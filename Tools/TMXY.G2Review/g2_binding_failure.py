"""P2-20A.7 production-binding failure diagnostic binding for G2."""
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Callable


INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a4_evidence", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_policy", "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json", True),
    ("p2_03_evidence", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False),
    ("p2_12_evidence", "Data/Inventory/p2-12-full-asset-inventory.json", True),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("core_report", "Data/Reports/p2-20a-core-resource-closure-report.json", True),
    ("a5_report", "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json", True),
    ("a6_report", "Data/Reports/p2-20a-asset-identity-normalization-report.json", True),
    ("b1_evidence", "Data/Inventory/p2-20b-migration-decisions.json", True),
    ("policy", "Contracts/data-schema/g2-asset-binding-failure-diagnostics-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-asset-binding-failure-diagnostics-v1.schema.json", True),
    ("detail_schema", "Contracts/data-schema/g2-asset-binding-failure-detail-v1.schema.json", True),
]
EXPECTED_TOP = {
    "schema_version", "evidence_revision", "captured_utc", "task_id", "criterion_id",
    "source_build", "result", "review_execution_result", "task_status",
    "completion_criteria_satisfied", "diagnostic_scope_complete",
    "remediation_scope_complete", "g2_06_satisfied", "p3_authorized", "input_bindings",
    "detail_export", "scope", "measured", "classification_controls", "authority_boundary",
    "preserved_blockers", "blockers", "negative_contracts", "g2_projection", "contracts",
    "disclosure",
}
EXPECTED_AUTHORITY = {
    "machine_can_reproduce": True, "machine_can_classify_errors": True,
    "machine_can_select_candidate": False, "machine_can_approve_disposition": False,
    "technical_adapter_must_be_contract_proven": True,
    "content_change_or_no_ref_requires_owner": True,
    "owner_records": 0, "approved_fixes": 0, "verified_resolutions": 0,
}
EXPECTED_BLOCKERS = [
    {"reason_code": "PRODUCTION_BINDING_REJECTIONS_DIAGNOSED_NOT_REMEDIATED", "count": 19},
    {"reason_code": "REMEDIATION_EVIDENCE_ABSENT", "count": 19},
]


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def bind_binding_failure_diagnostics(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["binding_failure_diagnostics"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    diagnostic = load_json(path)
    require(set(diagnostic) == EXPECTED_TOP and diagnostic.get("schema_version") == 1 and
            diagnostic.get("task_id") == spec["task_id"] and
            diagnostic.get("criterion_id") == spec["criterion_id"] and
            diagnostic.get("evidence_revision") == spec["evidence_revision"] and
            diagnostic.get("source_build") == policy["source_build"] and
            isinstance(diagnostic.get("captured_utc"), str),
            "P2-20A.7 binding-failure diagnostic identity or shape mismatch")
    require(diagnostic.get("result") == "BLOCKED" and
            diagnostic.get("review_execution_result") == "PASS" and
            diagnostic.get("task_status") == "BLOCKED" and
            diagnostic.get("completion_criteria_satisfied") is False and
            diagnostic.get("diagnostic_scope_complete") is True and
            diagnostic.get("remediation_scope_complete") is False and
            diagnostic.get("g2_06_satisfied") is False and
            diagnostic.get("p3_authorized") is False,
            "P2-20A.7 diagnostic state was falsely promoted")

    a7_policy_path = resolve_inside(root, INPUTS[12][1])
    a7_schema_path = resolve_inside(root, INPUTS[13][1])
    detail_schema_path = resolve_inside(root, INPUTS[14][1])
    a7_policy = load_json(a7_policy_path)
    require(a7_policy.get("task_id") == spec["task_id"] and
            a7_policy.get("criterion_id") == spec["criterion_id"] and
            a7_policy.get("evidence_revision") == spec["evidence_revision"] and
            a7_policy.get("source_build") == policy["source_build"],
            "P2-20A.7 policy identity mismatch")

    entries: list[dict[str, Any]] = []
    for role, item_relative, tracked in INPUTS:
        item_path = resolve_inside(root, item_relative)
        entries.append({"role": role, "path": item_relative, "tracked": tracked,
                        "bytes": item_path.stat().st_size, "lines": _line_count(item_path),
                        "sha256": sha256(item_path)})
    aggregate_text = "".join(
        f"{item['role']}\t{item['path']}\t{item['tracked']}\t{item['bytes']}\t"
        f"{item['lines']}\t{item['sha256']}\n" for item in entries)
    require(diagnostic.get("input_bindings") == {
                "aggregate_sha256": hashlib.sha256(aggregate_text.encode("utf-8")).hexdigest(),
                "entries": entries}, "P2-20A.7 input bindings drifted")

    a4_report = load_json(resolve_inside(root, INPUTS[0][1]))
    a4_detail = resolve_inside(root, INPUTS[1][1])
    a4_advertised = a4_report["detail_export"]
    require(a4_report.get("evidence_revision") == "P2-20A.4" and
            a4_report.get("diagnostic_scope_complete") is True and
            a4_report["measured"]["unresolved_targets"] == 19 and
            a4_report["measured"]["by_resolution_basis_edges"]
            ["NO_PRODUCTION_COMPATIBLE_CANDIDATE"] == 24 and
            a4_advertised.get("path") == INPUTS[1][1] and
            a4_advertised.get("bytes") == a4_detail.stat().st_size and
            a4_advertised.get("lines") == _line_count(a4_detail) and
            a4_advertised.get("sha256") == sha256(a4_detail),
            "P2-20A.7 did not preserve its exact A.4 report/detail binding")
    detail = diagnostic["detail_export"]
    detail_path = resolve_inside(root, detail["path"])
    require(detail.get("path") ==
            "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl" and
            detail.get("tracked") is False and detail.get("lines") == 19 and
            detail.get("bytes") == detail_path.stat().st_size and
            detail.get("sha256") == sha256(detail_path),
            "P2-20A.7 anonymous detail export is not hash-bound")

    measured = diagnostic["measured"]
    expected_measured = {
        "diagnosed_targets": 19, "diagnosed_candidate_edges": 24,
        "typed_error_edges": 24, "unclassified_error_edges": 0,
        "candidate_selections": 0, "automatic_resolutions": 0, "owner_dispositions": 0,
        "by_family": a7_policy["scope"]["by_family"],
        "by_error": a7_policy["expected_error_counts"],
        "effective": {"resolved_targets": 0, "resolved_edges": 0,
                      "unresolved_targets": 19, "unresolved_edges": 24},
    }
    require(diagnostic.get("scope") == a7_policy.get("scope") and
            measured == expected_measured and
            diagnostic.get("classification_controls") == a7_policy.get("controls") and
            diagnostic.get("authority_boundary") == EXPECTED_AUTHORITY and
            diagnostic.get("preserved_blockers") == a7_policy.get("preserved_blockers") and
            diagnostic.get("blockers") == EXPECTED_BLOCKERS and
            diagnostic.get("negative_contracts") == a7_policy.get("negative_contracts") and
            diagnostic.get("g2_projection") == {"criteria_total": 9, "satisfied": 7,
                                                 "blocked": 2, "g2_decision": "BLOCKED"},
            "P2-20A.7 measured failure taxonomy or fail-closed controls drifted")
    require(diagnostic.get("contracts") == {
                "policy_sha256": sha256(a7_policy_path),
                "schema_sha256": sha256(a7_schema_path),
                "detail_schema_sha256": sha256(detail_schema_path)} and
            diagnostic.get("disclosure") == a7_policy.get("disclosure"),
            "P2-20A.7 contracts or disclosure boundary drifted")

    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"], "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"], "path": relative, "sha256": digest,
        "result": diagnostic["result"],
        "review_execution_result": diagnostic["review_execution_result"],
        "task_status": diagnostic["task_status"],
        "completion_criteria_satisfied": diagnostic["completion_criteria_satisfied"],
        "diagnostic_scope_complete": diagnostic["diagnostic_scope_complete"],
        "remediation_scope_complete": diagnostic["remediation_scope_complete"],
        "g2_06_satisfied": diagnostic["g2_06_satisfied"],
    }
    aggregate = (f"BINDING_FAILURE_DIAGNOSTICS|{spec['task_id']}|{spec['criterion_id']}|"
                 f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, diagnostic, aggregate
