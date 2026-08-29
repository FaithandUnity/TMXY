#!/usr/bin/env python3
"""Hash binding and supplemental fact evaluation for the P2-20 G2 review."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path
from typing import Any
from g2_descriptor import bind_descriptor_diagnostics
from g2_aux_semantic import bind_aux_semantic_diagnostics
from g2_identity_normalization import bind_identity_normalization_safety
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
    kinds = ["policy", "schema"]
    kinds.extend(kind for kind in ("authority_schema", "review_packet_schema")
                 if kind in contracts)
    for kind in kinds:
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
    descriptor_binding, descriptor, descriptor_aggregate = bind_descriptor_diagnostics(
        root, policy, load_json, resolve_inside, sha256, require)
    evidence["P2-20A.4"] = descriptor
    aggregate_lines.append(descriptor_aggregate)
    aux_semantic_binding, aux_semantic, aux_semantic_aggregate = bind_aux_semantic_diagnostics(
        root, policy, load_json, resolve_inside, sha256, require)
    evidence["P2-20A.5"] = aux_semantic
    aggregate_lines.append(aux_semantic_aggregate)

    identity_binding, identity_safety, identity_aggregate = bind_identity_normalization_safety(
        root, policy, load_json, resolve_inside, sha256, require)
    evidence["P2-20A.6"] = identity_safety
    aggregate_lines.append(identity_aggregate)

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
        "descriptor_diagnostics": descriptor_binding,
        "aux_semantic_diagnostics": aux_semantic_binding,
        "identity_normalization_safety": identity_binding,
        "remediation": remediation_binding,
        "quality": {
            "path": quality_relative,
            "sha256": quality_digest,
            "result": quality["result"],
            "captured_utc": quality["captured_utc"],
        },
    }, evidence


def evaluate_auxiliary_binding(root: Path, report: dict[str, Any],
                               scope: dict[str, Any]) -> dict[str, Any]:
    artifacts = report["input_bindings"]["artifacts"]
    by_id: dict[str, list[dict[str, Any]]] = {}
    for item in artifacts:
        by_id.setdefault(str(item["id"]), []).append(item)
    require(len(by_id.get("P2-20A.3-AUX", [])) == 1,
            "P2-20A.3 auxiliary binding is missing or duplicated")
    binding = by_id["P2-20A.3-AUX"][0]
    relative = "Data/Reports/p2-20a-aux-config-reference-report.json"
    require(binding["path"] == relative, "P2-20A.3 auxiliary path drifted")
    path = resolve_inside(root, relative)
    auxiliary = load_json(path)
    require(binding["sha256"] == sha256(path) and
            binding["bytes"] == path.stat().st_size,
            "P2-20A.3 auxiliary report hash or size drifted")
    policy_path = resolve_inside(
        root, "Contracts/data-schema/g2-auxiliary-config-reference-policy-v1.json")
    schema_path = resolve_inside(
        root, "Contracts/data-schema/g2-auxiliary-config-reference-v1.schema.json")
    require(len(by_id.get("auxiliary-reference-policy", [])) == 1 and
            len(by_id.get("auxiliary-reference-schema", [])) == 1 and
            by_id["auxiliary-reference-policy"][0]["sha256"] == sha256(policy_path) and
            by_id["auxiliary-reference-schema"][0]["sha256"] == sha256(schema_path) and
            auxiliary["contracts"]["policy_sha256"] == sha256(policy_path) and
            auxiliary["contracts"]["schema_sha256"] == sha256(schema_path),
            "P2-20A.3 auxiliary contracts are not exactly hash-bound")
    measured = auxiliary["measured_lexical_candidates"]
    states = auxiliary["adapter_state_summary"]
    semantic = auxiliary["semantic_resolution"]
    closure = auxiliary["config_closure"]
    require(auxiliary["evidence_revision"] == "P2-20A.3" and
            auxiliary["task_id"] == "P2-20A" and auxiliary["criterion_id"] == "G2-06" and
            auxiliary["result"] == "BLOCKED" and
            auxiliary["review_execution_result"] == "PASS" and
            auxiliary["task_status"] == "BLOCKED" and
            auxiliary["completion_criteria_satisfied"] is False and
            auxiliary["scope_complete"] is False and
            auxiliary["g2_06_satisfied"] is False and auxiliary["p3_authorized"] is False,
            "P2-20A.3 auxiliary state was falsely promoted")
    require(len(auxiliary["file_instances"]) == 212 and
            measured["measurement_authority"] == "LEXICAL_ONLY" and
            measured["file_instances"] == 212 and measured["unique_content_bodies"] == 196 and
            measured["parsed_file_instances"] == 206 and measured["malformed_file_instances"] == 6 and
            measured["asset_exact_occurrences"] == 3043 and
            measured["package_exact_occurrences"] == 638 and
            measured["package_unique_occurrences"] == 218 and
            measured["package_ambiguous_occurrences"] == 420 and
            measured["package_ambiguous_candidate_edges"] == 1136 and
            measured["config_exact_edges"] == 8,
            "P2-20A.3 measured lexical baseline drifted")
    require(states == {"file_instances": 212, "terminal_file_instances": 0,
                       "nonterminal_file_instances": 212, "semantic_approved": 0,
                       "no_ref_approved": 0, "candidate_only": 171,
                       "malformed_blocked": 6, "editor_undecided": 35,
                       "approved_roots": 0} and semantic["status"] == "UNASSESSED" and
            all(semantic[name] is None for name in
                ("unknown_occurrences", "ambiguous_occurrences",
                 "unresolved_occurrences", "resolved_occurrences")) and
            semantic["first_candidate_selections"] == 0 and
            semantic["heuristic_target_selections"] == 0 and
            closure["approved_root_count"] == 0 and closure["closure_complete"] is False and
            closure["cycle_detection_complete"] is False,
            "P2-20A.3 semantic or closure state was inferred without approval")
    require(scope == {
        "evidence_revision": "P2-20A.3", "evidence_hash_bound": True,
        "measurement_authority": "LEXICAL_ONLY", "inventory_files": 212,
        "unique_content_bodies": 196, "parsed_file_instances": 206,
        "malformed_isolated": 6, "scalar_positions": 39522,
        "nonempty_scalar_positions": 39498, "asset_exact_occurrences": 3043,
        "package_exact_occurrences": 638, "config_exact_edges": 8,
        "reference_adapters": 0,
        "reference_adapter_coverage": "lexical-candidate-inventory-only",
        "terminal_file_instances": 0, "candidate_only": 171,
        "editor_undecided": 35, "malformed_blocked": 6,
        "semantic_approved": 0, "no_ref_approved": 0, "approved_roots": 0,
        "exact_complete_scalar_matching": True, "first_candidate_selection_used": False,
        "new_roots_are_union_only": True, "scope_complete": False,
    }, "Core auxiliary summary does not exactly match P2-20A.3")
    metrics = [
        ("auxiliary_reference_evidence_hash_bound", True, "boolean"),
        ("auxiliary_file_instances", 212, "files"),
        ("auxiliary_terminal_file_instances", 0, "files"),
        ("auxiliary_nonterminal_file_instances", 212, "files"),
        ("auxiliary_candidate_only", 171, "files"),
        ("auxiliary_editor_undecided", 35, "files"),
        ("auxiliary_malformed_blocked", 6, "files"),
        ("auxiliary_semantic_approved", 0, "files"),
        ("auxiliary_no_ref_approved", 0, "files"),
        ("auxiliary_approved_roots", 0, "roots"),
        ("auxiliary_asset_exact_occurrences", 3043, "occurrences"),
        ("auxiliary_package_exact_occurrences", 638, "occurrences"),
        ("auxiliary_package_unique_occurrences", 218, "occurrences"),
        ("auxiliary_package_ambiguous_occurrences", 420, "occurrences"),
        ("auxiliary_package_ambiguous_candidate_edges", 1136, "edges"),
        ("auxiliary_config_exact_edges", 8, "edges"),
        ("auxiliary_semantic_status", "UNASSESSED", "state"),
        ("auxiliary_config_closure_complete", False, "boolean"),
        ("auxiliary_cycle_detection_complete", False, "boolean"),
    ]
    return {"bound": True, "metrics": metrics, "report": auxiliary}


def evaluate_core_closure(root: Path, report: dict[str, Any],
                          descriptor: dict[str, Any],
                          thresholds: dict[str, Any]) -> dict[str, Any]:
    scope = report["scope_definition"]
    declared_roots = scope["declared_roots"]
    resource_rules = scope["core_table_resource_rules"]
    auxiliary = scope["auxiliary_config"]
    auxiliary_context = evaluate_auxiliary_binding(root, report, auxiliary)
    closure = report["closure"]
    resolution = closure["resolution"]
    conditional = closure["conditional_required"]
    asset_structure = closure["asset_structure"]
    asset_binding = closure["asset_binding"]
    descriptor_measured = descriptor["measured"]
    reconciled = descriptor_measured["reconciled_full_workset"]
    descriptor_bound = (descriptor["diagnostic_scope_complete"] is True and
                        descriptor["review_execution_result"] == "PASS" and
                        descriptor["scope"]["targets"] == 3651 and
                        descriptor["scope"]["candidate_edges"] == 12764 and
                        descriptor["scope"]["candidate_identity_exact"] is True and
                        descriptor["scope"]["production_binder_used"] is True and
                        descriptor["scope"]["first_candidate_selection_used"] is False and
                        descriptor_measured["descriptor_parsed_candidates"] == 12764 and
                        descriptor_measured["descriptor_rejected_candidates"] == 0 and
                        reconciled["targets"] == asset_binding["reachable_assets"] and
                        reconciled["candidate_edges"] == asset_binding["candidate_edges"] and
                        reconciled["resolved_targets"] + reconciled["ambiguous_targets"] +
                        reconciled["unresolved_targets"] + reconciled["unknown_targets"] ==
                        reconciled["targets"] and
                        reconciled["resolved_edges"] + reconciled["ambiguous_edges"] +
                        reconciled["unresolved_edges"] + reconciled["unknown_edges"] ==
                        reconciled["candidate_edges"] and
                        is_sha256(descriptor["detail_export"]["sha256"]))
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
                             conditional["member_set_count"] ==
                             conditional["conditional_required_missing"] and
                             is_sha256(conditional["member_set_sha256"]))
    first_candidate_used = not (scope["outcome_based_exclusion"] is False and
                                resource_rules["selection"] == "all-matching-core-resource-rules" and
                                resolution["heuristic_target_selections"] == 0 and
                                asset_binding["first_candidate_selection_used"] is False)
    integrity_mismatches = (integrity["recorded_resolution_mismatches"] +
                            integrity["catalog_candidate_mismatches"])
    logical_gap_sum = (resolution["table_unresolved"] + resolution["table_ambiguous"] +
                       resolution["package_unresolved"] + resolution["package_ambiguous"])
    logical_gap_set_bound = (closure["logical_gap_count"] == logical_gap_sum and
                             is_sha256(closure["gap_set_sha256"]))
    satisfied = (declared_scope_bound and auxiliary_context["bound"] and descriptor_bound and
                 closure["scope_complete"] == thresholds["core_scope_complete"] and
                 auxiliary["scope_complete"] == thresholds["core_auxiliary_config_scope_complete"] and
                 closure["auxiliary_config_reference_scope_complete"] ==
                 thresholds["core_auxiliary_config_scope_complete"] and
                 closure["asset_binding_resolution_explicit"] ==
                 thresholds["core_asset_binding_resolution_explicit"] and
                 reconciled["ambiguous_targets"] == thresholds["core_asset_binding_ambiguous"] and
                 reconciled["unresolved_targets"] == thresholds["core_asset_binding_unresolved"] and
                 reconciled["unknown_targets"] == thresholds["core_asset_binding_unknown"] and
                 reconciled["targets"] == asset_binding["workset_count"] and
                 is_sha256(asset_binding["workset_sha256"]) and
                 asset_binding["first_candidate_selection_used"] is False and
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
        "auxiliary_evidence_bound": auxiliary_context["bound"],
        "descriptor_diagnostic_bound": descriptor_bound,
        "descriptor_diagnostic_targets": descriptor["scope"]["targets"],
        "descriptor_diagnostic_edges": descriptor["scope"]["candidate_edges"],
        "descriptor_diagnostic_resolved": descriptor_measured["resolved_targets"],
        "descriptor_diagnostic_ambiguous": descriptor_measured["ambiguous_targets"],
        "descriptor_diagnostic_unresolved": descriptor_measured["unresolved_targets"],
        "auxiliary_metrics": auxiliary_context["metrics"],
        "scope_complete": closure["scope_complete"],
        "auxiliary_complete": closure["auxiliary_config_reference_scope_complete"],
        "asset_binding_explicit": closure["asset_binding_resolution_explicit"],
        "asset_binding_resolved": reconciled["resolved_targets"],
        "asset_binding_ambiguous": reconciled["ambiguous_targets"],
        "asset_binding_unresolved": reconciled["unresolved_targets"],
        "asset_binding_unknown": reconciled["unknown_targets"],
        "asset_binding_workset_bound": (asset_binding["reachable_assets"] ==
                                         asset_binding["workset_count"] and
                                         is_sha256(asset_binding["workset_sha256"])),
        "table_unresolved": resolution["table_unresolved"],
        "table_ambiguous": resolution["table_ambiguous"],
        "package_unresolved": resolution["package_unresolved"],
        "package_ambiguous": resolution["package_ambiguous"],
        "conditional_missing": conditional["conditional_required_missing"],
        "member_set_exported": conditional["member_set_exported"],
        "member_set_count": conditional["member_set_count"],
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
    verified = sum(item["verification"]["status"] == "PASS" for item in decisions)
    suggestions = sum(item.get("machine_suggestion") is not None for item in decisions)
    suggestions_non_authoritative = all(
        item.get("machine_suggestion", {}).get("counts_as_decision") is False for item in decisions)
    pending_empty = all(item["decision"]["status"] != "PENDING" or
                        (item["decision"]["chosen_action"] is None and
                         item["approval"]["approval_count"] == 0) for item in decisions)
    require(summary["enumerated_units"] == len(decisions) and summary["pending"] == pending and
            summary["decided"] == decided and summary["approved"] == approved and
            summary["approval_count"] == approval_count and summary["verified"] == verified,
            "P2-20B summary does not match the complete decision registry")
    packets = registry["review_packets"]
    workflow_ready = (registry["schema_version"] == thresholds["migration_workflow_version"] and
                      registry["workflow_version"] == thresholds["migration_workflow_version"] and
                      completeness["review_packets_complete"] is True and
                      packets["packet_count"] == thresholds["migration_review_packets"] and
                      packets["member_count"] == thresholds["migration_review_packet_members"] and
                      is_sha256(packets["sha256"]) and
                      is_sha256(packets["aggregate_membership_sha256"]) and
                      registry["authority_boundaries"]["machine_can_approve"] is False)
    coverage = (summary["expected_units"] == thresholds["migration_expected_units"] and
                summary["enumerated_units"] == thresholds["migration_expected_units"] and
                completeness["coverage_complete"] is True and
                completeness["missing"] == thresholds["migration_missing"] and
                completeness["duplicates"] == thresholds["migration_duplicates"] and
                completeness["orphans"] == thresholds["migration_orphans"] and
                completeness["reference_membership_enumerated"] is True and
                completeness["all_inputs_hash_bound"] is True)
    satisfied = (coverage and workflow_ready and
                 summary["pending"] == thresholds["migration_pending"] and
                 summary["decided"] == thresholds["migration_decided"] and
                 summary["approved"] == thresholds["migration_approved"] and
                 summary["verified"] == thresholds["migration_verified"] and
                 summary["approval_count"] >= thresholds["migration_minimum_approval_count"] and
                 completeness["decisions_complete"] is True and
                 completeness["approvals_complete"] is True and
                 completeness["verification_complete"] is True and suggestions_non_authoritative and
                 pending_empty and registry["authority_boundaries"]["machine_can_approve"] is False and
                 registry["g2_07_satisfied"] is True)
    return {
        "satisfied": satisfied, "coverage": coverage, "workflow_ready": workflow_ready,
        "workflow_version": registry["workflow_version"],
        "review_packets": packets["packet_count"],
        "review_packet_members": packets["member_count"],
        "authority_records": registry["authority_boundaries"]["authority_ledger_records"],
        "expected": summary["expected_units"], "enumerated": summary["enumerated_units"],
        "missing": completeness["missing"], "duplicates": completeness["duplicates"],
        "orphans": completeness["orphans"], "pending": summary["pending"],
        "decided": summary["decided"], "approved": summary["approved"],
        "verified": summary["verified"],
        "approval_count": summary["approval_count"], "suggestions": suggestions,
        "suggestions_count_as_decisions": not suggestions_non_authoritative,
        "pending_empty": pending_empty, "registry_satisfied": registry["g2_07_satisfied"],
    }
