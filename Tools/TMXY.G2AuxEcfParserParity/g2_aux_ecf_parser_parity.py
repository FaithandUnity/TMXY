#!/usr/bin/env python3
"""Generate disclosure-safe P2-20A.10 source-derived ECF parser diagnostics."""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path
from typing import Any, Sequence

from aux_ecf_parser_parity_support import (
    EvidenceError, a3_pairs, bind_legacy_sources, candidate_projection,
    canonical_identity, compare_pairs, current_a3_transform, domain_hash,
    independent_legacy_pairs, independent_legacy_transform, load_indexes, load_json,
    newline_profile, ordered_string_hash, reference_legacy_pairs,
    reference_legacy_transform, require, resolve_inside, run_self_test, sha256_bytes,
    sha256_file, string_set_hash,
)


REVISION = "P2-20A.10"
DETAIL_RELATIVE = "Data/Exports/P2-20/p2-20a-aux-ecf-parser-parity.jsonl"
INPUTS = collections.OrderedDict((
    ("auxiliary_inventory", "Data/Inventory/p2-05-auxiliary-config-inventory.json"),
    ("a3_report", "Data/Reports/p2-20a-aux-config-reference-report.json"),
    ("a3_evidence", "Data/Inventory/p2-20a-aux-config-reference-evidence.json"),
    ("a3_parser_implementation", "Tools/TMXY.G2AuxConfigClosure/aux_common.py"),
    ("a5_report", "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json"),
    ("a5_evidence", "Data/Inventory/p2-20a-aux-semantic-diagnostics.json"),
    ("a5_policy", "Contracts/data-schema/g2-aux-semantic-diagnostics-policy-v1.json"),
    ("a5_support_implementation", "Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_support.py"),
    ("a9_report", "Data/Reports/p2-20a-aux-package-context-report.json"),
    ("a9_evidence", "Data/Inventory/p2-20a-aux-package-context.json"),
    ("asset_inventory", "Data/Inventory/p2-12-full-asset-inventory.json"),
    ("reference_closure", "Data/Inventory/p2-13-reference-closure.json"),
    ("p2_05_transform_implementation", "Tools/TMXY.Table/New-AuxiliaryConfigInventory.ps1"),
    ("policy", "Contracts/data-schema/g2-aux-ecf-parser-parity-policy-v1.json"),
    ("schema", "Contracts/data-schema/g2-aux-ecf-parser-parity-v1.schema.json"),
    ("detail_schema", "Contracts/data-schema/g2-aux-ecf-parser-parity-detail-v1.schema.json"),
))
IGNORED_ROLES = ("a3_detail", "asset_catalog", "reference_graph")


def json_bytes(value: Any, compact: bool = False) -> bytes:
    separators = (",", ":") if compact else None
    return (json.dumps(value, ensure_ascii=False, sort_keys=compact, indent=None if compact else 2,
                       separators=separators) + "\n").encode("utf-8")


def write_output(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)


def ignored_binding(root: Path, role: str, declared: dict[str, Any]) -> dict[str, Any]:
    require(declared.get("tracked") is False, f"{role} must remain ignored")
    path = resolve_inside(root, declared.get("path"), role)
    lines = sum(1 for _ in path.open("rb"))
    require(path.stat().st_size == int(declared.get("bytes", -1)) and
            sha256_file(path) == declared.get("sha256") and
            lines == int(declared.get("lines", -1)), f"{role} drifted")
    return {"role": role, "path": declared["path"], "bytes": path.stat().st_size,
            "lines": lines, "sha256": sha256_file(path), "tracked": False}


def validate_upstream(root: Path, docs: dict[str, dict[str, Any]],
                      policy: dict[str, Any]) -> None:
    for revision, report_role, evidence_role in (
        ("P2-20A.3", "a3_report", "a3_evidence"),
        ("P2-20A.5", "a5_report", "a5_evidence"),
        ("P2-20A.9", "a9_report", "a9_evidence"),
    ):
        report, evidence = docs[report_role], docs[evidence_role]
        require(report.get("evidence_revision") == revision and
                evidence.get("evidence_revision") == revision and
                report.get("result") == evidence.get("result") == "BLOCKED" and
                report.get("review_execution_result") ==
                evidence.get("review_execution_result") == "PASS" and
                report.get("g2_06_satisfied") is False and
                evidence.get("p3_authorized") is False,
                f"{revision} state drifted")
        report_binding = (evidence.get("outputs", {}).get("report_json")
                          if revision == "P2-20A.3" else evidence.get("report_json"))
        require(isinstance(report_binding, dict) and
                report_binding.get("sha256") == sha256_file(root / INPUTS[report_role]),
                f"{revision} report/evidence cross-binding drifted")
    ecf = docs["a5_report"].get("measured", {}).get("ecf", {})
    historical = policy["expected_historical_a5"]
    require(ecf.get("instances") == historical["instances"] and
            ecf.get("mixed_newline_differences") == historical["difference_instances"] and
            ecf.get("legacy_assignments_missed_by_a3_parser") ==
            historical["legacy_pair_count_delta"],
            "P2-20A.5 immutable ECF baseline drifted")
    preserved = docs["a9_report"].get("preserved_blockers", {})
    require(preserved.get("ecf_parser_parity_gaps") == 3 and
            preserved.get("ecf_assignments_missed") == 4,
            "P2-20A.9 historical blocker binding drifted")
    baseline = policy["implementation_baseline"]
    require(sha256_file(root / INPUTS["p2_05_transform_implementation"]) ==
            baseline["p2_05_transform_implementation_sha256"] and
            sha256_file(root / INPUTS["a3_parser_implementation"]) ==
            baseline["a3_parser_implementation_sha256"] and
            sha256_file(root / INPUTS["a5_support_implementation"]) ==
            baseline["a5_support_implementation_sha256"],
            "frozen implementation baseline drifted")


def load_a3_scopes(root: Path, evidence: dict[str, Any]) -> tuple[dict[str, Any],
                                                                  dict[str, dict[str, Any]]]:
    declared = evidence.get("outputs", {}).get("anonymous_candidate_export")
    require(isinstance(declared, dict), "A.3 detail binding is absent")
    binding = ignored_binding(root, "a3_detail", declared)
    scopes: dict[str, dict[str, Any]] = {}
    counts = collections.Counter()
    with (root / declared["path"]).open("rb") as stream:
        for raw in stream:
            record = json.loads(raw)
            kind = record.get("record")
            counts[str(kind)] += 1
            if kind == "auxiliary_config_file_scope" and record.get("source_kind") == "ecf":
                source_id = record.get("source_file_id")
                require(isinstance(source_id, str) and source_id not in scopes,
                        "A.3 ECF scope identity is invalid")
                scopes[source_id] = record
    require(counts == {"auxiliary_config_file_scope": 212,
                       "auxiliary_config_reference_candidate": 3689,
                       "auxiliary_config_scope_blocker": 6} and len(scopes) == 64,
            "A.3 ignored-detail shape drifted")
    return binding, scopes


def aggregate_projection(items: Sequence[tuple[dict[str, Any], list[str]]]) -> dict[str, Any]:
    result = collections.Counter()
    candidates: list[str] = []
    for projection, identities in items:
        candidates.extend(identities)
        for key, value in projection.items():
            if key != "candidate_multiset_sha256":
                result[key] += int(value)
    return {**dict(result), "candidate_multiset_sha256": ordered_string_hash(sorted(candidates))}


def comparison(counter: collections.Counter[str], difference_ids: list[str],
               left_name: str, right_name: str) -> dict[str, Any]:
    return {
        "parity_instances": 64 - len(difference_ids),
        "difference_instances": len(difference_ids),
        f"{left_name}_pair_records": counter["left_count"],
        f"{right_name}_pair_records": counter["right_count"],
        "shared_pair_records": counter["shared_count"],
        f"{left_name}_only_pair_records": counter["left_only_count"],
        f"{right_name}_only_pair_records": counter["right_only_count"],
        "difference_set_sha256": string_set_hash(difference_ids),
    }


def normalized_comparison(value: dict[str, Any]) -> dict[str, Any]:
    keys = list(value)
    left = next(key[:-13] for key in keys if key.endswith("_pair_records") and
                key not in {"shared_pair_records"} and "only" not in key)
    remaining = [key[:-13] for key in keys if key.endswith("_pair_records") and
                 key not in {"shared_pair_records"} and "only" not in key and
                 not key.startswith(left)]
    right = remaining[0]
    return {
        "parity_instances": value["parity_instances"],
        "difference_instances": value["difference_instances"],
        "left_pair_records": value[f"{left}_pair_records"],
        "right_pair_records": value[f"{right}_pair_records"],
        "shared_pair_records": value["shared_pair_records"],
        "left_only_pair_records": value[f"{left}_only_pair_records"],
        "right_only_pair_records": value[f"{right}_only_pair_records"],
        "difference_set_sha256": value["difference_set_sha256"],
    }


def require_subset(actual: dict[str, Any], expected: dict[str, Any], label: str) -> None:
    require(all(actual.get(key) == value for key, value in expected.items()),
            f"{label} drifted: {actual!r} != {expected!r}")


def scan(root: Path, docs: dict[str, dict[str, Any]], policy: dict[str, Any],
         scopes: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    inventory = docs["auxiliary_inventory"]
    files = inventory.get("files")
    source = inventory.get("source")
    require(isinstance(files, list) and isinstance(source, dict), "P2-05 inventory is incomplete")
    ecf_entries = [entry for entry in files if entry.get("kind") == "ecf"]
    require(len(ecf_entries) == 64, "P2-05 ECF population drifted")
    sandbox = resolve_inside(root, source.get("sandbox_relative_path"), "P2-05 sandbox")
    indexes = load_indexes(root, inventory, docs["asset_inventory"], docs["reference_closure"])
    details: list[dict[str, Any]] = []
    instance_ids: list[str] = []
    mod3_ids: list[str] = []
    transform_differences: list[str] = []
    historical_differences: list[str] = []
    actual_differences: list[str] = []
    filter_differences: list[str] = []
    newline = collections.Counter()
    comparisons = {name: collections.Counter() for name in ("historical", "actual", "filter")}
    projection_items: dict[str, list[tuple[dict[str, Any], list[str]]]] = {
        name: [] for name in ("frozen_a3", "correct_transform_a3_filter",
                              "source_derived_legacy_pairs")}
    source_bytes = 0
    remainders = collections.Counter()
    legacy_pairs_total = 0
    for entry in sorted(ecf_entries, key=lambda item: canonical_identity(str(item["path"]))):
        raw = resolve_inside(sandbox, entry.get("path"), "ECF source").read_bytes()
        require(len(raw) == int(entry["bytes"]) and sha256_bytes(raw) == entry["sha256"],
                "ECF source binding drifted")
        instance_id = domain_hash("g2-aux-source-file-v1",
                                  canonical_identity(str(entry["path"])), entry["sha256"])
        instance_ids.append(instance_id)
        source_bytes += len(raw)
        remainder = len(raw) % 4
        remainders[f"mod{remainder}"] += 1
        if remainder == 3:
            mod3_ids.append(instance_id)
        current_plain = current_a3_transform(raw)
        correct_plain = reference_legacy_transform(raw)
        independent_plain = independent_legacy_transform(raw)
        require(correct_plain == independent_plain, "reference transform ports disagree")
        if current_plain != correct_plain:
            transform_differences.append(instance_id)
        classification = entry.get("encoding", {}).get("classification")
        require(isinstance(classification, str), "ECF encoding classification is absent")
        current_pairs = a3_pairs(current_plain, classification)
        current_legacy_pairs = reference_legacy_pairs(current_plain)
        correct_a3_pairs = a3_pairs(correct_plain, classification)
        correct_legacy_pairs = reference_legacy_pairs(correct_plain)
        independent_pairs = independent_legacy_pairs(correct_plain)
        require(correct_legacy_pairs == independent_pairs, "reference pair ports disagree")
        legacy_pairs_total += len(correct_legacy_pairs)
        comparisons_to_run = (
            ("historical", current_pairs, current_legacy_pairs, historical_differences),
            ("actual", current_pairs, correct_legacy_pairs, actual_differences),
            ("filter", correct_a3_pairs, correct_legacy_pairs, filter_differences),
        )
        for name, left, right, differences in comparisons_to_run:
            result = compare_pairs(left, right)
            for field in ("left_count", "right_count", "shared_count",
                          "left_only_count", "right_only_count"):
                comparisons[name][field] += int(result[field])
            if not result["equal"]:
                differences.append(instance_id)
        profile = newline_profile(correct_plain)
        require(profile["profile"] == "CRLF_ONLY" and profile["nul"] == 0,
                "source-derived plaintext newline or NUL boundary drifted")
        newline["crlf_only_instances"] += 1
        newline["crlf_pairs"] += int(profile["crlf"])
        newline["lone_lf"] += int(profile["lone_lf"])
        newline["lone_cr"] += int(profile["lone_cr"])
        newline["nul"] += int(profile["nul"])
        newline["trailing_crlf_instances"] += int(profile["trailing_crlf"])
        projections: dict[str, dict[str, Any]] = {}
        for name, pairs in (("frozen_a3", current_pairs),
                            ("correct_transform_a3_filter", correct_a3_pairs),
                            ("source_derived_legacy_pairs", correct_legacy_pairs)):
            projected, candidate_ids = candidate_projection(pairs, classification, indexes)
            projections[name] = projected
            projection_items[name].append((projected, candidate_ids))
        scope = scopes.get(instance_id)
        require(isinstance(scope, dict) and scope.get("scalar_locations") == len(current_pairs) and
                scope.get("nonempty_scalar_locations") == projections["frozen_a3"]["nonempty_pair_values"] and
                scope.get("resource_candidate_occurrences") ==
                projections["frozen_a3"]["asset_occurrences"] +
                projections["frozen_a3"]["package_occurrences"] and
                scope.get("config_candidate_occurrences") ==
                projections["frozen_a3"]["config_occurrences"],
                "frozen A.3 per-ECF scope does not match its parser reproduction")
        detail = {
            "schema_version": 1, "instance_id": instance_id, "source_bytes": len(raw),
            "length_remainder": remainder, "transform_ports_equal": True,
            "current_transform_matches_reference": current_plain == correct_plain,
            "current_a3_pairs_match_reference": current_pairs == correct_legacy_pairs,
            "correct_plain_a3_filter_matches_reference": correct_a3_pairs == correct_legacy_pairs,
            "reference_pair_ports_equal": True, "current_a3_pair_count": len(current_pairs),
            "correct_plain_a3_pair_count": len(correct_a3_pairs),
            "legacy_pair_count": len(correct_legacy_pairs), "newline_profile": "CRLF_ONLY",
            "candidate_projections": projections,
        }
        detail["proof_sha256"] = sha256_bytes(json_bytes(detail, compact=True))
        details.append(detail)
    require(len(set(instance_ids)) == 64 and set(scopes) == set(instance_ids),
            "ECF instance population does not close")
    population = {"instances": 64, "source_bytes": source_bytes,
                  "length_remainders": dict(sorted(remainders.items())),
                  "population_set_sha256": string_set_hash(instance_ids),
                  "mod3_set_sha256": string_set_hash(mod3_ids)}
    newline["mixed_instances"] = 0
    newline["no_trailing_crlf_instances"] = 64 - newline["trailing_crlf_instances"]
    actual = comparison(comparisons["actual"], actual_differences, "a3", "legacy")
    filtered = comparison(comparisons["filter"], filter_differences, "a3", "legacy")
    historical = comparison(comparisons["historical"], historical_differences,
                            "a3", "legacy")
    ecf_projections = {name: aggregate_projection(items)
                       for name, items in projection_items.items()}
    measured = docs["a3_report"]["measured_lexical_candidates"]
    current = ecf_projections["frozen_a3"]
    global_projections: dict[str, dict[str, int]] = {}
    for name, projection in ecf_projections.items():
        occurrence_delta = (projection["asset_occurrences"] + projection["package_occurrences"] +
                            projection["config_occurrences"] - current["asset_occurrences"] -
                            current["package_occurrences"] - current["config_occurrences"])
        global_projections[name] = {
            "scalar_positions": measured["scalar_positions"] - current["pair_records"] + projection["pair_records"],
            "nonempty_scalar_positions": measured["nonempty_scalar_positions"] - current["nonempty_pair_values"] + projection["nonempty_pair_values"],
            "package_exact_occurrences": measured["package_exact_occurrences"] - current["package_occurrences"] + projection["package_occurrences"],
            "package_unique_occurrences": measured["package_unique_occurrences"] - current["package_unique"] + projection["package_unique"],
            "package_ambiguous_occurrences": measured["package_ambiguous_occurrences"] - current["package_ambiguous"] + projection["package_ambiguous"],
            "package_candidate_edges": measured["package_ambiguous_candidate_edges"] - current["package_edges"] + projection["package_edges"],
            "runtime_ecf_resource_identities": projection["asset_occurrences"] + projection["package_occurrences"],
            "predicted_detail_lines": 3907 + occurrence_delta,
        }
    source_derived = {
        "derivation_scope": "SOURCE_DERIVED_DIAGNOSTIC_ONLY", "population": population,
        "newline": dict(newline),
        "reference_transform_ports": {"parity_instances": 64, "difference_instances": 0,
            "frozen_a3_body_parity_instances": 64 - len(transform_differences),
            "frozen_a3_body_difference_instances": len(transform_differences),
            "difference_set_sha256": string_set_hash(transform_differences)},
        "a3_actual_vs_reference": normalized_comparison(actual),
        "correct_plain_a3_filter_vs_legacy": normalized_comparison(filtered),
        "reference_pair_ports": {"parity_instances": 64, "difference_instances": 0,
                                 "reference_pair_records": legacy_pairs_total,
                                 "independent_pair_records": legacy_pairs_total},
    }
    historical_report = {"evidence_revision": "P2-20A.5", "immutable_baseline": True,
                         "instances": 64, "parity_instances": historical["parity_instances"],
                         "difference_instances": historical["difference_instances"],
                         "legacy_pair_count_delta": historical["legacy_only_pair_records"] -
                         historical["a3_only_pair_records"],
                         "a3_only_pair_records": historical["a3_only_pair_records"],
                         "legacy_only_pair_records": historical["legacy_only_pair_records"],
                         "difference_set_sha256": historical["difference_set_sha256"]}
    require_subset(population, policy["expected_population"], "source population")
    require_subset(historical_report, {"instances": 64, "parity_instances": 61,
                   "difference_instances": 3, "legacy_pair_count_delta": 4,
                   "a3_only_pair_records": 3, "legacy_only_pair_records": 7,
                   "difference_set_sha256": policy["expected_historical_a5"]["difference_set_sha256"]},
                   "historical A.5 reproduction")
    expected_source = policy["expected_source_derived"]
    require_subset(source_derived["reference_transform_ports"], {
        "parity_instances": expected_source["reference_transform_port_parity_instances"],
        "difference_instances": expected_source["reference_transform_port_difference_instances"],
        "frozen_a3_body_parity_instances": expected_source["transform_body_parity_instances"],
        "frozen_a3_body_difference_instances": expected_source["transform_body_difference_instances"],
        "difference_set_sha256": expected_source["transform_difference_set_sha256"]},
        "source-derived transform")
    require_subset(source_derived["newline"], expected_source["newline"], "newline profile")
    expected_actual = expected_source["a3_actual_vs_reference"]
    require_subset(source_derived["a3_actual_vs_reference"], {
        "parity_instances": expected_actual["parity_instances"], "difference_instances": expected_actual["difference_instances"],
        "left_pair_records": expected_actual["a3_pair_records"], "right_pair_records": expected_actual["legacy_pair_records"],
        "shared_pair_records": expected_actual["shared_pair_records"], "left_only_pair_records": expected_actual["a3_only_pair_records"],
        "right_only_pair_records": expected_actual["legacy_only_pair_records"], "difference_set_sha256": expected_source["transform_difference_set_sha256"]},
        "A.3 actual/reference comparison")
    expected_filter = expected_source["correct_plain_a3_filter_vs_legacy"]
    require_subset(source_derived["correct_plain_a3_filter_vs_legacy"], {
        "parity_instances": expected_filter["parity_instances"], "difference_instances": expected_filter["difference_instances"],
        "left_pair_records": expected_filter["a3_pair_records"], "right_pair_records": expected_filter["legacy_pair_records"],
        "shared_pair_records": expected_filter["shared_pair_records"], "left_only_pair_records": expected_filter["a3_only_pair_records"],
        "right_only_pair_records": expected_filter["legacy_only_pair_records"], "difference_set_sha256": expected_filter["difference_set_sha256"]},
        "correct-plaintext filter comparison")
    require_subset(source_derived["reference_pair_ports"], expected_source["reference_pair_port"],
                   "reference pair ports")
    for name, expected in policy["expected_ecf_candidate_projections"].items():
        require_subset(ecf_projections[name], expected, f"{name} ECF candidate projection")
    require(global_projections == policy["expected_global_candidate_projections"],
            "global candidate projections drifted")
    details.sort(key=lambda item: item["instance_id"])
    return {"historical": historical_report, "source_derived": source_derived,
            "ecf_projections": ecf_projections, "global_projections": global_projections}, details


def markdown(report: dict[str, Any]) -> bytes:
    source = report["source_derived"]
    actual = source["a3_actual_vs_reference"]
    filtered = source["correct_plain_a3_filter_vs_legacy"]
    text = f"""# P2-20A.10 ECF parser-parity diagnostic\n\nResult: **BLOCKED** / diagnostic execution: **PASS**.\n\n- Frozen P2-20A.5 history: 61/64 parity, 3 differences, and a net legacy-minus-A.3 pair-count delta of 4.\n- Frozen A.3 output versus source-derived legacy reference: {actual['parity_instances']}/64 parity and {actual['difference_instances']} differences.\n- Correct plaintext, A.3 filter versus legacy pair parser: {filtered['parity_instances']}/64 parity and {filtered['right_only_pair_records']} legacy pair records absent from A.3.\n- Both independent reference transform and pair-parser ports agree on all 64 instances; this is source-derived diagnostic parity only.\n- Legacy runtime executed: no. Runtime binary parity claimed: no. A.3 outputs modified: no.\n- Candidate projections are non-mutating and grant zero selections, roots, adapters, consumer contracts, semantic imports, or terminal states.\n\nG2 remains 7/9 and BLOCKED; G2-06 is unsatisfied and P3 remains unauthorized.\n"""
    return text.encode("utf-8")


def generate(args: argparse.Namespace) -> dict[str, Any]:
    root, legacy_root = Path(args.root).resolve(), Path(args.legacy_source_root).resolve()
    paths = {role: resolve_inside(root, relative, role) for role, relative in INPUTS.items()}
    docs = {role: load_json(paths[role], role) for role in
            ("auxiliary_inventory", "a3_report", "a3_evidence", "a5_report", "a5_evidence",
             "a9_report", "a9_evidence", "asset_inventory", "reference_closure", "policy")}
    policy = docs["policy"]
    require(policy.get("evidence_revision") == REVISION and
            policy.get("required_input_roles") == [*INPUTS, *IGNORED_ROLES] and
            policy.get("required_ignored_artifact_roles") == list(IGNORED_ROLES),
            "P2-20A.10 policy role boundary drifted")
    require(all(value is False for value in policy["authority_rules"].values()) and
            policy["candidate_projection_controls"] == {
                "candidate_only": True, "frozen_indexes_only": True, "selection_count": 0,
                "approved_roots": 0, "approved_consumer_contracts": 0,
                "approved_semantic_adapters": 0, "approved_no_reference_instances": 0,
                "terminal_instances": 0, "semantic_imports_claimed": 0},
            "P2-20A.10 authority boundary drifted")
    validate_upstream(root, docs, policy)
    a3_binding, scopes = load_a3_scopes(root, docs["a3_evidence"])
    asset_binding = ignored_binding(root, "asset_catalog", docs["asset_inventory"]["catalog"])
    graph_binding = ignored_binding(root, "reference_graph", docs["reference_closure"]["graph"])
    result, details = scan(root, docs, policy, scopes)
    legacy_sources = bind_legacy_sources(legacy_root, policy["legacy_source_bindings"])
    entries = [{"role": role, "sha256": sha256_file(path)} for role, path in paths.items()]
    ignored = [a3_binding, asset_binding, graph_binding]
    aggregate = ordered_string_hash([f"{item['role']}:{item['sha256']}"
                                     for item in [*entries, *ignored, *legacy_sources]])
    detail_bytes = b"".join(json_bytes(item, compact=True) for item in details)
    detail_path = Path(args.detail_output)
    write_output(detail_path, detail_bytes)
    detail_binding = {"tracked": False, "path": DETAIL_RELATIVE, "lines": len(details),
                      "bytes": len(detail_bytes), "sha256": sha256_bytes(detail_bytes)}
    report = {
        "schema_version": 1, "evidence_revision": REVISION,
        "captured_utc": docs["a9_report"]["captured_utc"], "task_id": "P2-20A",
        "criterion_id": "G2-06", "source_build": "qy-3.0.0.413", "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "input_bindings": {"aggregate_sha256": aggregate, "entries": entries,
                           "ignored_artifacts": ignored, "legacy_sources": legacy_sources},
        "historical_a5": result["historical"], "source_derived": result["source_derived"],
        "candidate_projections": {"scope": "CANDIDATE_ONLY_NON_MUTATING_PROJECTION",
                                  "ecf": result["ecf_projections"],
                                  "global": result["global_projections"],
                                  "controls": policy["candidate_projection_controls"]},
        "runtime_boundaries": {"legacy_runtime_executed": False,
            "runtime_binary_parity_claimed": False, "a3_outputs_modified": False,
            "valid_semantic_assignments_claimed": False, "consumer_contract_approved": False,
            "semantic_adapter_approved": False, "no_reference_approved": False,
            "root_approved": False, "terminal_state_approved": False},
        "blockers": policy["blockers"], "negative_contracts": policy["negative_contracts"],
        "detail_export": detail_binding, "g2_projection": policy["g2_projection"],
        "contracts": {"policy_sha256": sha256_file(paths["policy"]),
                      "schema_sha256": sha256_file(paths["schema"]),
                      "detail_schema_sha256": sha256_file(paths["detail_schema"])},
        "disclosure": policy["disclosure"],
    }
    report_bytes = json_bytes(report)
    markdown_bytes = markdown(report)
    write_output(Path(args.json_output), report_bytes)
    write_output(Path(args.markdown_output), markdown_bytes)
    self_test = run_self_test()
    evidence = {
        "schema_version": 1, "evidence_revision": REVISION, "captured_utc": report["captured_utc"],
        "task_id": "P2-20A", "criterion_id": "G2-06", "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "report_json": {"bytes": len(report_bytes), "sha256": sha256_bytes(report_bytes)},
        "report_markdown": {"bytes": len(markdown_bytes), "sha256": sha256_bytes(markdown_bytes)},
        "detail_export": detail_binding, "historical_a5": result["historical"],
        "source_derived": result["source_derived"],
        "candidate_projections": {"scope": "CANDIDATE_ONLY_NON_MUTATING_PROJECTION",
                                  "ecf": result["ecf_projections"],
                                  "global": result["global_projections"],
                                  "controls": policy["candidate_projection_controls"]},
        "runtime_boundaries": report["runtime_boundaries"], "blockers": policy["blockers"],
        "contracts": report["contracts"],
        "implementation": {"generator_sha256": sha256_file(Path(__file__)),
                           "support_sha256": sha256_file(Path(__file__).with_name(
                               "aux_ecf_parser_parity_support.py")),
                           "self_test_assertions": self_test["assertions"]},
        "isolation": {"network": "none", "repository_mount": "read-only",
                      "legacy_source_mount": "read-only", "builder_user": "tmxy",
                      "capabilities": "none", "no_new_privileges": True},
        "disclosure": policy["disclosure"],
    }
    write_output(Path(args.evidence_output), json_bytes(evidence))
    return {"result": "BLOCKED", "review_execution_result": "PASS",
            "a3_actual_parity_instances": 51, "a3_actual_difference_instances": 13,
            "correct_plain_filter_parity_instances": 63,
            "legacy_pair_records_absent_from_a3": 4,
            "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--legacy-source-root", required=True)
    parser.add_argument("--detail-output", required=True)
    parser.add_argument("--json-output", required=True)
    parser.add_argument("--markdown-output", required=True)
    parser.add_argument("--evidence-output", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    try:
        print(json.dumps(generate(parse_args()), sort_keys=True))
    except (EvidenceError, OSError, ValueError, KeyError, TypeError, UnicodeError,
            json.JSONDecodeError) as error:
        print(json.dumps({"result": "ERROR", "error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
