#!/usr/bin/env python3
"""Assemble the closed P2-20A.3 auxiliary-config evidence documents."""

from __future__ import annotations

from pathlib import Path
from typing import Any

def sha256_file(path: Path) -> str:
    digest = __import__("hashlib").sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_report(
    policy: dict[str, Any],
    policy_path: Path,
    schema_path: Path,
    bindings: dict[str, Any],
    extraction: dict[str, Any],
    captured_utc: str,
) -> dict[str, Any]:
    measured = dict(extraction["measured"])
    files = list(extraction["file_instances"])
    candidate_only = sum(item["adapter_state"] == "candidate-only" for item in files)
    malformed = sum(item["adapter_state"] == "malformed-blocked" for item in files)
    undecided = sum(item["adapter_state"] == "editor-undecided" for item in files)
    if candidate_only + malformed + undecided != len(files):
        raise ValueError("current P2-20A.3 file states are not fail closed")

    return {
        "schema_version": 1,
        "evidence_revision": "P2-20A.3",
        "captured_utc": captured_utc,
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "source_build": policy["source_build"],
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "scope_complete": False,
        "g2_06_satisfied": False,
        "p3_authorized": False,
        "input_bindings": bindings,
        "measured_lexical_candidates": measured,
        "parser_and_matching_controls": {
            "every_file_instance_enumerated": True,
            "duplicate_file_instances_preserved": True,
            "duplicate_ecf_assignments_preserve_order": True,
            "xml_dtd_enabled": False,
            "xml_external_resolver_enabled": False,
            "exact_complete_scalar_matching": True,
            "substring_matching": False,
            "basename_matching": False,
            "extension_only_matching": False,
            "first_candidate_selection": False,
            "ambiguous_candidates_all_retained": True,
            "config_closure_detection": True,
            "config_cycle_detection": True,
            "malformed_implies_zero_references": False,
        },
        "adapter_state_summary": {
            "file_instances": len(files),
            "terminal_file_instances": 0,
            "nonterminal_file_instances": len(files),
            "semantic_approved": 0,
            "no_ref_approved": 0,
            "candidate_only": candidate_only,
            "malformed_blocked": malformed,
            "editor_undecided": undecided,
            "approved_roots": 0,
        },
        "file_instances": files,
        "semantic_resolution": {
            "status": "UNASSESSED",
            "unknown_occurrences": None,
            "ambiguous_occurrences": None,
            "unresolved_occurrences": None,
            "resolved_occurrences": None,
            "first_candidate_selections": 0,
            "heuristic_target_selections": 0,
            "all_ambiguous_candidates_retained": True,
            "reason_code": "SEMANTIC_ADAPTERS_NOT_APPROVED",
        },
        "config_closure": {
            "lexical_edges": measured["config_exact_edges"],
            "approved_root_count": 0,
            "approved_root_set_sha256": None,
            "semantic_edge_set_sha256": None,
            "closure_set_sha256": None,
            "closure_complete": False,
            "cycle_detection_complete": False,
            "cycle_count": None,
            "unresolved_cycle_count": None,
            "reason_code": "APPROVED_ROOTS_AND_SEMANTIC_EDGES_UNAVAILABLE",
        },
        "assumptions": list(policy["assumptions"]),
        "blockers": [
            {"reason_code": "SEMANTIC_ADAPTERS_UNAPPROVED", "count": len(files), "blocking": True},
            {"reason_code": "APPROVED_ROOT_SET_EMPTY", "count": 0, "blocking": True},
            {"reason_code": "MALFORMED_INPUTS_UNDISPOSED", "count": malformed, "blocking": True},
            {"reason_code": "SEMANTIC_METRICS_UNAVAILABLE", "count": 3, "blocking": True},
            {"reason_code": "CONFIG_CLOSURE_UNAPPROVED", "count": measured["config_exact_edges"], "blocking": True},
            {"reason_code": "AUXILIARY_SCOPE_INCOMPLETE", "count": 1, "blocking": True},
        ],
        "completion": {
            "file_coverage_complete": len(files) == 212,
            "duplicate_file_instances_preserved": True,
            "duplicate_ecf_assignment_order_preserved": True,
            "semantic_adapters_terminal": False,
            "malformed_disposition_complete": False,
            "semantic_resolution_complete": False,
            "config_closure_complete": False,
            "cycle_detection_complete": False,
            "all_inputs_hash_bound": True,
            "first_candidate_selection_absent": True,
            "scope_complete": False,
            "satisfied": False,
        },
        "authority_boundaries": {
            "machine_candidate_is_approval": False,
            "approved_semantic_adapters": 0,
            "approved_no_ref_files": 0,
            "approved_roots": 0,
            "g2_06_satisfied": False,
            "g2_approved": False,
            "p3_authorized": False,
            "release_authority": False,
        },
        "contracts": {
            "policy_sha256": sha256_file(policy_path),
            "schema_sha256": sha256_file(schema_path),
        },
        "disclosure": dict(policy["disclosure_rules"]),
    }


def render_markdown(report: dict[str, Any]) -> str:
    measured = report["measured_lexical_candidates"]
    states = report["adapter_state_summary"]
    lines = [
        "# P2-20A.3 Auxiliary-Config Reference Evidence",
        "",
        "- Review execution: `PASS`",
        "- Closure result: `BLOCKED`",
        "- G2-06 satisfied: `false`",
        "- P3 authorized: `false`",
        "",
        "## Measured lexical facts",
        "",
        f"- File instances: {measured['file_instances']} ({measured['unique_content_bodies']} unique bodies)",
        f"- Parsed / malformed: {measured['parsed_file_instances']} / {measured['malformed_file_instances']}",
        f"- Scalar positions / non-empty: {measured['scalar_positions']} / {measured['nonempty_scalar_positions']}",
        f"- Exact asset occurrences: {measured['asset_exact_occurrences']}",
        f"- Exact Package occurrences: {measured['package_exact_occurrences']} ({measured['package_unique_occurrences']} unique, {measured['package_ambiguous_occurrences']} ambiguous)",
        f"- Retained ambiguous Package candidate edges: {measured['package_ambiguous_candidate_edges']}",
        f"- Exact config-to-config lexical edges: {measured['config_exact_edges']}",
        "",
        "These are complete-scalar lexical observations only. They do not approve a semantic adapter or a traversal root.",
        "",
        "## Adapter state",
        "",
        f"- Candidate-only: {states['candidate_only']}",
        f"- Malformed-blocked: {states['malformed_blocked']}",
        f"- No-reference undecided: {states['editor_undecided']}",
        "- Semantic-approved / no-ref-approved: 0 / 0",
        "- Approved roots: 0",
        "",
        "Every file instance is retained, including duplicate bodies. ECF repeated assignments preserve source order; no first/last winner is selected. XML DTDs and external resolution are disabled. Substring, basename, extension-only and first-candidate matching are prohibited.",
        "",
        "## Blocking boundary",
        "",
        "All 212 instances still need an authority-backed terminal disposition. The six malformed XML instances need explicit safe handling. Semantic resolution and configuration closure cannot be calculated from lexical candidates until adapters and roots are approved.",
        "",
        "This evidence does not establish a complete playable version, approve G2, authorize P3, or grant release authority.",
        "",
        "## Reproduction",
        "",
        "Run `Tools/TMXY.G2AuxConfigClosure/New-G2AuxiliaryConfigClosure.ps1`; add `-Check` to compare deterministic outputs. Deep contract verification additionally reads the ignored anonymous candidate export.",
        "",
    ]
    return "\n".join(lines)


def build_governance(report: dict[str, Any], report_sha256: str,
                     detail_count: int, detail_sha256: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "evidence_revision": "P2-20A.3",
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "completion_criteria_satisfied": False,
        "scope_complete": False,
        "report": {
            "path": "Data/Reports/p2-20a-aux-config-reference-report.json",
            "sha256": report_sha256,
        },
        "anonymous_candidate_export": {
            "tracked": False,
            "count": detail_count,
            "sha256": detail_sha256,
        },
        "authority": {
            "approved_semantic_adapters": 0,
            "approved_no_ref_files": 0,
            "approved_roots": 0,
            "g2_06_satisfied": False,
            "g2_approved": False,
            "p3_authorized": False,
            "release_authority": False,
        },
    }
