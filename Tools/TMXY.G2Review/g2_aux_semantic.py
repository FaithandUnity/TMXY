"""P2-20A.5 auxiliary semantic diagnostic binding for the G2 review."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Callable


INPUT_PATHS = {
    "auxiliary_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "three_layer_inventory": "Data/Inventory/p2-06-three-layer-data.json",
    "lexical_report": "Data/Reports/p2-20a-aux-config-reference-report.json",
    "package_inventory": "Data/Inventory/p2-01-package-inventory.json",
    "asset_inventory": "Data/Inventory/p2-12-full-asset-inventory.json",
    "reference_closure": "Data/Inventory/p2-13-reference-closure.json",
    "policy": "Contracts/data-schema/g2-aux-semantic-diagnostics-policy-v1.json",
    "schema": "Contracts/data-schema/g2-aux-semantic-diagnostics-v1.schema.json",
}
CONTROLS = {
    "strict_region_xml": True, "consumer_selected_fields_only": True,
    "legacy_ecf_crlf_parser_compared": True,
    "mixed_newline_difference_is_blocking": True,
    "first_candidate_selection": False, "zero_match_is_no_reference": False,
    "shadow_without_roots_is_no_reference": False, "malformed_auto_fix": False,
    "unknown_field_is_ignored": False,
}
SEMANTIC_STATE = {
    "approved_consumer_contracts": 0, "approved_no_reference_instances": 0,
    "approved_roots": 0, "terminal_instances": 0, "nonterminal_instances": 212,
    "ordinary_development_authorization_is_semantic_approval": False,
}
BLOCKERS = [
    {"reason_code": "AMBIGUOUS_OBJECT_TARGETS", "count": 211},
    {"reason_code": "UNRESOLVED_RESOURCE_TARGETS", "count": 1},
    {"reason_code": "LEGACY_PARSER_PARITY_GAPS", "count": 3},
    {"reason_code": "MALFORMED_INPUTS_UNDISPOSED", "count": 6},
    {"reason_code": "APPROVED_ROOT_SET_EMPTY", "count": 0},
    {"reason_code": "CONSUMER_CONTRACTS_UNAPPROVED", "count": 212},
]


def bind_aux_semantic_diagnostics(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["aux_semantic_diagnostics"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    diagnostic = load_json(path)
    expected_top = {
        "schema_version", "evidence_revision", "captured_utc", "task_id",
        "criterion_id", "source_build", "result", "review_execution_result",
        "task_status", "completion_criteria_satisfied", "diagnostic_scope_complete",
        "scope_complete", "g2_06_satisfied", "p3_authorized", "input_bindings",
        "measured", "parser_and_consumer_controls", "semantic_state", "blockers",
        "negative_contracts", "g2_projection", "contracts", "disclosure",
    }
    require(set(diagnostic) == expected_top and diagnostic.get("schema_version") == 1 and
            diagnostic.get("task_id") == spec["task_id"] and
            diagnostic.get("criterion_id") == spec["criterion_id"] and
            diagnostic.get("evidence_revision") == spec["evidence_revision"] and
            diagnostic.get("source_build") == policy["source_build"] and
            isinstance(diagnostic.get("captured_utc"), str),
            "P2-20A.5 auxiliary semantic diagnostic identity or shape mismatch")
    require(diagnostic.get("result") == "BLOCKED" and
            diagnostic.get("review_execution_result") == "PASS" and
            diagnostic.get("task_status") == "BLOCKED" and
            diagnostic.get("completion_criteria_satisfied") is False and
            diagnostic.get("diagnostic_scope_complete") is True and
            diagnostic.get("scope_complete") is False and
            diagnostic.get("g2_06_satisfied") is False and
            diagnostic.get("p3_authorized") is False,
            "P2-20A.5 auxiliary semantic diagnostic state is inconsistent")

    policy_path = resolve_inside(root, INPUT_PATHS["policy"])
    schema_path = resolve_inside(root, INPUT_PATHS["schema"])
    diagnostic_policy = load_json(policy_path)
    require(diagnostic_policy.get("evidence_revision") == spec["evidence_revision"] and
            diagnostic_policy.get("task_id") == spec["task_id"] and
            diagnostic_policy.get("criterion_id") == spec["criterion_id"] and
            diagnostic_policy.get("source_build") == policy["source_build"],
            "P2-20A.5 diagnostic policy identity mismatch")
    entries: list[dict[str, str]] = []
    aggregate = hashlib.sha256()
    for role, input_relative in INPUT_PATHS.items():
        digest = sha256(resolve_inside(root, input_relative))
        entries.append({"role": role, "sha256": digest})
        aggregate.update(f"{role}\t{digest}\n".encode("ascii"))
    legacy = [{"role": role, "sha256": diagnostic_policy["legacy_source_bindings"][role]}
              for role in sorted(diagnostic_policy["legacy_source_bindings"])]
    require(diagnostic.get("input_bindings") == {
                "aggregate_sha256": aggregate.hexdigest(),
                "entries": entries, "legacy_sources": legacy,
            }, "P2-20A.5 input or legacy-source bindings drifted")
    require(diagnostic.get("measured") == diagnostic_policy.get("expected_measured") and
            diagnostic["measured"].get("source_instances_verified") == 212,
            "P2-20A.5 auxiliary semantic measurements drifted")
    require(diagnostic.get("parser_and_consumer_controls") == CONTROLS and
            diagnostic.get("semantic_state") == SEMANTIC_STATE and
            diagnostic.get("blockers") == BLOCKERS and
            diagnostic.get("negative_contracts") == diagnostic_policy.get("negative_contracts") and
            diagnostic.get("g2_projection") == {
                "criteria_total": 9, "satisfied": 7, "blocked": 2,
                "g2_decision": "BLOCKED",
            }, "P2-20A.5 fail-closed semantic state or blockers drifted")
    require(diagnostic.get("disclosure") == diagnostic_policy.get("disclosure"),
            "P2-20A.5 auxiliary semantic disclosure boundary failed")
    require(diagnostic.get("contracts") == {
                "policy_sha256": sha256(policy_path), "schema_sha256": sha256(schema_path),
            }, "P2-20A.5 auxiliary semantic contracts are not hash-bound")

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
    aggregate_line = (f"AUX_SEMANTIC|{spec['task_id']}|{spec['criterion_id']}|"
                      f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, diagnostic, aggregate_line
