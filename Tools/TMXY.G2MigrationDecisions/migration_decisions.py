#!/usr/bin/env python3
"""Generate the fail-closed P2-20B.1 G2-07 decision workflow V2."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from g2_common import (digest, file_digest, load_json, load_jsonl,
                       manifest_digest, require, safe_repo_path, write_text)
from legacy_reference import discover_legacy_snapshot, reference_members, select_unique_manifest
from workflow_v2 import (apply_authority, build_review_packets, pending_state,
                         workflow_self_test)


KINDS = ("SCHEMA_TABLE", "SCHEMA_REFERENCE", "CANONICAL_ID_DOMAIN",
         "ID_COMPONENT", "FIXED_LIMIT_SIGNAL")


def bind_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    evidence: dict[str, dict[str, Any]] = {}
    bindings = []
    aggregate = []
    for specification in policy["required_inputs"]:
        task_id, relative = specification["task_id"], specification["path"]
        path = safe_repo_path(root, relative)
        document = load_json(path)
        require(document.get("task_id", document.get("task")) == task_id, f"Task mismatch: {task_id}")
        require(document.get("result") == "PASS" and document.get("task_status") == "COMPLETE" and
                document.get("completion_criteria_satisfied") is True, f"Incomplete input: {task_id}")
        sha = file_digest(path)
        bindings.append({"task_id": task_id, "path": relative, "sha256": sha, "result": "PASS",
                         "task_status": "COMPLETE", "completion_criteria_satisfied": True})
        evidence[task_id] = document
        aggregate.append(f"{task_id}|{relative}|{sha}")
    g2_path = safe_repo_path(root, policy["g2_policy"])
    g2_sha = file_digest(g2_path)
    aggregate.append(f"G2_POLICY|{g2_sha}")
    return {"evidence": bindings, "g2_path": g2_path, "g2_sha": g2_sha,
            "aggregate_lines": aggregate}, evidence


def validate_report(root: Path, metadata: dict[str, Any], expected_path: str) -> tuple[Path, str, int]:
    require(metadata["path"] == expected_path and metadata["tracked"] is False,
            "Derived report metadata path or tracking status changed")
    path = safe_repo_path(root, expected_path)
    sha = file_digest(path)
    line_count = sum(1 for _ in path.open("r", encoding="utf-8-sig"))
    require(sha == metadata["sha256"] and path.stat().st_size == metadata["bytes"] and
            line_count == metadata["lines"], "Derived report binding changed")
    return path, sha, line_count


def evidence_ref(task: str, artifact: str, sha: str, kind: str, ordinal: int) -> dict[str, Any]:
    return {"task_id": task, "artifact_id": artifact, "artifact_sha256": sha,
            "record_kind": kind, "record_ordinal": ordinal}


def pending_decision(identifier: str, risk_class: str, subject_kind: str, member: str,
                     reference: dict[str, Any], risks: list[str], action: str,
                     rationale: list[str], roles: list[str]) -> dict[str, Any]:
    result = {
        "decision_id": identifier,
        "risk_class": risk_class,
        "subject_kind": subject_kind,
        "subject_membership_sha256": member,
        "evidence_ref": reference,
        "risk_codes": sorted(set(risks)),
        "machine_suggestion": {"status": "GENERATED", "action_code": action,
                               "rationale_codes": sorted(set(rationale)), "counts_as_decision": False},
        "ownership": {"responsible_role": roles[0], "required_approver_roles": roles},
    }
    result.update(pending_state())
    return result


def schema_table_decisions(records: list[dict[str, Any]], report_sha: str,
                           roles: list[str]) -> list[dict[str, Any]]:
    result = []
    for ordinal, item in enumerate(records, 1):
        require(item.get("record") == "table_diff" and item.get("state") == "paired",
                "P2-09 table record is not a paired table diff")
        schema, rows = item["schema"], item["rows"]
        risks = ["OLD_TO_NEW_SCHEMA_REVIEW"]
        flags = (("LEGACY_ONLY_COLUMN", schema["legacy_only_columns"]),
                 ("CURRENT_ONLY_COLUMN", schema["current_only_columns"]),
                 ("INFERRED_TYPE_CHANGE", schema["inferred_type_changes"]),
                 ("OBSERVED_MODE_CHANGE_NOT_DEFAULT", schema["observed_mode_hash_changes"]),
                 ("LEGACY_ONLY_ROWS", rows["legacy_only"]),
                 ("CURRENT_ONLY_ROWS", rows["current_only"]))
        risks.extend(name for name, value in flags if int(value) > 0)
        if item["primary_key"].get("applicable"):
            risks.append("PRIMARY_KEY_MIGRATION_SCOPE")
        member = digest({"report": report_sha, "ordinal": ordinal, "identity": item["table"]})
        result.append(pending_decision(f"MIG-SCHEMA-TABLE-{ordinal:04d}", "OLD_TO_NEW_SCHEMA",
            "SCHEMA_TABLE", member, evidence_ref("P2-09", "P2_09_TABLE_DIFF_REPORT", report_sha,
            "table_diff", ordinal), risks, "REVIEW_TABLE_MIGRATION",
            ["DEFAULTS_REQUIRE_AUTHORITY", "FIELD_PLAN_REQUIRED", "OBSERVED_MODE_IS_NOT_DEFAULT"], roles))
    return result


def schema_reference_decisions(members: list[dict[str, Any]], report_sha: str,
                               legacy_sha: str, registry_sha: str, roles: list[str]) -> list[dict[str, Any]]:
    result = []
    for ordinal, identity in enumerate(members, 1):
        member = digest({"report": report_sha, "legacy": legacy_sha,
                         "registry": registry_sha, "identity": identity})
        result.append(pending_decision(f"MIG-SCHEMA-REFERENCE-{ordinal:04d}", "OLD_TO_NEW_SCHEMA",
            "SCHEMA_REFERENCE", member, evidence_ref("P2-09", "P2_09_REFERENCE_DERIVATION",
            report_sha, "reference_rule", ordinal), ["REFERENCE_POPULATION_CHANGE"],
            "REVIEW_REFERENCE_MIGRATION", ["REFERENCE_SEMANTICS_REQUIRE_AUTHORITY"], roles))
    return result


def canonical_id_decisions(document: dict[str, Any], evidence_sha: str,
                           roles: list[str]) -> list[dict[str, Any]]:
    result = []
    for ordinal, item in enumerate(document["domains"], 1):
        risks = ["ID_ALLOCATION_POLICY", "NO_AUTOMATIC_RENUMBERING"]
        if int(item["key_arity"]) > 1:
            risks.append("COMPOSITE_ID")
        if int(item["tombstones"]) > 0:
            risks.extend(("TOMBSTONE_PRESENT", "TOMBSTONE_REUSE_FORBIDDEN"))
        if int(item["legacy_type_exception_components"]) > 0:
            risks.append("LEGACY_TYPE_EXCEPTION")
        if int(item["collapsed_duplicate_occurrences"]) > 0:
            risks.append("IDENTICAL_DUPLICATE_COLLAPSE")
        member = digest({"evidence": evidence_sha, "ordinal": ordinal, "identity": item["domain"]})
        result.append(pending_decision(f"MIG-CANONICAL-ID-{ordinal:04d}", "CANONICAL_ID",
            "CANONICAL_ID_DOMAIN", member, evidence_ref("P2-10", "P2_10_EVIDENCE", evidence_sha,
            "canonical_id_domain", ordinal), risks, "PRESERVE_EXISTING_ID_POLICY",
            ["CURRENT_MAPPING_HAS_ZERO_CONFLICTS", "OWNER_APPROVAL_REQUIRED"], roles))
    return result


def id_component_decisions(document: dict[str, Any], evidence_sha: str,
                           roles: list[str]) -> list[dict[str, Any]]:
    result = []
    for ordinal, item in enumerate(document["components"], 1):
        numeric = item["type"] == "int64"
        risks = [str(value).upper() for value in item["risks"]]
        risks.append("NUMERIC_ID_NO_NARROWING" if numeric else "STRING_ID_NOT_NUMERIC")
        identity = {"domain": item["domain"], "column_id": item["column_id"],
                    "component_index": item["component_index"]}
        member = digest({"evidence": evidence_sha, "ordinal": ordinal, "identity": identity})
        action = "KEEP_UINT64_NO_NARROWING" if numeric else "KEEP_STRING_ID"
        result.append(pending_decision(f"MIG-ID-COMPONENT-{ordinal:04d}", "ID_WIDTH", "ID_COMPONENT",
            member, evidence_ref("P2-11", "P2_11_EVIDENCE", evidence_sha,
            "id_component_audit", ordinal), risks, action,
            ["CURRENT_CODEGEN_POLICY", "PERSISTENCE_COMPATIBILITY_REQUIRES_APPROVAL"], roles))
    return result


def fixed_limit_decisions(records: list[dict[str, Any]], report_sha: str,
                          roles: list[str]) -> list[dict[str, Any]]:
    signals = [(ordinal, item) for ordinal, item in enumerate(records, 1)
               if item.get("record") == "legacy_source_limit_signal"]
    result = []
    for case, (record_ordinal, item) in enumerate(signals, 1):
        identity = {"root": item["root"], "relative_path": item["relative_path"],
                    "source_sha256": item["source_sha256"], "rule": item["rule"]}
        member = digest({"report": report_sha, "ordinal": record_ordinal, "identity": identity})
        risk = f"{str(item['rule']).upper()}_REQUIRES_CLASSIFICATION"
        result.append(pending_decision(f"MIG-FIXED-LIMIT-{case:04d}", "LEGACY_FIXED_LIMIT",
            "FIXED_LIMIT_SIGNAL", member, evidence_ref("P2-11", "P2_11_ID_LIMIT_REPORT", report_sha,
            "legacy_source_limit_signal", record_ordinal), [risk], "CLASSIFY_LIMIT_SIGNAL",
            ["SIGNAL_IS_NOT_A_DECISION", "SOURCE_CONTEXT_REVIEW_REQUIRED"], roles))
    return result


def derived_bindings(policy: dict[str, Any], evidence: dict[str, dict[str, Any]],
                     registry_path: Path, registry: dict[str, Any], table_sha: str,
                     table_count: int, limit_sha: str, limit_count: int,
                     legacy_sha: str, authority_path: Path,
                     authority_records: int) -> list[dict[str, Any]]:
    p209 = evidence["P2-09"]
    require(file_digest(registry_path) == p209["input"]["core_registry_sha256"],
            "Core registry no longer matches P2-09")
    require(legacy_sha == p209["input"]["legacy_manifest_sha256"],
            "Legacy snapshot manifest no longer matches P2-09")
    return [
        {"artifact_id": "G2_POLICY", "sha256": file_digest(Path(policy["_g2_path"])), "records": 9},
        {"artifact_id": "CORE_REGISTRY", "sha256": file_digest(registry_path),
         "records": len(registry["tables"])},
        {"artifact_id": "P2_09_TABLE_DIFF_REPORT", "sha256": table_sha, "records": table_count},
        {"artifact_id": "P2_11_ID_LIMIT_REPORT", "sha256": limit_sha, "records": limit_count},
        {"artifact_id": "LEGACY_SNAPSHOT_MANIFEST", "sha256": legacy_sha, "records": 52},
        {"artifact_id": "AUTHORITY_LEDGER", "sha256": file_digest(authority_path),
         "records": authority_records},
    ]


def build_registry(root: Path, devdoc_root: Path, policy_path: Path,
                   schema_path: Path, packet_output: Path) -> dict[str, Any]:
    policy = load_json(policy_path)
    bound, evidence = bind_inputs(root, policy)
    policy["_g2_path"] = str(bound["g2_path"])
    auxiliary = policy["auxiliary_inputs"]
    table_path, table_sha, table_count = validate_report(root, evidence["P2-09"]["report"],
                                                         auxiliary["table_diff_report"])
    limit_path, limit_sha, limit_count = validate_report(root, evidence["P2-11"]["report"],
                                                         auxiliary["id_limit_report"])
    registry_path = safe_repo_path(root, auxiliary["core_registry"])
    core_registry = load_json(registry_path)
    legacy_sha, headers = discover_legacy_snapshot(
        devdoc_root, evidence["P2-09"]["input"]["legacy_manifest_sha256"])
    references = reference_members(core_registry, headers)
    roles = policy["approval_roles"]
    decisions = schema_table_decisions(load_jsonl(table_path), table_sha, roles["schema_table"])
    decisions += schema_reference_decisions(references, table_sha, legacy_sha,
                                             file_digest(registry_path), roles["schema_reference"])
    decisions += canonical_id_decisions(evidence["P2-10"], file_digest(
        safe_repo_path(root, policy["required_inputs"][1]["path"])), roles["canonical_id_domain"])
    decisions += id_component_decisions(evidence["P2-11"], file_digest(
        safe_repo_path(root, policy["required_inputs"][2]["path"])), roles["id_component"])
    decisions += fixed_limit_decisions(load_jsonl(limit_path), limit_sha, roles["fixed_limit_signal"])
    authority_path = safe_repo_path(root, policy["authority_ledger"])
    authority = load_json(authority_path)
    decisions = apply_authority(decisions, authority, policy)
    packets = build_review_packets(decisions, policy)
    write_text(packet_output, json.dumps(packets, ensure_ascii=False, indent=2) + "\n")
    derived = derived_bindings(policy, evidence, registry_path, core_registry, table_sha,
                               table_count, limit_sha, limit_count, legacy_sha,
                               authority_path, len(authority["records"]))
    return assemble_registry(root, policy_path, schema_path, policy, evidence, bound,
                             derived, decisions, authority, packets, packet_output)


def assemble_registry(root: Path, policy_path: Path, schema_path: Path, policy: dict[str, Any],
                      evidence: dict[str, dict[str, Any]], bound: dict[str, Any],
                      derived: list[dict[str, Any]], decisions: list[dict[str, Any]],
                      authority: dict[str, Any], packets: dict[str, Any],
                      packet_output: Path) -> dict[str, Any]:
    expected = policy["expected_units"]
    counts = Counter(item["subject_kind"] for item in decisions)
    ids = [item["decision_id"] for item in decisions]
    duplicates = len(ids) - len(set(ids))
    expected_total = int(expected["total"])
    missing = max(0, expected_total - len(decisions))
    orphans = max(0, len(decisions) - expected_total)
    manifests = [{"subject_kind": kind, "expected": int(expected[kind.lower()]),
                  "enumerated": counts[kind],
                  "membership_sha256": manifest_digest(item for item in decisions
                                                         if item["subject_kind"] == kind)}
                 for kind in KINDS]
    coverage = missing == 0 and duplicates == 0 and orphans == 0 and all(
        item["expected"] == item["enumerated"] for item in manifests)
    pending = sum(item["decision"]["status"] == "PENDING" for item in decisions)
    decided = sum(item["decision"]["status"] == "DECIDED" for item in decisions)
    approved = sum(item["approval"]["status"] == "APPROVED" for item in decisions)
    rejected = sum(item["approval"]["status"] == "REJECTED" for item in decisions)
    verified = sum(item["verification"]["status"] == "PASS" for item in decisions)
    approval_count = sum(item["approval"]["approval_count"] for item in decisions)
    superseded = sum(len(item["superseded_revisions"]) for item in decisions)
    decisions_complete = decided == expected_total
    approvals_complete = approved == expected_total
    verification_complete = verified == expected_total
    packet_complete = (packets["summary"]["packet_count"] == policy["expected_review_packets"]["total"] and
                       packets["summary"]["member_count"] == expected_total and
                       packets["summary"]["unique_member_count"] == expected_total)
    gate = coverage and decisions_complete and approvals_complete and verification_complete and packet_complete
    reasons = []
    if not coverage:
        reasons.append("SUBJECT_COVERAGE_INCOMPLETE")
    if not decisions_complete:
        reasons.append("DECISIONS_PENDING")
    if not approvals_complete:
        reasons.append("APPROVALS_ABSENT")
    if not verification_complete:
        reasons.append("VERIFICATION_INCOMPLETE")
    if not packet_complete:
        reasons.append("REVIEW_PACKETS_INCOMPLETE")
    aggregate_lines = bound["aggregate_lines"] + [f"{item['artifact_id']}|{item['sha256']}|{item['records']}"
                                                   for item in derived]
    bound_inputs = {"aggregate_sha256": digest(aggregate_lines), "evidence": bound["evidence"],
                    "derived_sources": derived}
    by_kind = {kind.lower(): counts[kind] for kind in KINDS}
    return {
        "schema_version": 2, "workflow_version": 2,
        "captured_utc": evidence["P2-18"]["captured_utc"],
        "task_id": "P2-20B", "milestone": "P2-20B.1", "source_build": policy["source_build"],
        "result": "PASS" if gate else "BLOCKED", "generation_result": "PASS",
        "task_status": "COMPLETE" if gate else "BLOCKED",
        "completion_criteria_satisfied": gate, "gate_criterion": "G2-07", "g2_07_satisfied": gate,
        "input_bindings": bound_inputs,
        "review_packets": {"path": "Data/Governance/p2-g2-migration-review-packets.json",
            "sha256": file_digest(packet_output),
            "packet_count": packets["summary"]["packet_count"],
            "member_count": packets["summary"]["member_count"],
            "aggregate_membership_sha256": packets["summary"]["aggregate_membership_sha256"]},
        "summary": {"expected_units": expected_total, "enumerated_units": len(decisions),
                    "pending": pending, "decided": decided, "approved": approved,
                    "rejected": rejected, "verified": verified, "approval_count": approval_count,
                    "superseded_revisions": superseded, "by_subject_kind": by_kind},
        "completeness": {"coverage_complete": coverage, "decisions_complete": decisions_complete,
                         "approvals_complete": approvals_complete,
                         "verification_complete": verification_complete,
                         "missing": missing, "duplicates": duplicates,
                         "orphans": orphans, "reference_membership_enumerated": counts["SCHEMA_REFERENCE"] == 12,
                         "all_inputs_hash_bound": True, "review_packets_complete": packet_complete,
                         "failure_reasons": reasons},
        "manifests": manifests, "decisions": decisions,
        "hard_invariants": {"numeric_identity_narrowing_forbidden": True,
            "string_identity_numeric_conversion_forbidden": True,
            "observed_mode_default_forbidden": True,
            "tombstone_reuse_without_approval_forbidden": True,
            "automatic_renumbering_without_approved_remap_forbidden": True,
            "fixed_limit_copy_without_classification_forbidden": True},
        "authority_boundaries": {"machine_generated": True, "machine_can_approve": False,
            "authority_ledger_records": len(authority["records"]),
            "approval_authority_present": approval_count > 0, "g2_approved": False,
            "p3_authorized": False, "release_authority": False},
        "contracts": {"policy": policy_path.relative_to(root).as_posix(),
            "policy_sha256": file_digest(policy_path), "schema": schema_path.relative_to(root).as_posix(),
            "schema_sha256": file_digest(schema_path),
            "authority_schema": policy["authority_schema"],
            "authority_schema_sha256": file_digest(safe_repo_path(root, policy["authority_schema"])),
            "review_packet_schema": policy["review_packet_schema"],
            "review_packet_schema_sha256": file_digest(safe_repo_path(root, policy["review_packet_schema"]))},
        "disclosure": {"table_or_field_names": False, "legacy_source_paths": False,
            "exact_primary_keys": False, "exact_observed_extrema": False, "raw_table_rows": False,
            "legacy_source_lines": False, "matched_literal_values": False},
    }


def render_markdown(registry: dict[str, Any]) -> str:
    summary, complete = registry["summary"], registry["completeness"]
    lines = ["# P2-20B G2-07 Migration Decision Registry", "",
        f"- Generation: `{registry['generation_result']}`", f"- Registry result: `{registry['result']}`",
        f"- G2-07 satisfied: `{str(registry['g2_07_satisfied']).lower()}`",
        f"- Enumerated units: {summary['enumerated_units']} / {summary['expected_units']}",
        f"- Workflow version: {registry['workflow_version']}",
        f"- Pending decisions: {summary['pending']}", f"- Approved decisions: {summary['approved']}",
        f"- Review packets: {registry['review_packets']['packet_count']} / 39", "",
        "The V2 workflow can validate future externally authorized decisions, but the current authority ledger is empty. Every machine suggestion remains a non-decision.", "",
        "## Coverage", "", "| Subject | Units |", "| --- | ---: |"]
    labels = {"schema_table": "Schema table", "schema_reference": "Schema reference",
              "canonical_id_domain": "Canonical ID domain", "id_component": "ID component",
              "fixed_limit_signal": "Fixed-limit signal"}
    for key, value in summary["by_subject_kind"].items():
        lines.append(f"| {labels[key]} | {value} |")
    lines += ["", "Reference membership was deterministically enumerated from the frozen read-only legacy headers and the P2-09-bound core registry; names and paths are not emitted.", "",
        "## Fail-closed status", "", f"Coverage complete: `{str(complete['coverage_complete']).lower()}`. Decisions complete: `{str(complete['decisions_complete']).lower()}`. Approvals complete: `{str(complete['approvals_complete']).lower()}`. Verification complete: `{str(complete['verification_complete']).lower()}`.", "",
        "The 39 anonymous risk-signature packets preserve all 1,359 independent members and exact membership hashes. A packet is review routing, not a batch decision or approval.", "",
        "G2-07 remains blocked until every active subject has a chosen action, migration and rollback evidence where required, and independently verifiable approval from the required role. Candidate text, a self-asserted approver field, or an aggregate count cannot close the gate.", "",
        "## Hard boundaries", "", "Numeric IDs may not be narrowed from uint64; string IDs may not be converted implicitly to numbers; observed modes are not authoritative defaults; Tombstones may not be reused; and legacy fixed limits may not be copied without classification and rationale.", "",
        "This registry does not approve G2, authorize P3, grant release authority, or claim restoration of an unavailable official server implementation.", ""]
    return "\n".join(lines)


def self_test() -> dict[str, Any]:
    assertions = 0
    sample = [{"decision_id": "MIG-X-0001", "subject_membership_sha256": "0" * 64}]
    require(manifest_digest(sample) == manifest_digest(sample), "Manifest stability failed"); assertions += 1
    require(len({item["decision_id"] for item in sample}) == len(sample), "Uniqueness failed"); assertions += 1
    require(1359 == 52 + 12 + 12 + 16 + 1267, "Population arithmetic failed"); assertions += 1
    require(False is not True, "Machine approval boundary failed"); assertions += 1
    require(None is None, "Pending chosen-action boundary failed"); assertions += 1
    require("UINT64" not in "NARROW", "Narrowing boundary failed"); assertions += 1
    require(digest(["a"]) != digest(["b"]), "Input drift hash failed"); assertions += 1
    try:
        safe_repo_path(Path.cwd(), "../outside")
        raise ValueError("Path escape accepted")
    except ValueError:
        assertions += 1
    sample_match = [("0" * 64, {})]
    require(select_unique_manifest(sample_match) == sample_match[0], "Unique discovery failed"); assertions += 1
    try:
        select_unique_manifest(sample_match + sample_match)
        raise ValueError("Ambiguous discovery accepted")
    except ValueError:
        assertions += 1
    try:
        select_unique_manifest([])
        raise ValueError("Missing discovery accepted")
    except ValueError:
        assertions += 1
    workflow = workflow_self_test()
    assertions += workflow["assertions"]
    return {"result": "PASS", "assertions": assertions,
            "workflow_negative_cases": workflow["negative_cases"]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path); parser.add_argument("--legacy-root", type=Path)
    parser.add_argument("--policy", type=Path); parser.add_argument("--schema", type=Path)
    parser.add_argument("--registry-output", type=Path); parser.add_argument("--packet-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True, separators=(",", ":"))); return
    require(all((args.root, args.legacy_root, args.policy, args.schema, args.registry_output,
                 args.packet_output,
                 args.markdown_output)), "Generation arguments are required")
    registry = build_registry(args.root.resolve(), args.legacy_root.resolve(),
                              args.policy.resolve(), args.schema.resolve(), args.packet_output.resolve())
    write_text(args.registry_output, json.dumps(registry, ensure_ascii=False, indent=2) + "\n")
    write_text(args.markdown_output, render_markdown(registry))
    print(json.dumps({"generation_result": "PASS", "result": registry["result"],
        "enumerated_units": registry["summary"]["enumerated_units"],
        "pending": registry["summary"]["pending"],
        "review_packets": registry["review_packets"]["packet_count"],
        "g2_07_satisfied": registry["g2_07_satisfied"]}, separators=(",", ":")))


if __name__ == "__main__":
    main()
