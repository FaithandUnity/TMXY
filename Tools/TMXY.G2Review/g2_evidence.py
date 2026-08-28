#!/usr/bin/env python3
"""Hash binding and supplemental fact evaluation for the P2-20 G2 review."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path.name}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and bool(re.fullmatch(r"[0-9a-f]{64}", value))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def is_safe_relative(relative: str) -> bool:
    candidate = Path(relative)
    return (bool(relative) and "\\" not in relative and not relative.startswith("/") and
            not candidate.is_absolute() and ".." not in candidate.parts)


def resolve_inside(root: Path, relative: str) -> Path:
    require(is_safe_relative(relative), "Path is not repository-relative")
    candidate = (root / relative).resolve()
    require(candidate.is_relative_to(root), "Path escaped repository root")
    require(candidate.is_file(), f"Required input is missing: {relative}")
    return candidate


def verify_contract_binding(root: Path, document: dict[str, Any], label: str) -> None:
    contracts = document.get("contracts", {})
    for kind in ("policy", "schema"):
        relative = contracts.get(kind)
        require(isinstance(relative, str), f"{label} {kind} contract path is absent")
        path = resolve_inside(root, relative)
        require(contracts.get(f"{kind}_sha256") == sha256(path),
                f"{label} {kind} contract hash drifted")


def bind_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    bindings: list[dict[str, Any]] = []
    evidence: dict[str, dict[str, Any]] = {}
    aggregate_lines: list[str] = []
    for specification in policy["required_inputs"]:
        task_id = specification["task_id"]
        relative = specification["path"]
        path = resolve_inside(root, relative)
        document = load_json(path)
        observed_task = document.get("task_id", document.get("task"))
        require(observed_task == task_id, f"Task identity mismatch for {task_id}")
        require(document.get("result") == "PASS", f"Prerequisite {task_id} did not pass")
        require(document.get("task_status") == "COMPLETE", f"Prerequisite {task_id} is incomplete")
        require(document.get("completion_criteria_satisfied") is True,
                f"Prerequisite {task_id} is not complete")
        digest = sha256(path)
        bindings.append({
            "task_id": task_id,
            "path": relative,
            "sha256": digest,
            "result": "PASS",
            "task_status": "COMPLETE",
            "completion_criteria_satisfied": True,
        })
        evidence[task_id] = document
        aggregate_lines.append(f"{task_id}|{relative}|{digest}")

    supplemental_spec = policy["supplemental"]
    supplemental_relative = supplemental_spec["path"]
    supplemental_path = resolve_inside(root, supplemental_relative)
    supplemental = load_json(supplemental_path)
    require(supplemental.get("task_id") == supplemental_spec["task_id"] and
            supplemental.get("criterion_id") == supplemental_spec["criterion_id"] and
            supplemental.get("source_build") == policy["source_build"],
            "P2-20A supplemental identity mismatch")
    require(supplemental.get("review_execution_result") == "PASS",
            "P2-20A supplemental review did not execute successfully")
    supplemental_complete = (supplemental.get("result") == "PASS" and
                             supplemental.get("task_status") == "COMPLETE" and
                             supplemental.get("completion_criteria_satisfied") is True)
    supplemental_blocked = (supplemental.get("result") == "BLOCKED" and
                            supplemental.get("task_status") == "BLOCKED" and
                            supplemental.get("completion_criteria_satisfied") is False)
    require(supplemental_complete or supplemental_blocked,
            "P2-20A supplemental state is inconsistent")
    verify_contract_binding(root, supplemental, "P2-20A supplemental")
    require(not any(bool(supplemental.get("disclosure", {}).get(name)) for name in
                    ("private_source_paths", "exact_primary_keys", "raw_table_rows",
                     "decoded_confidential_payloads", "legacy_source_lines")),
            "P2-20A supplemental disclosure boundary failed")
    supplemental_digest = sha256(supplemental_path)
    supplemental_binding = {
        "task_id": supplemental_spec["task_id"],
        "criterion_id": supplemental_spec["criterion_id"],
        "path": supplemental_relative,
        "sha256": supplemental_digest,
        "result": supplemental["result"],
        "review_execution_result": supplemental["review_execution_result"],
        "task_status": supplemental["task_status"],
        "completion_criteria_satisfied": supplemental["completion_criteria_satisfied"],
    }
    evidence[supplemental_spec["task_id"]] = supplemental
    aggregate_lines.append(
        f"SUPPLEMENTAL|{supplemental_spec['task_id']}|{supplemental_spec['criterion_id']}|"
        f"{supplemental_relative}|{supplemental_digest}")

    remediation_spec = policy["remediation"]
    remediation_relative = remediation_spec["path"]
    remediation_path = resolve_inside(root, remediation_relative)
    remediation = load_json(remediation_path)
    require(remediation.get("task_id") == remediation_spec["task_id"] and
            remediation.get("gate_criterion") == remediation_spec["criterion_id"] and
            remediation.get("source_build") == policy["source_build"],
            "P2-20B remediation identity mismatch")
    require(remediation.get("generation_result") == "PASS",
            "P2-20B remediation generation did not pass")
    remediation_complete = (remediation.get("result") == "PASS" and
                            remediation.get("task_status") == "COMPLETE" and
                            remediation.get("completion_criteria_satisfied") is True and
                            remediation.get("g2_07_satisfied") is True)
    remediation_blocked = (remediation.get("result") == "BLOCKED" and
                           remediation.get("task_status") == "BLOCKED" and
                           remediation.get("completion_criteria_satisfied") is False and
                           remediation.get("g2_07_satisfied") is False)
    require(remediation_complete or remediation_blocked,
            "P2-20B remediation state is inconsistent")
    verify_contract_binding(root, remediation, "P2-20B remediation")
    require(not any(bool(remediation.get("disclosure", {}).get(name)) for name in
                    ("table_or_field_names", "legacy_source_paths", "exact_primary_keys",
                     "exact_observed_extrema", "raw_table_rows", "legacy_source_lines",
                     "matched_literal_values")),
            "P2-20B remediation disclosure boundary failed")
    remediation_digest = sha256(remediation_path)
    remediation_binding = {
        "task_id": remediation_spec["task_id"],
        "criterion_id": remediation_spec["criterion_id"],
        "path": remediation_relative,
        "sha256": remediation_digest,
        "result": remediation["result"],
        "generation_result": remediation["generation_result"],
        "task_status": remediation["task_status"],
        "completion_criteria_satisfied": remediation["completion_criteria_satisfied"],
        "g2_07_satisfied": remediation["g2_07_satisfied"],
    }
    evidence[remediation_spec["task_id"]] = remediation
    aggregate_lines.append(
        f"REMEDIATION|{remediation_spec['task_id']}|{remediation_spec['criterion_id']}|"
        f"{remediation_relative}|{remediation_digest}")

    quality_relative = policy["quality_evidence"]
    quality_path = resolve_inside(root, quality_relative)
    quality = load_json(quality_path)
    repository = quality.get("repository", {})
    secret = quality.get("secret", {})
    require(quality.get("result") == "PASS_DIAGNOSTIC", "Local quality aggregate did not pass")
    require(repository.get("result") == "PASS" and repository.get("failure_count") == 0,
            "Repository policy evidence did not pass")
    require(secret.get("result") == "PASS" and secret.get("failure_count") == 0 and
            secret.get("finding_count") == 0, "Secret evidence did not pass")
    quality_digest = sha256(quality_path)
    aggregate_lines.append(f"QUALITY|{quality_relative}|{quality_digest}")
    joined = ("\n".join(aggregate_lines) + "\n").encode("utf-8")
    return {
        "aggregate_sha256": hashlib.sha256(joined).hexdigest(),
        "prerequisites": bindings,
        "supplemental": supplemental_binding,
        "remediation": remediation_binding,
        "quality": {
            "path": quality_relative,
            "sha256": quality_digest,
            "result": quality["result"],
            "captured_utc": quality["captured_utc"],
        },
    }, evidence


def evaluate_core_closure(root: Path, report: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    scope = report["scope_definition"]
    declared_roots = scope["declared_roots"]
    resource_rules = scope["core_table_resource_rules"]
    auxiliary = scope["auxiliary_config"]
    closure = report["closure"]
    resolution = closure["resolution"]
    conditional = closure["conditional_required"]
    asset_structure = closure["asset_structure"]
    integrity = closure["integrity"]
    p213_sha = sha256(resolve_inside(root, "Data/Inventory/p2-13-reference-closure.json"))
    artifacts = {item["id"]: item for item in report["input_bindings"]["artifacts"]}
    conditional_source_bound = (conditional["source_inventory_id"] == "P2-13" and
                                conditional["source_inventory_sha256"] == p213_sha and
                                artifacts.get("P2-13", {}).get("sha256") == p213_sha)
    declared_scope_bound = (scope["mode"] == "monotonic-union" and
                            scope["outcome_based_exclusion"] is False and
                            declared_roots["selection"] == "all-declared-roots" and
                            declared_roots["count"] > 0 and is_sha256(declared_roots["set_sha256"]) and
                            resource_rules["selection"] == "all-matching-core-resource-rules" and
                            resource_rules["declared_rules"] == resource_rules["selected_rules"] and
                            resource_rules["owner_filtering"] == "forbidden" and
                            is_sha256(resource_rules["selection_sha256"]) and
                            is_sha256(closure["start_set_sha256"]) and
                            is_sha256(closure["reachable_set_sha256"]))
    member_set_hash_bound = (conditional["member_set_exported"] is True and
                             is_sha256(conditional["member_set_sha256"]))
    first_candidate_used = not (scope["outcome_based_exclusion"] is False and
                                resource_rules["selection"] == "all-matching-core-resource-rules" and
                                resolution["heuristic_target_selections"] == 0)
    integrity_mismatches = (integrity["recorded_resolution_mismatches"] +
                            integrity["catalog_candidate_mismatches"])
    logical_gap_sum = (resolution["table_unresolved"] + resolution["table_ambiguous"] +
                       resolution["package_unresolved"] + resolution["package_ambiguous"])
    logical_gap_set_bound = (closure["logical_gap_count"] == logical_gap_sum and
                             is_sha256(closure["gap_set_sha256"]))
    satisfied = (declared_scope_bound and closure["scope_complete"] == thresholds["core_scope_complete"] and
                 auxiliary["scope_complete"] == thresholds["core_auxiliary_config_scope_complete"] and
                 closure["auxiliary_config_reference_scope_complete"] ==
                 thresholds["core_auxiliary_config_scope_complete"] and
                 closure["asset_binding_resolution_explicit"] ==
                 thresholds["core_asset_binding_resolution_explicit"] and
                 resolution["table_unresolved"] == thresholds["core_table_resource_unresolved"] and
                 resolution["table_ambiguous"] == thresholds["core_table_resource_ambiguous"] and
                 resolution["package_unresolved"] == thresholds["core_package_resource_unresolved"] and
                 resolution["package_ambiguous"] == thresholds["core_package_resource_ambiguous"] and
                 conditional["conditional_required_missing"] ==
                 thresholds["core_conditional_required_missing"] and
                 conditional["member_set_exported"] == thresholds["core_member_set_exported"] and
                 member_set_hash_bound and conditional_source_bound and
                 resolution["heuristic_target_selections"] ==
                 thresholds["core_heuristic_target_selections"] and not first_candidate_used and
                 asset_structure["unresolved"] == thresholds["core_asset_structure_unresolved"] and
                 asset_structure["fail"] == thresholds["core_asset_structure_fail"] and
                 integrity["unknown_record_count"] == thresholds["core_unknown_record_count"] and
                 integrity["unknown_resolution_count"] == thresholds["core_unknown_resolution_count"] and
                 integrity_mismatches == thresholds["core_integrity_mismatches"] and logical_gap_set_bound)
    require(report["decision"]["satisfied"] is satisfied,
            "P2-20A decision does not match independently recomputed closure facts")
    return {
        "satisfied": satisfied, "declared_scope_bound": declared_scope_bound,
        "scope_complete": closure["scope_complete"],
        "auxiliary_complete": closure["auxiliary_config_reference_scope_complete"],
        "asset_binding_explicit": closure["asset_binding_resolution_explicit"],
        "table_unresolved": resolution["table_unresolved"],
        "table_ambiguous": resolution["table_ambiguous"],
        "package_unresolved": resolution["package_unresolved"],
        "package_ambiguous": resolution["package_ambiguous"],
        "conditional_missing": conditional["conditional_required_missing"],
        "member_set_exported": conditional["member_set_exported"],
        "member_set_hash_bound": member_set_hash_bound,
        "conditional_source_bound": conditional_source_bound,
        "heuristic": resolution["heuristic_target_selections"],
        "first_candidate_used": first_candidate_used,
        "asset_unresolved": asset_structure["unresolved"], "asset_fail": asset_structure["fail"],
        "unknown_records": integrity["unknown_record_count"],
        "unknown_resolutions": integrity["unknown_resolution_count"],
        "integrity_mismatches": integrity_mismatches,
        "logical_gap_count": closure["logical_gap_count"],
        "logical_gap_set_bound": logical_gap_set_bound,
        "core_fk_dangling": integrity["core_foreign_key_dangling"],
    }


def evaluate_migration_registry(registry: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    summary = registry["summary"]
    completeness = registry["completeness"]
    decisions = registry["decisions"]
    pending = sum(item["decision"]["status"] == "PENDING" for item in decisions)
    decided = sum(item["decision"]["status"] == "DECIDED" for item in decisions)
    approved = sum(item["approval"]["status"] == "APPROVED" and
                   item["approval"]["external_authority_verified"] is True for item in decisions)
    approval_count = sum(item["approval"]["approval_count"] for item in decisions)
    suggestions = sum(item.get("machine_suggestion") is not None for item in decisions)
    suggestions_non_authoritative = all(
        item.get("machine_suggestion", {}).get("counts_as_decision") is False for item in decisions)
    pending_empty = all(item["decision"]["status"] != "PENDING" or
                        (item["decision"]["chosen_action"] is None and
                         item["approval"]["approval_count"] == 0) for item in decisions)
    require(summary["enumerated_units"] == len(decisions) and summary["pending"] == pending and
            summary["decided"] == decided and summary["approved"] == approved and
            summary["approval_count"] == approval_count,
            "P2-20B summary does not match the complete decision registry")
    coverage = (summary["expected_units"] == thresholds["migration_expected_units"] and
                summary["enumerated_units"] == thresholds["migration_expected_units"] and
                completeness["coverage_complete"] is True and
                completeness["missing"] == thresholds["migration_missing"] and
                completeness["duplicates"] == thresholds["migration_duplicates"] and
                completeness["orphans"] == thresholds["migration_orphans"] and
                completeness["reference_membership_enumerated"] is True and
                completeness["all_inputs_hash_bound"] is True)
    satisfied = (coverage and summary["pending"] == thresholds["migration_pending"] and
                 summary["decided"] == thresholds["migration_decided"] and
                 summary["approved"] == thresholds["migration_approved"] and
                 summary["approval_count"] >= thresholds["migration_minimum_approval_count"] and
                 completeness["decisions_complete"] is True and
                 completeness["approvals_complete"] is True and suggestions_non_authoritative and
                 pending_empty and registry["authority_boundaries"]["machine_can_approve"] is False and
                 registry["g2_07_satisfied"] is True)
    return {
        "satisfied": satisfied, "coverage": coverage,
        "expected": summary["expected_units"], "enumerated": summary["enumerated_units"],
        "missing": completeness["missing"], "duplicates": completeness["duplicates"],
        "orphans": completeness["orphans"], "pending": summary["pending"],
        "decided": summary["decided"], "approved": summary["approved"],
        "approval_count": summary["approval_count"], "suggestions": suggestions,
        "suggestions_count_as_decisions": not suggestions_non_authoritative,
        "pending_empty": pending_empty, "registry_satisfied": registry["g2_07_satisfied"],
    }
