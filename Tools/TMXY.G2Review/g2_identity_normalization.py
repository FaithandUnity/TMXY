"""P2-20A.6 identity-normalization safety binding for the G2 review."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Callable


INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a4_policy", "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json", True),
    ("p2_03_evidence", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False),
    ("policy", "Contracts/data-schema/g2-asset-identity-normalization-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-asset-identity-normalization-v1.schema.json", True),
]
EXPECTED_TOP = {
    "schema_version", "evidence_revision", "captured_utc", "task_id", "criterion_id",
    "source_build", "result", "review_execution_result", "task_status",
    "completion_criteria_satisfied", "diagnostic_scope_complete", "scope_complete",
    "g2_06_satisfied", "p3_authorized", "input_bindings", "detail_export", "scope",
    "measured", "normalization_controls", "blockers", "negative_contracts",
    "g2_projection", "contracts", "disclosure",
}
EXPECTED_SCOPE = {
    "source_revision": "P2-20A.4", "source_resolution": "AMBIGUOUS",
    "source_ambiguous_targets": 15, "source_candidate_edges": 30,
    "candidate_count_per_target": 2, "candidate_identity_exact": True,
    "production_descriptor_semantics_used": True, "candidate_selected": False,
    "first_candidate_selection_used": False,
    "representative_candidate_selection_used": False,
}
EXPECTED_CONTROLS = {
    "ascii_lower_identity_grouping_only": True, "unicode_casefold": False,
    "locale_sensitive_mapping": False, "path_normalization": False,
    "descriptor_field_normalization": False,
    "identity_grouping_is_semantic_equivalence": False,
    "strict_descriptor_semantics_required": True, "strict_full_semantics_required": True,
    "nested_references_preserved": True, "unknown_properties_preserved": True,
    "floating_point_bits_preserved": True, "field_order_preserved": True,
    "first_candidate_selection": False, "representative_candidate_selection": False,
    "coarse_equivalence_substitution": False,
}
EXPECTED_BLOCKERS = [
    {"reason_code": "CASE_FOLD_COLLISION_NOT_SEMANTIC_EQUIVALENCE", "count": 13},
    {"reason_code": "NON_CASE_IDENTITY_MULTIPLICITY", "count": 2},
    {"reason_code": "STRICT_SEMANTIC_EQUIVALENCE_ABSENT", "count": 15},
]


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def bind_identity_normalization_safety(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["identity_normalization_safety"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    diagnostic = load_json(path)
    require(set(diagnostic) == EXPECTED_TOP and diagnostic.get("schema_version") == 1 and
            diagnostic.get("task_id") == spec["task_id"] and
            diagnostic.get("criterion_id") == spec["criterion_id"] and
            diagnostic.get("evidence_revision") == spec["evidence_revision"] and
            diagnostic.get("source_build") == policy["source_build"] and
            isinstance(diagnostic.get("captured_utc"), str),
            "P2-20A.6 identity-normalization diagnostic identity or shape mismatch")
    require(diagnostic.get("result") == "BLOCKED" and
            diagnostic.get("review_execution_result") == "PASS" and
            diagnostic.get("task_status") == "BLOCKED" and
            diagnostic.get("completion_criteria_satisfied") is False and
            diagnostic.get("diagnostic_scope_complete") is True and
            diagnostic.get("scope_complete") is False and
            diagnostic.get("g2_06_satisfied") is False and
            diagnostic.get("p3_authorized") is False,
            "P2-20A.6 identity-normalization state was falsely promoted")

    a6_policy_path = resolve_inside(root, INPUTS[5][1])
    a6_schema_path = resolve_inside(root, INPUTS[6][1])
    a6_policy = load_json(a6_policy_path)
    require(a6_policy.get("task_id") == spec["task_id"] and
            a6_policy.get("criterion_id") == spec["criterion_id"] and
            a6_policy.get("evidence_revision") == spec["evidence_revision"] and
            a6_policy.get("source_build") == policy["source_build"],
            "P2-20A.6 policy identity mismatch")

    entries: list[dict[str, Any]] = []
    for role, item_relative, tracked in INPUTS:
        item_path = resolve_inside(root, item_relative)
        entries.append({
            "role": role, "path": item_relative, "tracked": tracked,
            "bytes": item_path.stat().st_size, "lines": _line_count(item_path),
            "sha256": sha256(item_path),
        })
    aggregate_text = "".join(
        f"{item['role']}\t{item['path']}\t{item['tracked']}\t{item['bytes']}\t"
        f"{item['lines']}\t{item['sha256']}\n" for item in entries)
    require(diagnostic.get("input_bindings") == {
                "aggregate_sha256": hashlib.sha256(aggregate_text.encode("utf-8")).hexdigest(),
                "entries": entries,
            }, "P2-20A.6 input bindings drifted")

    a4_report = load_json(resolve_inside(root, INPUTS[0][1]))
    a4_detail = resolve_inside(root, INPUTS[1][1])
    a4_advertised = a4_report["detail_export"]
    require(a4_report.get("evidence_revision") == "P2-20A.4" and
            a4_report.get("diagnostic_scope_complete") is True and
            a4_report["measured"]["by_resolution_basis_targets"]
            ["MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"] == 15 and
            a4_report["measured"]["by_resolution_basis_edges"]
            ["MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"] == 30 and
            a4_advertised.get("path") == INPUTS[1][1] and
            a4_advertised.get("tracked") is False and
            a4_advertised.get("bytes") == a4_detail.stat().st_size and
            a4_advertised.get("lines") == _line_count(a4_detail) and
            a4_advertised.get("sha256") == sha256(a4_detail),
            "P2-20A.6 did not preserve its exact A.4 report/detail binding")

    detail = diagnostic["detail_export"]
    detail_path = resolve_inside(root, detail["path"])
    require(detail.get("path") ==
            "Data/Exports/P2-20/p2-20a-asset-identity-normalization.jsonl" and
            detail.get("tracked") is False and detail.get("lines") == 15 and
            detail.get("bytes") == detail_path.stat().st_size and
            detail.get("sha256") == sha256(detail_path),
            "P2-20A.6 anonymous detail export is not hash-bound")
    require(diagnostic.get("scope") == EXPECTED_SCOPE and
            diagnostic.get("measured") == a6_policy.get("expected_measured") and
            diagnostic.get("normalization_controls") == EXPECTED_CONTROLS and
            diagnostic.get("blockers") == EXPECTED_BLOCKERS and
            diagnostic.get("negative_contracts") == a6_policy.get("negative_contracts") and
            diagnostic.get("g2_projection") == {
                "criteria_total": 9, "satisfied": 7, "blocked": 2,
                "g2_decision": "BLOCKED",
            }, "P2-20A.6 measured safety facts or fail-closed controls drifted")
    measured = diagnostic["measured"]
    require(measured["strict_descriptor_equivalent_targets"] == 0 and
            measured["strict_full_semantic_equivalent_targets"] == 0 and
            measured["candidate_selections"] == 0 and
            measured["effective"] == {
                "resolved_targets": 0, "resolved_edges": 0,
                "ambiguous_targets": 15, "ambiguous_edges": 30,
            } and measured["reconciled_full_workset"]["ambiguous_targets"] == 189 and
            measured["reconciled_full_workset"]["ambiguous_edges"] == 546 and
            measured["reconciled_full_workset"]["unresolved_targets"] == 6 and
            measured["reconciled_full_workset"]["unresolved_edges"] == 9,
            "P2-20A.6 falsely reduced the A.4 blocking population")
    require(diagnostic.get("contracts") == {
                "policy_sha256": sha256(a6_policy_path),
                "schema_sha256": sha256(a6_schema_path),
            } and diagnostic.get("disclosure") == a6_policy.get("disclosure"),
            "P2-20A.6 contracts or disclosure boundary drifted")

    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"], "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"], "path": relative,
        "sha256": digest, "result": diagnostic["result"],
        "review_execution_result": diagnostic["review_execution_result"],
        "task_status": diagnostic["task_status"],
        "completion_criteria_satisfied": diagnostic["completion_criteria_satisfied"],
        "diagnostic_scope_complete": diagnostic["diagnostic_scope_complete"],
        "scope_complete": diagnostic["scope_complete"],
        "g2_06_satisfied": diagnostic["g2_06_satisfied"],
    }
    aggregate = (f"IDENTITY_NORMALIZATION|{spec['task_id']}|{spec['criterion_id']}|"
                 f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, diagnostic, aggregate
