"""P2-20A.9 auxiliary package-context binding for the G2 review."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any, Callable


POLICY_PATH = "Contracts/data-schema/g2-aux-package-context-policy-v1.json"
SCHEMA_PATH = "Contracts/data-schema/g2-aux-package-context-v1.schema.json"
DETAIL_SCHEMA_PATH = "Contracts/data-schema/g2-aux-package-context-detail-v1.schema.json"
DETAIL_EXPORT_PATH = "Data/Exports/P2-20/p2-20a-aux-package-context.jsonl"

INPUT_PATHS = {
    "auxiliary_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "a3_report": "Data/Reports/p2-20a-aux-config-reference-report.json",
    "a3_evidence": "Data/Inventory/p2-20a-aux-config-reference-evidence.json",
    "a5_report": "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json",
    "a5_evidence": "Data/Inventory/p2-20a-aux-semantic-diagnostics.json",
    "package_inventory": "Data/Inventory/p2-01-package-inventory.json",
    "asset_inventory": "Data/Inventory/p2-12-full-asset-inventory.json",
    "reference_closure": "Data/Inventory/p2-13-reference-closure.json",
    "policy": POLICY_PATH,
    "schema": SCHEMA_PATH,
    "detail_schema": DETAIL_SCHEMA_PATH,
}

IGNORED_ARTIFACT_SOURCES = (
    ("a3_detail", "a3_evidence", ("outputs", "anonymous_candidate_export")),
    ("asset_catalog", "asset_inventory", ("catalog",)),
    ("reference_graph", "reference_closure", ("graph",)),
)

STRICT_BASELINE = {
    "region_instances": 135,
    "unique_total": 3180,
    "unique_file": 3042,
    "unique_object": 4,
    "unique_package_root": 134,
    "ambiguous_object": 211,
    "ambiguous_candidate_edges": 422,
    "divergent_ambiguous_bodies": 211,
    "unresolved_resource": 1,
    "first_candidate_selections": 0,
}

MEASURED = {
    "source_instances_verified": 212,
    "region_instance_partition": {
        "strict_clean": 5,
        "strict_ambiguous_only": 129,
        "strict_ambiguous_and_unresolved": 1,
    },
    "package_context": {
        "preexisting_unique_verified": 4,
        "ambiguous_attempted": 211,
        "original_candidate_edges": 422,
        "singleton_matches": 211,
        "zero_matches": 0,
        "multiple_matches": 0,
        "selected_edges": 211,
        "incompatible_context_edges": 211,
        "order_invariant": 211,
        "first_candidate_selections": 0,
    },
    "effective_resolution": {
        "total_occurrences": 3392,
        "resolved_total": 3391,
        "resolved_file": 3042,
        "resolved_object": 215,
        "resolved_package_root": 134,
        "ambiguous_object": 0,
        "ambiguous_candidate_edges": 0,
        "unresolved_resource": 1,
    },
    "effective_region_instances": {"resolved_only": 134, "unresolved_resource": 1},
}

CONSUMER_CONTROLS = {
    "selection_basis": "PRODUCTION_PACKAGE_CONTEXT_PREFIX",
    "strict_region_consumer_fields_only": True,
    "frozen_strict_candidate_sets": True,
    "package_prefix_from_observed_consumer_context": True,
    "package_prefix_exact_complete_component": True,
    "global_package_basename_unique_required": True,
    "full_object_name_exact_match_required": True,
    "ascii_case_fold_only": True,
    "candidate_order_invariant": True,
    "selected_candidate_must_be_frozen_member": True,
    "all_incompatible_candidates_retained": True,
    "first_candidate_selection": False,
    "heuristic_path_selection": False,
    "content_body_equivalence_selection": False,
    "root_inference": False,
    "shadow_instance_collapse": False,
    "zero_reference_is_no_ref_approval": False,
    "technical_proof_is_authority_approval": False,
}

TECHNICAL_STATE = {
    "package_context_contract_proven": True,
    "ambiguous_object_targets_remaining": 0,
    "unresolved_resources_remaining": 1,
    "consumer_clean_region_instances": 134,
    "semantic_adapter_approved": False,
}

AUTHORITY_STATE = {
    "approved_consumer_contracts": 0,
    "approved_semantic_adapters": 0,
    "approved_no_reference_instances": 0,
    "approved_roots": 0,
    "terminal_instances": 0,
    "nonterminal_instances": 212,
    "ordinary_development_authorization_is_semantic_approval": False,
    "technical_resolution_is_semantic_approval": False,
}

PRESERVED_BLOCKERS = {
    "ecf_parser_parity_gaps": 3,
    "ecf_assignments_missed": 4,
    "malformed_instances": 6,
    "approved_roots": 0,
    "nonterminal_instances": 212,
    "config_edges_unapproved": 8,
}

BLOCKERS = [
    {"reason_code": "UNRESOLVED_RESOURCE_TARGETS", "count": 1},
    {"reason_code": "LEGACY_PARSER_PARITY_GAPS", "count": 3},
    {"reason_code": "MALFORMED_INPUTS_UNDISPOSED", "count": 6},
    {"reason_code": "APPROVED_ROOT_SET_EMPTY", "count": 0},
    {"reason_code": "CONSUMER_CONTRACTS_UNAPPROVED", "count": 212},
]

REQUIRED_IGNORED_ARTIFACT_ROLES = ["a3_detail", "asset_catalog", "reference_graph"]
AUTHORITY_RULES = {
    "package_context_proof_is_root_approval": False,
    "resolved_reference_is_terminal_instance_approval": False,
    "shadow_equivalence_is_exclusion_authority": False,
    "diagnostic_can_approve_no_ref": False,
    "this_evidence_can_approve_g2_or_p3": False,
}

G2_PROJECTION = {
    "criteria_total": 9,
    "satisfied": 7,
    "blocked": 2,
    "g2_decision": "BLOCKED",
}

SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")

TOP_LEVEL_FIELDS = {
    "schema_version", "evidence_revision", "captured_utc", "task_id",
    "criterion_id", "source_build", "result", "review_execution_result",
    "task_status", "completion_criteria_satisfied", "diagnostic_scope_complete",
    "scope_complete", "g2_06_satisfied", "p3_authorized", "input_bindings",
    "strict_baseline", "measured", "consumer_controls", "technical_state",
    "authority_state", "preserved_blockers", "blockers", "negative_contracts",
    "detail_export", "g2_projection", "contracts", "disclosure",
}


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def _nested(document: dict[str, Any], keys: tuple[str, ...]) -> Any:
    current: Any = document
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def _artifact_binding(
    root: Path,
    role: str,
    candidate: Any,
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> dict[str, Any]:
    require(isinstance(candidate, dict) and candidate.get("tracked") is False,
            f"P2-20A.9 {role} ignored-artifact binding is incomplete")
    relative = candidate.get("path")
    require(isinstance(relative, str),
            f"P2-20A.9 {role} ignored-artifact path is absent")
    path = resolve_inside(root, relative)
    expected = {
        "role": role,
        "path": relative,
        "bytes": path.stat().st_size,
        "lines": _line_count(path),
        "sha256": sha256(path),
        "tracked": False,
    }
    require(candidate.get("bytes") == expected["bytes"] and
            candidate.get("lines") == expected["lines"] and
            candidate.get("sha256") == expected["sha256"],
            f"P2-20A.9 {role} ignored artifact drifted")
    return expected


def bind_aux_package_context(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    """Bind and independently re-check the fail-closed A.9 report."""

    spec = policy["aux_package_context"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    report = load_json(path)
    require(set(report) == TOP_LEVEL_FIELDS and report.get("schema_version") == 1 and
            report.get("task_id") == spec["task_id"] and
            report.get("criterion_id") == spec["criterion_id"] and
            report.get("evidence_revision") == spec["evidence_revision"] and
            report.get("source_build") == policy["source_build"] and
            isinstance(report.get("captured_utc"), str),
            "P2-20A.9 auxiliary package-context identity or shape mismatch")
    require(report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            report.get("diagnostic_scope_complete") is True and
            report.get("scope_complete") is False and
            report.get("g2_06_satisfied") is False and
            report.get("p3_authorized") is False,
            "P2-20A.9 auxiliary package-context state is inconsistent")

    documents: dict[str, dict[str, Any]] = {}
    entries: list[dict[str, str]] = []
    aggregate = hashlib.sha256()
    for role, input_relative in INPUT_PATHS.items():
        input_path = resolve_inside(root, input_relative)
        digest = sha256(input_path)
        entries.append({"role": role, "sha256": digest})
        aggregate.update(f"{role}\t{digest}\n".encode("ascii"))
        documents[role] = load_json(input_path)

    package_policy = documents["policy"]
    require(package_policy.get("schema_version") == 1 and
            package_policy.get("task_id") == spec["task_id"] and
            package_policy.get("criterion_id") == spec["criterion_id"] and
            package_policy.get("evidence_revision") == spec["evidence_revision"] and
            package_policy.get("source_build") == policy["source_build"],
            "P2-20A.9 package-context policy identity mismatch")
    auxiliary_inventory = documents["auxiliary_inventory"]
    a3_report = documents["a3_report"]
    a3_evidence = documents["a3_evidence"]
    a5_report = documents["a5_report"]
    a5_evidence = documents["a5_evidence"]
    require(auxiliary_inventory.get("completion_criteria_satisfied") is True and
            len(auxiliary_inventory.get("files", [])) == 212,
            "P2-20A.9 auxiliary population is incomplete")
    require(a3_report.get("evidence_revision") == "P2-20A.3" and
            a3_report.get("result") == "BLOCKED" and
            a3_report.get("adapter_state_summary", {}).get("nonterminal_file_instances") == 212 and
            a3_report.get("adapter_state_summary", {}).get("malformed_blocked") == 6,
            "P2-20A.9 A.3 strict auxiliary state drifted")
    require(a3_evidence.get("outputs", {}).get("report_json", {}).get("sha256") == sha256(
                resolve_inside(root, INPUT_PATHS["a3_report"])),
            "P2-20A.9 A.3 report/evidence cross-binding drifted")
    require(a5_report.get("evidence_revision") == "P2-20A.5" and
            a5_report.get("result") == "BLOCKED" and
            a5_report.get("diagnostic_scope_complete") is True and
            a5_report.get("scope_complete") is False,
            "P2-20A.9 A.5 diagnostic state drifted")
    require(a5_evidence.get("report_json", {}).get("sha256") == sha256(
                resolve_inside(root, INPUT_PATHS["a5_report"])),
            "P2-20A.9 A.5 report/evidence cross-binding drifted")

    ignored: list[dict[str, Any]] = []
    for role, document_role, keys in IGNORED_ARTIFACT_SOURCES:
        binding = _artifact_binding(
            root, role, _nested(documents[document_role], keys),
            resolve_inside, sha256, require)
        ignored.append(binding)
        aggregate.update(f"{role}\t{binding['sha256']}\n".encode("ascii"))

    required_roles = [*INPUT_PATHS, *(role for role, _, _ in IGNORED_ARTIFACT_SOURCES)]
    require(package_policy.get("required_input_roles") == required_roles,
            "P2-20A.9 required input roles drifted")
    ignored_roles = package_policy.get("required_ignored_artifact_roles")
    require(isinstance(ignored_roles, list) and
            ignored_roles == REQUIRED_IGNORED_ARTIFACT_ROLES,
            "P2-20A.9 required ignored-artifact roles drifted")
    authority_rules = package_policy.get("authority_rules")
    require(isinstance(authority_rules, dict) and
            set(authority_rules) == set(AUTHORITY_RULES) and
            all(authority_rules[name] is False for name in AUTHORITY_RULES),
            "P2-20A.9 authority rules drifted")
    legacy_bindings = package_policy.get("legacy_source_bindings")
    require(isinstance(legacy_bindings, dict) and legacy_bindings and
            all(isinstance(role, str) and role and isinstance(digest, str) and
                SHA256_PATTERN.fullmatch(digest) is not None
                for role, digest in legacy_bindings.items()),
            "P2-20A.9 legacy-source bindings are incomplete")
    legacy = [{"role": role, "sha256": legacy_bindings[role]}
              for role in sorted(legacy_bindings)]
    require(report.get("input_bindings") == {
                "aggregate_sha256": aggregate.hexdigest(),
                "entries": entries,
                "ignored_artifacts": ignored,
                "legacy_sources": legacy,
            }, "P2-20A.9 input, ignored-artifact, or legacy-source bindings drifted")

    require(package_policy.get("strict_baseline") == STRICT_BASELINE and
            report.get("strict_baseline") == STRICT_BASELINE,
            "P2-20A.9 strict auxiliary baseline drifted")
    a5_region = a5_report.get("measured", {}).get("region_semantic_references", {})
    require(a5_report.get("measured", {}).get("region_strict_instances") ==
            STRICT_BASELINE["region_instances"] and
            a5_region.get("unique_total") == STRICT_BASELINE["unique_total"] and
            a5_region.get("unique_file") == STRICT_BASELINE["unique_file"] and
            a5_region.get("unique_object") == STRICT_BASELINE["unique_object"] and
            a5_region.get("unique_package_root") == STRICT_BASELINE["unique_package_root"] and
            a5_region.get("ambiguous_object") == STRICT_BASELINE["ambiguous_object"] and
            a5_region.get("ambiguous_object_candidate_edges") ==
            STRICT_BASELINE["ambiguous_candidate_edges"] and
            a5_region.get("ambiguous_object_divergent_bodies") ==
            STRICT_BASELINE["divergent_ambiguous_bodies"] and
            a5_region.get("unresolved_resource") == STRICT_BASELINE["unresolved_resource"] and
            a5_region.get("first_candidate_selections") == 0,
            "P2-20A.9 strict baseline does not reconcile to A.5")
    require(package_policy.get("expected_measured") == MEASURED and
            report.get("measured") == MEASURED,
            "P2-20A.9 package-context measurements drifted")
    partition = MEASURED["region_instance_partition"]
    context = MEASURED["package_context"]
    effective = MEASURED["effective_resolution"]
    effective_instances = MEASURED["effective_region_instances"]
    require(sum(partition.values()) == STRICT_BASELINE["region_instances"] and
            context["ambiguous_attempted"] == STRICT_BASELINE["ambiguous_object"] and
            context["original_candidate_edges"] == STRICT_BASELINE["ambiguous_candidate_edges"] and
            context["singleton_matches"] + context["zero_matches"] +
            context["multiple_matches"] == context["ambiguous_attempted"] and
            context["selected_edges"] + context["incompatible_context_edges"] ==
            context["original_candidate_edges"] and
            effective["resolved_total"] + effective["ambiguous_object"] +
            effective["unresolved_resource"] == effective["total_occurrences"] and
            effective["resolved_file"] + effective["resolved_object"] +
            effective["resolved_package_root"] == effective["resolved_total"] and
            effective_instances["resolved_only"] + effective_instances["unresolved_resource"] ==
            STRICT_BASELINE["region_instances"],
            "P2-20A.9 strict/effective arithmetic does not close")
    require(package_policy.get("expected_consumer_controls") == CONSUMER_CONTROLS and
            report.get("consumer_controls") == CONSUMER_CONTROLS,
            "P2-20A.9 consumer controls drifted")
    require(package_policy.get("technical_state") == TECHNICAL_STATE and
            report.get("technical_state") == TECHNICAL_STATE,
            "P2-20A.9 technical state drifted")
    require(package_policy.get("authority_state") == AUTHORITY_STATE and
            report.get("authority_state") == AUTHORITY_STATE,
            "P2-20A.9 authority state drifted")
    require(package_policy.get("preserved_blockers") == PRESERVED_BLOCKERS and
            report.get("preserved_blockers") == PRESERVED_BLOCKERS and
            package_policy.get("blockers") == BLOCKERS and report.get("blockers") == BLOCKERS,
            "P2-20A.9 preserved or active blockers drifted")
    require(report.get("negative_contracts") == package_policy.get("negative_contracts") and
            isinstance(report.get("negative_contracts"), list) and
            len(report["negative_contracts"]) > 0 and
            len(set(report["negative_contracts"])) == len(report["negative_contracts"]),
            "P2-20A.9 negative contracts drifted")
    require(package_policy.get("g2_projection") == G2_PROJECTION and
            report.get("g2_projection") == G2_PROJECTION,
            "P2-20A.9 G2 projection drifted")

    detail_path = resolve_inside(root, DETAIL_EXPORT_PATH)
    expected_detail = {
        "path": DETAIL_EXPORT_PATH,
        "tracked": False,
        "bytes": detail_path.stat().st_size,
        "lines": _line_count(detail_path),
        "sha256": sha256(detail_path),
    }
    require(expected_detail["lines"] == 135 and
            report.get("detail_export") == expected_detail and
            package_policy.get("outputs", {}).get("detail_export") == DETAIL_EXPORT_PATH and
            package_policy.get("outputs", {}).get("detail_export_tracked") is False,
            "P2-20A.9 detail export path, size, line count, or hash drifted")

    expected_contracts = {
        "policy_sha256": sha256(resolve_inside(root, POLICY_PATH)),
        "schema_sha256": sha256(resolve_inside(root, SCHEMA_PATH)),
        "detail_schema_sha256": sha256(resolve_inside(root, DETAIL_SCHEMA_PATH)),
    }
    require(report.get("contracts") == expected_contracts,
            "P2-20A.9 contracts are not exactly hash-bound")
    require(report.get("disclosure") == package_policy.get("disclosure"),
            "P2-20A.9 disclosure boundary drifted")
    disclosure = report["disclosure"]
    require(disclosure.get("tracked_aggregate_and_hash_only") is True and
            disclosure.get("anonymous_detail_only") is True and
            not any(disclosure.get(name) is not False for name in (
                "raw_values", "key_names", "file_names", "private_source_paths",
                "source_line_numbers", "legacy_source_lines", "exact_primary_keys",
                "decoded_payloads")),
            "P2-20A.9 sensitive disclosure was enabled")

    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"],
        "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"],
        "path": relative,
        "sha256": digest,
        "result": report["result"],
        "review_execution_result": report["review_execution_result"],
        "task_status": report["task_status"],
        "completion_criteria_satisfied": report["completion_criteria_satisfied"],
        "diagnostic_scope_complete": report["diagnostic_scope_complete"],
        "scope_complete": report["scope_complete"],
        "g2_06_satisfied": report["g2_06_satisfied"],
    }
    aggregate_line = (
        f"AUX_PACKAGE_CONTEXT|{spec['task_id']}|{spec['criterion_id']}|"
        f"{spec['evidence_revision']}|{relative}|{digest}"
    )
    return binding, report, aggregate_line
