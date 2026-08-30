"""P2-20A.10 source-derived ECF parser-parity binding for G2 review."""

from __future__ import annotations

import hashlib
import json
import re
import struct
from collections import Counter
from pathlib import Path
from typing import Any, Callable


REVISION = "P2-20A.10"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-aux-ecf-parser-parity.jsonl"
POLICY_PATH = "Contracts/data-schema/g2-aux-ecf-parser-parity-policy-v1.json"
SCHEMA_PATH = "Contracts/data-schema/g2-aux-ecf-parser-parity-v1.schema.json"
DETAIL_SCHEMA_PATH = "Contracts/data-schema/g2-aux-ecf-parser-parity-detail-v1.schema.json"
INPUT_PATHS = {
    "auxiliary_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "a3_report": "Data/Reports/p2-20a-aux-config-reference-report.json",
    "a3_evidence": "Data/Inventory/p2-20a-aux-config-reference-evidence.json",
    "a3_parser_implementation": "Tools/TMXY.G2AuxConfigClosure/aux_common.py",
    "a5_report": "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json",
    "a5_evidence": "Data/Inventory/p2-20a-aux-semantic-diagnostics.json",
    "a5_policy": "Contracts/data-schema/g2-aux-semantic-diagnostics-policy-v1.json",
    "a5_support_implementation": "Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_support.py",
    "a9_report": "Data/Reports/p2-20a-aux-package-context-report.json",
    "a9_evidence": "Data/Inventory/p2-20a-aux-package-context.json",
    "asset_inventory": "Data/Inventory/p2-12-full-asset-inventory.json",
    "reference_closure": "Data/Inventory/p2-13-reference-closure.json",
    "p2_05_transform_implementation": "Tools/TMXY.Table/New-AuxiliaryConfigInventory.ps1",
    "policy": POLICY_PATH,
    "schema": SCHEMA_PATH,
    "detail_schema": DETAIL_SCHEMA_PATH,
}
IGNORED_PATHS = {
    "a3_detail": "Data/Exports/P2-20/p2-20a-aux-config-reference-candidates.jsonl",
    "asset_catalog": "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl",
    "reference_graph": "Data/Exports/P2-13/p2-13-reference-closure.jsonl",
}
TOP_LEVEL_FIELDS = {
    "schema_version", "evidence_revision", "captured_utc", "task_id", "criterion_id",
    "source_build", "result", "review_execution_result", "task_status",
    "completion_criteria_satisfied", "diagnostic_scope_complete", "scope_complete",
    "g2_06_satisfied", "p3_authorized", "input_bindings", "historical_a5",
    "source_derived", "candidate_projections", "runtime_boundaries", "blockers",
    "negative_contracts", "detail_export", "g2_projection", "contracts", "disclosure",
}
DETAIL_FIELDS = {
    "schema_version", "instance_id", "source_bytes", "length_remainder",
    "newline_profile", "current_transform_matches_reference", "transform_ports_equal",
    "current_a3_pairs_match_reference", "correct_plain_a3_filter_matches_reference",
    "reference_pair_ports_equal", "current_a3_pair_count", "correct_plain_a3_pair_count",
    "legacy_pair_count", "candidate_projections", "proof_sha256",
}
EXPECTED_HISTORICAL = {
    "evidence_revision": "P2-20A.5", "immutable_baseline": True, "instances": 64,
    "parity_instances": 61, "difference_instances": 3, "legacy_pair_count_delta": 4,
    "a3_only_pair_records": 3, "legacy_only_pair_records": 7,
    "difference_set_sha256": "fdb734d7eaa0f03572738d15f4f6c59abbb2a8eeea767fd4ed7edffded262f8a",
}
EXPECTED_BLOCKERS = [
    {"reason_code": "A3_ECF_TRANSFORM_PARITY_GAPS", "count": 13},
    {"reason_code": "LEGACY_PAIR_RECORDS_ABSENT_FROM_A3", "count": 4},
    {"reason_code": "LEGACY_RUNTIME_NOT_EXECUTED", "count": 1},
    {"reason_code": "RUNTIME_BINARY_PARITY_UNPROVEN", "count": 1},
    {"reason_code": "CONSUMER_CONTRACTS_UNAPPROVED", "count": 212},
]
EXPECTED_RUNTIME = {
    "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False,
    "a3_outputs_modified": False, "valid_semantic_assignments_claimed": False,
    "consumer_contract_approved": False, "semantic_adapter_approved": False,
    "no_reference_approved": False, "root_approved": False,
    "terminal_state_approved": False,
}
EXPECTED_CONTROLS = {
    "candidate_only": True, "frozen_indexes_only": True, "selection_count": 0,
    "approved_roots": 0, "approved_consumer_contracts": 0,
    "approved_semantic_adapters": 0, "approved_no_reference_instances": 0,
    "terminal_instances": 0, "semantic_imports_claimed": 0,
}
EXPECTED_SET_HASHES = {
    "population": "4c4f307498889c10c5548e3b9b23c4ffb537f45af3385418a5b56a002e11e70a",
    "mod3": "8f534fe41c9450a7b864308d60de2e6c73dc3347dee490c85e45b63f334b2150",
    "transform": "4e19dafaafbc02f6fb31b8509c8f3b7700017cafda7afb2dcd9edc8ae7d8328b",
    "filter": "1edb75d2f7fd841c2599691c23b7c259b4de4553c0814a53ccb73159f9e012e9",
}
EXPECTED_LEGACY_SOURCES = {
    "configuration_platform_contract": "cf3fec8a4a753f1184999e168817257ca9112eb3619880085b7f8f329bc9a590",
    "cstring_contract": "8c9b1a68411a66ca0285ee24bed96ff8f664aedc753770d4285e25b76ed136af",
    "encrypted_config_reader": "f1bef9a8221f2e05bdf855d7038d71f9222792a349f8e29944651cbddf0c4042",
    "line_and_pair_parser": "bab39ccce47907e06dbac0913c2edf2b43350a7efae867cb8b9c61fb56880314",
    "reflection_config_loader": "3a4ba187ea1099706328c0b49084ad555fa3d2f68f16d8b8e7f0a53fa0b8fc57",
    "string_contract": "e3f2856c105711d5a1f3e792c17b715419eab1a12571f8faa4b065ffcb8a37d0",
}
EXPECTED_IMPLEMENTATIONS = {
    "p2_05_transform_implementation_sha256": "0e4828ef6eda2f61e2b727ffe2fe2e13b26d668e8083594945cc7b589462797b",
    "a3_parser_implementation_sha256": "cc90300cb0ffd05d71ac0ced00231ea680cd48c91817f1acb66a432eb75ab31f",
    "a5_support_implementation_sha256": "01bc061ee355d5ece17e1630b35df27e82db2cc37b30735c19c4ac4aa14ad18e",
}
AUTHORITY_RULES = {
    "source_derived_port_is_runtime_execution", "reference_port_parity_is_binary_parity",
    "additional_pair_record_is_valid_assignment_approval",
    "candidate_projection_is_semantic_reference", "diagnostic_can_rewrite_a3_outputs",
    "diagnostic_can_approve_consumer_contract", "diagnostic_can_approve_adapter_or_no_ref",
    "diagnostic_can_approve_root_or_terminal_state", "this_evidence_can_approve_g2_or_p3",
}
SHA256 = re.compile(r"[0-9a-f]{64}")


def _ordered_hash(values: list[str]) -> str:
    digest = hashlib.sha256()
    for value in values:
        encoded = value.encode("utf-8")
        digest.update(struct.pack(">Q", len(encoded)))
        digest.update(encoded)
    return digest.hexdigest()


def _set_hash(values: list[str]) -> str:
    return _ordered_hash(sorted(values))


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def _ignored_binding(root: Path, role: str, declared: dict[str, Any],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> dict[str, Any]:
    relative = IGNORED_PATHS[role]
    path = resolve_inside(root, relative)
    expected = {"role": role, "path": relative, "bytes": path.stat().st_size,
                "lines": _line_count(path), "sha256": sha256(path), "tracked": False}
    require(declared == expected, f"P2-20A.10 {role} ignored artifact drifted")
    return expected


def _validate_detail(root: Path, report: dict[str, Any],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> dict[str, Any]:
    path = resolve_inside(root, DETAIL_PATH)
    binding = {"tracked": False, "path": DETAIL_PATH, "lines": _line_count(path),
               "bytes": path.stat().st_size, "sha256": sha256(path)}
    require(report.get("detail_export") == binding and binding["lines"] == 64,
            "P2-20A.10 detail export binding drifted")
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            require(isinstance(row, dict) and set(row) == DETAIL_FIELDS and
                    row.get("schema_version") == 1 and
                    SHA256.fullmatch(str(row.get("instance_id"))) is not None and
                    SHA256.fullmatch(str(row.get("proof_sha256"))) is not None,
                    "P2-20A.10 anonymous detail shape drifted")
            rows.append(row)
    ids = [row["instance_id"] for row in rows]
    require(ids == sorted(ids) and len(set(ids)) == 64 and
            all(row["newline_profile"] == "CRLF_ONLY" for row in rows),
            "P2-20A.10 detail population or newline profile drifted")
    remainders = Counter(row["length_remainder"] for row in rows)
    transform_gaps = [row["instance_id"] for row in rows
                      if row["current_transform_matches_reference"] is False]
    pair_gaps = [row["instance_id"] for row in rows
                 if row["current_a3_pairs_match_reference"] is False]
    filter_gaps = [row["instance_id"] for row in rows
                   if row["correct_plain_a3_filter_matches_reference"] is False]
    require(remainders == {0: 15, 1: 21, 2: 14, 3: 14} and
            all(row["transform_ports_equal"] is True and
                row["reference_pair_ports_equal"] is True for row in rows) and
            transform_gaps == pair_gaps and len(transform_gaps) == 13 and
            len(filter_gaps) == 1 and sum(row["source_bytes"] for row in rows) == 57011 and
            sum(row["current_a3_pair_count"] for row in rows) == 2065 and
            sum(row["correct_plain_a3_pair_count"] for row in rows) == 2065 and
            sum(row["legacy_pair_count"] for row in rows) == 2069,
            "P2-20A.10 detail transform or pair arithmetic drifted")
    hashes = {"population": _set_hash(ids),
              "mod3": _set_hash([row["instance_id"] for row in rows
                                  if row["length_remainder"] == 3]),
              "transform": _set_hash(transform_gaps), "filter": _set_hash(filter_gaps)}
    require(hashes == EXPECTED_SET_HASHES, "P2-20A.10 anonymous set hashes drifted")
    projection_totals: dict[str, Counter[str]] = {
        name: Counter() for name in
        ("frozen_a3", "correct_transform_a3_filter", "source_derived_legacy_pairs")}
    for row in rows:
        projections = row.get("candidate_projections")
        require(isinstance(projections, dict) and set(projections) == set(projection_totals),
                "P2-20A.10 detail candidate projection layers drifted")
        for name, target in projection_totals.items():
            layer = projections[name]
            require(isinstance(layer, dict) and SHA256.fullmatch(
                str(layer.get("candidate_multiset_sha256"))) is not None,
                "P2-20A.10 detail candidate projection shape drifted")
            for key, value in layer.items():
                if key != "candidate_multiset_sha256":
                    require(isinstance(value, int) and not isinstance(value, bool) and value >= 0,
                            "P2-20A.10 detail candidate count is invalid")
                    target[key] += value
    report_ecf = report["candidate_projections"]["ecf"]
    for name, totals in projection_totals.items():
        require(all(report_ecf[name].get(key) == value for key, value in totals.items()),
                f"P2-20A.10 {name} detail/report candidate totals drifted")
    return binding


def _validate_layers(report: dict[str, Any], policy: dict[str, Any],
                     require: Callable[[bool, str], None]) -> None:
    source = report.get("source_derived", {})
    population = source.get("population", {})
    newline = source.get("newline", {})
    transforms = source.get("reference_transform_ports", {})
    actual = source.get("a3_actual_vs_reference", {})
    filtered = source.get("correct_plain_a3_filter_vs_legacy", {})
    pair_ports = source.get("reference_pair_ports", {})
    require(source.get("derivation_scope") == "SOURCE_DERIVED_DIAGNOSTIC_ONLY" and
            population == {"instances": 64, "source_bytes": 57011,
                "length_remainders": {"mod0": 15, "mod1": 21, "mod2": 14, "mod3": 14},
                "population_set_sha256": EXPECTED_SET_HASHES["population"],
                "mod3_set_sha256": EXPECTED_SET_HASHES["mod3"]} and
            newline == {"crlf_only_instances": 64, "crlf_pairs": 2351, "lone_lf": 0,
                "lone_cr": 0, "nul": 0, "trailing_crlf_instances": 9,
                "mixed_instances": 0, "no_trailing_crlf_instances": 55},
            "P2-20A.10 source-derived population or newline layer drifted")
    require(transforms == {"parity_instances": 64, "difference_instances": 0,
                "frozen_a3_body_parity_instances": 51,
                "frozen_a3_body_difference_instances": 13,
                "difference_set_sha256": EXPECTED_SET_HASHES["transform"]} and
            actual == {"parity_instances": 51, "difference_instances": 13,
                "left_pair_records": 2065, "right_pair_records": 2069,
                "shared_pair_records": 2052, "left_only_pair_records": 13,
                "right_only_pair_records": 17,
                "difference_set_sha256": EXPECTED_SET_HASHES["transform"]} and
            filtered == {"parity_instances": 63, "difference_instances": 1,
                "left_pair_records": 2065, "right_pair_records": 2069,
                "shared_pair_records": 2065, "left_only_pair_records": 0,
                "right_only_pair_records": 4,
                "difference_set_sha256": EXPECTED_SET_HASHES["filter"]} and
            pair_ports == {"parity_instances": 64, "difference_instances": 0,
                "reference_pair_records": 2069, "independent_pair_records": 2069},
            "P2-20A.10 transform, A.3 actual, filter, or pair-port layer drifted")
    require(policy.get("expected_population") == {
                "instances": 64, "source_bytes": 57011,
                "length_remainders": {"mod0": 15, "mod1": 21, "mod2": 14, "mod3": 14},
                "population_set_sha256": EXPECTED_SET_HASHES["population"],
                "mod3_set_sha256": EXPECTED_SET_HASHES["mod3"]} and
            policy.get("expected_source_derived", {}).get(
                "transform_body_difference_instances") == 13 and
            policy["expected_source_derived"]["a3_actual_vs_reference"] == {
                "parity_instances": 51, "difference_instances": 13,
                "a3_pair_records": 2065, "legacy_pair_records": 2069,
                "shared_pair_records": 2052, "a3_only_pair_records": 13,
                "legacy_only_pair_records": 17} and
            policy["expected_source_derived"]["correct_plain_a3_filter_vs_legacy"][
                "legacy_only_pair_records"] == 4,
            "P2-20A.10 policy layer baseline drifted")


def aux_ecf_parser_parity_safe(report: dict[str, Any]) -> bool:
    """Return true only for the expected fail-closed diagnostic state."""
    return (report.get("diagnostic_scope_complete") is True and
            report.get("scope_complete") is False and report.get("g2_06_satisfied") is False and
            report.get("p3_authorized") is False and
            report.get("runtime_boundaries") == EXPECTED_RUNTIME and
            report.get("candidate_projections", {}).get("controls") == EXPECTED_CONTROLS)


def aux_ecf_parser_parity_metrics(report: dict[str, Any]) -> list[tuple[str, Any, str]]:
    """Provide compact G2-06 metrics without expanding the main generator."""
    source = report["source_derived"]
    actual = source["a3_actual_vs_reference"]
    filtered = source["correct_plain_a3_filter_vs_legacy"]
    runtime = report["runtime_boundaries"]
    controls = report["candidate_projections"]["controls"]
    return [
        ("aux_ecf_parser_parity_hash_bound", True, "boolean"),
        ("aux_ecf_historical_a5_parity_instances", report["historical_a5"]["parity_instances"], "files"),
        ("aux_ecf_historical_a5_difference_instances", report["historical_a5"]["difference_instances"], "files"),
        ("aux_ecf_historical_a5_pair_count_delta", report["historical_a5"]["legacy_pair_count_delta"], "pair_records"),
        ("aux_ecf_a3_actual_parity_instances", actual["parity_instances"], "files"),
        ("aux_ecf_a3_actual_difference_instances", actual["difference_instances"], "files"),
        ("aux_ecf_correct_plain_filter_parity_instances", filtered["parity_instances"], "files"),
        ("aux_ecf_legacy_pair_records_absent_from_a3", filtered["right_only_pair_records"], "pair_records"),
        ("aux_ecf_reference_transform_port_differences", source["reference_transform_ports"]["difference_instances"], "files"),
        ("aux_ecf_reference_pair_port_differences", source["reference_pair_ports"]["difference_instances"], "files"),
        ("aux_ecf_legacy_runtime_executed", runtime["legacy_runtime_executed"], "boolean"),
        ("aux_ecf_runtime_binary_parity_claimed", runtime["runtime_binary_parity_claimed"], "boolean"),
        ("aux_ecf_a3_outputs_modified", runtime["a3_outputs_modified"], "boolean"),
        ("aux_ecf_semantic_imports_claimed", controls["semantic_imports_claimed"], "count"),
    ]


def bind_aux_ecf_parser_parity(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    """Bind and independently re-check the fail-closed A.10 report."""
    spec = policy["aux_ecf_parser_parity"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    report = load_json(path)
    require(set(report) == TOP_LEVEL_FIELDS and report.get("schema_version") == 1 and
            report.get("task_id") == spec["task_id"] and
            report.get("criterion_id") == spec["criterion_id"] and
            report.get("evidence_revision") == spec["evidence_revision"] == REVISION and
            report.get("source_build") == policy["source_build"] and
            isinstance(report.get("captured_utc"), str),
            "P2-20A.10 ECF parser-parity identity or shape mismatch")
    require(report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            aux_ecf_parser_parity_safe(report),
            "P2-20A.10 ECF parser-parity state was falsely promoted")
    documents = {role: load_json(resolve_inside(root, relative_path))
                 for role, relative_path in INPUT_PATHS.items()
                 if role not in {"a3_parser_implementation", "a5_support_implementation",
                                 "p2_05_transform_implementation"}}
    diagnostic_policy = documents["policy"]
    require(diagnostic_policy.get("schema_version") == 1 and
            diagnostic_policy.get("task_id") == spec["task_id"] and
            diagnostic_policy.get("criterion_id") == spec["criterion_id"] and
            diagnostic_policy.get("evidence_revision") == REVISION and
            diagnostic_policy.get("source_build") == policy["source_build"] and
            diagnostic_policy.get("required_input_roles") == [*INPUT_PATHS, *IGNORED_PATHS] and
            diagnostic_policy.get("required_ignored_artifact_roles") == list(IGNORED_PATHS),
            "P2-20A.10 policy identity or role boundary drifted")
    entries = [{"role": role, "sha256": sha256(resolve_inside(root, input_relative))}
               for role, input_relative in INPUT_PATHS.items()]
    declared_ignored = report.get("input_bindings", {}).get("ignored_artifacts")
    require(isinstance(declared_ignored, list) and len(declared_ignored) == 3,
            "P2-20A.10 ignored-artifact bindings are absent")
    ignored = [_ignored_binding(root, role, declared_ignored[index], resolve_inside,
                                sha256, require)
               for index, role in enumerate(IGNORED_PATHS)]
    legacy_bindings = diagnostic_policy.get("legacy_source_bindings")
    require(legacy_bindings == EXPECTED_LEGACY_SOURCES and
            diagnostic_policy.get("implementation_baseline") == EXPECTED_IMPLEMENTATIONS and
            entries[3]["sha256"] == EXPECTED_IMPLEMENTATIONS["a3_parser_implementation_sha256"] and
            entries[7]["sha256"] == EXPECTED_IMPLEMENTATIONS["a5_support_implementation_sha256"] and
            entries[12]["sha256"] == EXPECTED_IMPLEMENTATIONS["p2_05_transform_implementation_sha256"],
            "P2-20A.10 legacy source or implementation baseline drifted")
    legacy = [{"role": role, "sha256": legacy_bindings[role]}
              for role in sorted(legacy_bindings)]
    aggregate = _ordered_hash([f"{item['role']}:{item['sha256']}"
                               for item in [*entries, *ignored, *legacy]])
    require(report.get("input_bindings") == {"aggregate_sha256": aggregate,
                "entries": entries, "ignored_artifacts": ignored, "legacy_sources": legacy},
            "P2-20A.10 input, ignored-artifact, or legacy bindings drifted")
    a5 = documents["a5_report"]
    require(a5.get("evidence_revision") == "P2-20A.5" and
            a5.get("measured", {}).get("ecf", {}).get("instances") == 64 and
            a5["measured"]["ecf"].get("mixed_newline_differences") == 3 and
            a5["measured"]["ecf"].get("legacy_assignments_missed_by_a3_parser") == 4 and
            report.get("historical_a5") == EXPECTED_HISTORICAL and
            diagnostic_policy.get("expected_historical_a5", {}).get("difference_instances") == 3 and
            diagnostic_policy["expected_historical_a5"].get("legacy_pair_count_delta") == 4,
            "P2-20A.10 immutable A.5 historical layer drifted")
    _validate_layers(report, diagnostic_policy, require)
    _validate_detail(root, report, resolve_inside, sha256, require)
    report_ecf = report.get("candidate_projections", {}).get("ecf", {})
    expected_ecf = diagnostic_policy.get("expected_ecf_candidate_projections", {})
    require(set(report_ecf) == set(expected_ecf) and
            all(all(report_ecf[layer].get(name) == value
                    for name, value in expected.items())
                for layer, expected in expected_ecf.items()) and
            report.get("candidate_projections", {}).get("global") ==
            diagnostic_policy.get("expected_global_candidate_projections") and
            all(SHA256.fullmatch(str(layer.get("candidate_multiset_sha256"))) is not None
                for layer in report_ecf.values()),
            "P2-20A.10 candidate projection baselines drifted")
    require(report.get("candidate_projections", {}).get("scope") ==
            "CANDIDATE_ONLY_NON_MUTATING_PROJECTION" and
            report["candidate_projections"].get("controls") == EXPECTED_CONTROLS and
            diagnostic_policy.get("candidate_projection_controls") == EXPECTED_CONTROLS and
            report.get("runtime_boundaries") == EXPECTED_RUNTIME and
            diagnostic_policy.get("authority_rules") == {
                name: False for name in AUTHORITY_RULES},
            "P2-20A.10 candidate-only or authority boundary drifted")
    require(report.get("blockers") == EXPECTED_BLOCKERS == diagnostic_policy.get("blockers") and
            report.get("negative_contracts") == diagnostic_policy.get("negative_contracts") and
            isinstance(report.get("negative_contracts"), list) and
            len(report["negative_contracts"]) == len(set(report["negative_contracts"])) and
            report.get("g2_projection") == diagnostic_policy.get("g2_projection") == {
                "criteria_total": 9, "satisfied": 7, "blocked": 2,
                "g2_decision": "BLOCKED"},
            "P2-20A.10 blockers, negative contracts, or G2 projection drifted")
    require(report.get("contracts") == {
                "policy_sha256": sha256(resolve_inside(root, POLICY_PATH)),
                "schema_sha256": sha256(resolve_inside(root, SCHEMA_PATH)),
                "detail_schema_sha256": sha256(resolve_inside(root, DETAIL_SCHEMA_PATH))},
            "P2-20A.10 contracts are not exactly hash-bound")
    disclosure = report.get("disclosure")
    require(disclosure == diagnostic_policy.get("disclosure") and
            disclosure.get("tracked_aggregate_and_hash_only") is True and
            disclosure.get("anonymous_detail_only") is True and
            not any(disclosure.get(name) is not False for name in (
                "raw_values", "key_names", "file_names", "private_source_paths",
                "source_line_numbers", "legacy_source_lines", "exact_primary_keys",
                "decoded_payloads")),
            "P2-20A.10 disclosure boundary failed")
    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"], "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"], "path": relative,
        "sha256": digest, "result": report["result"],
        "review_execution_result": report["review_execution_result"],
        "task_status": report["task_status"],
        "completion_criteria_satisfied": report["completion_criteria_satisfied"],
        "diagnostic_scope_complete": report["diagnostic_scope_complete"],
        "scope_complete": report["scope_complete"],
        "g2_06_satisfied": report["g2_06_satisfied"],
    }
    aggregate_line = (f"AUX_ECF_PARSER_PARITY|{spec['task_id']}|{spec['criterion_id']}|"
                      f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, report, aggregate_line
