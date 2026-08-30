"""Fail-closed P2-20A.13 QTX declared-mip payload-prefix binding for G2."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Callable
REVISION = "P2-20A.13"
REPORT_PATH = "Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json"
MARKDOWN_PATH = "Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.md"
INVENTORY_PATH = "Data/Inventory/p2-20a-qtx-declared-mip-payload-prefix.json"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix.jsonl"
PLAN_PATH = "Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv"
POLICY_PATH = "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json"
SCHEMA_PATH = "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-v1.schema.json"
DETAIL_SCHEMA_PATH = "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json"
BASE_PLAN_CONTRACT = "Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv"
INPUT_PATHS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True), ("a4_inventory", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a7_report", "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True), ("a7_inventory", "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
    ("a7_detail", "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False),
    ("a8_report", "Data/Reports/p2-20a-asset-binding-recovery-report.json", True), ("a8_inventory", "Data/Inventory/p2-20a-asset-binding-recovery.json", True),
    ("a8_detail", "Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl", False),
    ("core_report", "Data/Reports/p2-20a-core-resource-closure-report.json", True), ("core_inventory", "Data/Inventory/p2-20a-core-resource-closure.json", True),
    ("core_detail", "Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl", False),
    ("base_plan_contract", BASE_PLAN_CONTRACT, True), ("p2_03_inventory", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False), ("p2_12_inventory", "Data/Inventory/p2-12-full-asset-inventory.json", True),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False), ("policy", POLICY_PATH, True),
    ("schema", SCHEMA_PATH, True), ("detail_schema", DETAIL_SCHEMA_PATH, True),
]
PRODUCTION_PATHS = [
    ("texture_types_header", "Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp", True), ("qtx_reader_header", "Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp", True),
    ("qtx_reader_implementation", "Tools/TMXY.Texture/src/qtx_reader.cpp", True), ("texture_decode_internal_header", "Tools/TMXY.Texture/src/texture_decode_internal.hpp", True),
    ("texture_decode_implementation", "Tools/TMXY.Texture/src/texture_decode.cpp", True), ("dds_writer_implementation", "Tools/TMXY.Texture/src/dds_writer.cpp", True),
    ("texture_export_implementation", "Tools/TMXY.Texture/src/texture_export.cpp", True),
    ("texture_error_implementation", "Tools/TMXY.Texture/src/texture_error.cpp", True),
]
IMPLEMENTATION_PATHS = [
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/CMakeLists.txt", "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/README.md",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/New-G2QtxDeclaredMipPayloadPrefix.ps1",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/g2_qtx_declared_mip_payload_prefix.py", "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/qtx_declared_mip_prefix_common.py",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/apps/qtx_declared_mip_prefix_probe_main.cpp",
    POLICY_PATH, SCHEMA_PATH, DETAIL_SCHEMA_PATH,
    "Docs/Formats/G2-QTX-DECLARED-MIP-PAYLOAD-PREFIX.md",
    "Tests/Contract/Test-G2QtxDeclaredMipPayloadPrefix.ps1",
    "Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.cpp", "Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.hpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.cpp", "Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.hpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.cpp", "Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.hpp",
    "Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.cpp", "Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.hpp",
]
DETAIL_FIELDS = {"asset_id", "family", "candidate_count", "candidate_set_sha256",
                 "recovery_kind", "basis", "source_strict_resolution",
                 "a13_resolution_change", "candidate_selected", "automatic_resolution",
                 "authority_state_changed", "candidate"}
DETAIL_CANDIDATE_FIELDS = {"candidate_id", "package_sha256", "body_sha256",
    "descriptor_semantic_sha256", "strict_semantic_sha256", "prefix_semantic_sha256",
    "input_payload_sha256", "consumed_payload_sha256", "ignored_tail_sha256",
    "decoded_mip_zero_sha256", "dds_sha256", "dds_payload_sha256", "strict_binding",
    "strict_error_code", "strict_prefix_binding", "explicit_prefix_binding", "format", "width",
    "height", "stored_mip_count", "declared_mip_count", "effective_mip_count",
    "payload_boundary_mip_count", "maximum_natural_mip_count", "input_payload_bytes",
    "consumed_payload_bytes", "ignored_payload_bytes", "decoded_mip_zero_bytes",
    "dds_header_bytes", "dds_payload_bytes", "dds_bytes", "dds_declared_mip_count",
    "dds_payload_prefix_only", "ignored_tail_excluded_from_dds", "payload_extent_basis",
    "recovery_applied", "adapter_applied", "content_disposition"}
def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)

def _text_sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def _is_sha256(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _expected_entry(root: Path, role: str, relative: str, tracked: bool,
                    resolve_inside: Callable[[Path, str], Path],
                    sha256: Callable[[Path], str]) -> dict[str, Any]:
    path = resolve_inside(root, relative)
    return {"role": role, "path": relative, "tracked": tracked,
            "bytes": path.stat().st_size, "lines": _line_count(path), "sha256": sha256(path)}


def _aggregate(entries: list[dict[str, Any]]) -> str:
    text = "".join(f"{x['role']}\t{x['path']}\t{str(x['tracked']).lower()}\t"
                   f"{x['bytes']}\t{x['lines']}\t{x['sha256']}\n" for x in entries)
    return _text_sha256(text)


def _jsonl(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig") as stream:
        values = [json.loads(line) for line in stream]
    if not all(isinstance(value, dict) for value in values):
        raise ValueError(f"JSONL root is not an object: {path}")
    return values


def _output_binding(path: Path, relative: str, tracked: bool,
                    sha256: Callable[[Path], str]) -> dict[str, Any]:
    return {"path": relative, "tracked": tracked, "bytes": path.stat().st_size,
            "lines": _line_count(path), "sha256": sha256(path)}


def _validate_detail(root: Path, report: dict[str, Any], policy: dict[str, Any],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> list[dict[str, Any]]:
    path = resolve_inside(root, DETAIL_PATH)
    require(report.get("detail_export") == _output_binding(path, DETAIL_PATH, False, sha256),
            "P2-20A.13 detail export is not exactly hash-bound")
    rows = _jsonl(path)
    expected = {item["asset_id"]: item for item in policy["selected_targets"]}
    require(len(rows) == 6 and {row.get("asset_id") for row in rows} == set(expected),
            "P2-20A.13 detail target set drifted")
    patterns: dict[str, tuple[Any, ...]] = {
        "dxt1": (512, 512, 10, 10, 174776, 131072, 43704, 1048576, 131200),
        "dxt5": (256, 256, 7, 9, 87376, 65536, 21840, 262144, 65664),
    }
    for row in rows:
        require(set(row) == DETAIL_FIELDS and row["family"] == "qtx" and
                row["candidate_count"] == 1 and
                row["recovery_kind"] == "qtx_declared_mip_payload_prefix" and
                row["basis"] == "declared_mip_payload_prefix_contract" and
                row["source_strict_resolution"] == "UNRESOLVED" and
                row["a13_resolution_change"] is False and
                row["candidate_selected"] is False and
                row["automatic_resolution"] is False and
                row["authority_state_changed"] is False,
                "P2-20A.13 detail authority boundary drifted")
        candidate, selected = row["candidate"], expected[row["asset_id"]]
        require(isinstance(candidate, dict) and set(candidate) == DETAIL_CANDIDATE_FIELDS and
                all(_is_sha256(candidate[key]) for key in DETAIL_CANDIDATE_FIELDS
                    if key.endswith("_sha256")) and
                candidate["candidate_id"] == selected["candidate_id"] and
                candidate["body_sha256"] == selected["body_sha256"] and
                candidate["descriptor_semantic_sha256"] == selected["descriptor_semantic_sha256"] and
                row["candidate_set_sha256"] == _text_sha256(candidate["candidate_id"] + "\n") and
                candidate["strict_binding"] == "REJECTED" and
                candidate["strict_error_code"] == "payload_size_mismatch" and
                candidate["strict_prefix_binding"] == "PASS" and
                candidate["explicit_prefix_binding"] == "PASS" and
                candidate["stored_mip_count"] == candidate["declared_mip_count"] ==
                candidate["effective_mip_count"] == 1 and
                candidate["input_payload_bytes"] == candidate["consumed_payload_bytes"] +
                candidate["ignored_payload_bytes"] and candidate["dds_header_bytes"] == 128 and
                candidate["dds_payload_bytes"] == candidate["consumed_payload_bytes"] and
                candidate["dds_bytes"] == 128 + candidate["dds_payload_bytes"] and
                candidate["dds_payload_sha256"] == candidate["consumed_payload_sha256"] and
                candidate["dds_declared_mip_count"] == 1 and
                candidate["dds_payload_prefix_only"] is True and
                candidate["ignored_tail_excluded_from_dds"] is True and
                candidate["payload_extent_basis"] == "declared_mip_payload_prefix_contract" and
                candidate["recovery_applied"] is False and candidate["adapter_applied"] is False and
                candidate["content_disposition"] == "NONE",
                "P2-20A.13 detail candidate relation drifted")
        observed = (candidate["width"], candidate["height"],
                    candidate["payload_boundary_mip_count"], candidate["maximum_natural_mip_count"],
                    candidate["input_payload_bytes"], candidate["consumed_payload_bytes"],
                    candidate["ignored_payload_bytes"], candidate["decoded_mip_zero_bytes"],
                    candidate["dds_bytes"])
        require(candidate["format"] in patterns and observed == patterns[candidate["format"]],
                "P2-20A.13 detail extent pattern drifted")
    return rows


def _validate_plan(root: Path, report: dict[str, Any], policy: dict[str, Any],
                   resolve_inside: Callable[[Path, str], Path],
                   sha256: Callable[[Path], str], require: Callable[[bool, str], None]) -> None:
    path = resolve_inside(root, PLAN_PATH)
    require(report.get("effective_recovery_plan") == _output_binding(path, PLAN_PATH, False, sha256),
            "P2-20A.13 effective recovery plan is not exactly hash-bound")
    base_path = resolve_inside(root, BASE_PLAN_CONTRACT)
    base = [line.split("\t") for line in base_path.read_text(encoding="utf-8").splitlines()]
    effective = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()]
    selected = {(item["asset_id"], item["candidate_id"]) for item in policy["selected_targets"]}
    require(len(base) == len(effective) == 21 and all(len(row) == 7 for row in base + effective),
            "P2-20A.13 plan row shape drifted")
    changed = 0
    for before, after in zip(base, effective):
        if (before[0], before[1]) in selected:
            require(before[:5] + before[6:] == after[:5] + after[6:] and
                    before[5] == "qtx_complete_mip_chain" and
                    after[5] == "qtx_declared_mip_payload_prefix",
                    "P2-20A.13 selected plan mutation drifted")
            changed += 1
        else:
            require(before == after, "P2-20A.13 excluded plan row changed")
    require(changed == 6, "P2-20A.13 plan changed-row count drifted")


def _validate_current_chain(root: Path, report: dict[str, Any], policy: dict[str, Any],
                            load_json: Callable[[Path], dict[str, Any]],
                            resolve_inside: Callable[[Path, str], Path],
                            require: Callable[[bool, str], None]) -> None:
    a4 = load_json(resolve_inside(root, INPUT_PATHS[0][1]))
    a7 = load_json(resolve_inside(root, INPUT_PATHS[3][1]))
    a8 = load_json(resolve_inside(root, INPUT_PATHS[6][1]))
    core = load_json(resolve_inside(root, INPUT_PATHS[9][1]))
    blockers = report["preserved_blockers"]
    require(blockers == a7["preserved_blockers"], "P2-20A.13 blockers differ from final A.7")
    common = set(a8["preserved_blockers"])
    require({key: blockers[key] for key in common} == a8["preserved_blockers"],
            "P2-20A.13 blockers differ from final A.8")
    asset = core["closure"]["asset_binding"]
    full = a4["measured"]["reconciled_full_workset"]
    effective = a7["measured"]["effective"]
    recovery = a8["measured"]["effective_resolution"]
    require((blockers["asset_effective_ambiguous_targets"],
             blockers["asset_effective_ambiguous_edges"],
             blockers["asset_effective_unresolved_targets"],
             blockers["asset_effective_unresolved_edges"]) ==
            (asset["ambiguous_targets"], asset["ambiguous_edges"],
             asset["unresolved_targets"], asset["unresolved_edges"]) ==
            (full["ambiguous_targets"], full["ambiguous_edges"],
             full["unresolved_targets"], full["unresolved_edges"]) and
            recovery["resolved"] == {"targets": effective["resolved_targets"],
                                      "candidate_edges": effective["resolved_edges"]} and
            recovery["unresolved"] == {"targets": effective["unresolved_targets"],
                                        "candidate_edges": effective["unresolved_edges"]},
            "P2-20A.13 final A.4/A.7/A.8/Core effective counts disagree")
    selected = {item["asset_id"] for item in policy["selected_targets"]}
    a7_rows = {row["asset_id"]: row for row in _jsonl(resolve_inside(root, INPUT_PATHS[5][1]))
               if row.get("asset_id") in selected}
    a8_rows = {row["asset_id"]: row for row in _jsonl(resolve_inside(root, INPUT_PATHS[8][1]))
               if row.get("asset_id") in selected}
    require(set(a7_rows) == set(a8_rows) == selected, "P2-20A.13 upstream selected set drifted")
    post = all(a7_rows[key]["effective_resolution"] == "RESOLVED" and
               a8_rows[key]["successful_edges"] == 1 and
               a8_rows[key]["effective_resolution"] == "RESOLVED" and
               a8_rows[key]["candidates"][0]["recovery_kind"] ==
               "qtx_declared_mip_payload_prefix" and
               a8_rows[key]["candidates"][0]["recovery_applied"] is True for key in selected)
    require(post and report["scope"]["current_upstream_effective_state"] == {
                "phase": "POST_APPLICATION", "selected_targets_resolved": 6,
                "selected_edges_pass": 6, "selected_recovery_applied_edges": 6},
            "P2-20A.13 tracked evidence is not the exact post-application state")


def _validate_report(root: Path, report: dict[str, Any],
                     load_json: Callable[[Path], dict[str, Any]],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str], require: Callable[[bool, str], None]) -> None:
    policy = load_json(resolve_inside(root, POLICY_PATH))
    base_contract = resolve_inside(root, BASE_PLAN_CONTRACT)
    require(policy.get("base_plan_contract") == {"path": BASE_PLAN_CONTRACT, "tracked": True,
        "rows": 21, "bytes": 6504, "sha256": sha256(base_contract)}, "P2-20A.13 base-plan contract policy drifted")
    require(set(report) == {"schema_version", "evidence_revision", "captured_utc", "task_id", "criterion_id", "result", "review_execution_result", "task_status", "completion_criteria_satisfied", "diagnostic_scope_complete", "remediation_scope_complete", "g2_06_satisfied", "p3_authorized", "proof_classification", "input_bindings", "detail_export", "effective_recovery_plan", "legacy_source_provenance", "source_facts", "production_contract", "scope", "measured", "observed_relation", "authority_boundary", "preserved_blockers", "contracts", "disclosure"}, "P2-20A.13 report is not closed")
    require(report.get("schema_version") == 1 and report.get("evidence_revision") == REVISION and
            report.get("task_id") == "P2-20A" and report.get("criterion_id") == "G2-06" and
            report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS_DIAGNOSTIC" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            report.get("diagnostic_scope_complete") is True and
            report.get("remediation_scope_complete") is False and
            report.get("g2_06_satisfied") is False and report.get("p3_authorized") is False and
            report.get("proof_classification") == {"source_basis": "SOURCE_DERIVED",
                "legacy_binary_executed": False, "runtime_parity_proven": False},
            "P2-20A.13 diagnostic was falsely promoted")
    inputs = [_expected_entry(root, *item, resolve_inside, sha256) for item in INPUT_PATHS]
    require(report.get("input_bindings") == {"aggregate_sha256": _aggregate(inputs),
                                              "entries": inputs},
            "P2-20A.13 input chain is not exactly hash-bound")
    _validate_detail(root, report, policy, resolve_inside, sha256, require)
    _validate_plan(root, report, policy, resolve_inside, sha256, require)
    scope = report.get("scope", {})
    require(set(scope) == {"source_revision", "family", "targets", "candidate_edges", "unique_candidates", "candidate_ids_distinct", "candidate_set_exact", "excluded_unresolved_targets", "excluded_unresolved_edges", "excluded_scope_selected", "current_upstream_effective_state"}, "P2-20A.13 scope is not closed")
    require({key: scope.get(key) for key in ("source_revision", "family", "targets",
            "candidate_edges", "unique_candidates", "candidate_ids_distinct",
            "candidate_set_exact", "excluded_unresolved_targets", "excluded_unresolved_edges",
            "excluded_scope_selected")} == {"source_revision": "P2-20A.7", "family": "qtx",
            "targets": 6, "candidate_edges": 6, "unique_candidates": 6,
            "candidate_ids_distinct": True, "candidate_set_exact": True,
            "excluded_unresolved_targets": 4, "excluded_unresolved_edges": 6,
            "excluded_scope_selected": False}, "P2-20A.13 scope drifted")
    measured = report.get("measured", {})
    require(measured == {
        "source_assets_reverified": 6, "candidate_packages_hashed": 6,
        "candidate_bodies_reverified": 6, "strict_default_rejected_edges": 6,
        "payload_size_mismatch_edges": 6, "strict_prefix_pass_edges": 6,
        "explicit_prefix_pass_edges": 6, "full_payload_boundary_edges": 6,
        "decoded_mip_zero_match_edges": 6, "dds_prefix_only_edges": 6,
        "ignored_tail_hashes": 6, "dxt1_targets": 3, "dxt5_targets": 3,
        "input_payload_bytes": 786456, "consumed_payload_bytes": 589824,
        "ignored_payload_bytes": 196632, "base_recovery_plan_rows": 21,
        "effective_recovery_plan_rows": 21, "effective_plan_changed_rows": 6,
        "effective_plan_unchanged_rows": 15, "candidate_selections": 0,
        "automatic_resolutions": 0, "owner_dispositions": 0,
        "content_dispositions": 0}, "P2-20A.13 measurements drifted")
    require(report.get("observed_relation") == {
        "recovery_kind": "qtx_declared_mip_payload_prefix", "basis": "declared_mip_payload_prefix_contract",
        "default_strict_binding": "REJECTED", "default_strict_error_code": "payload_size_mismatch",
        "explicit_api_binding": "PASS", "stored_mip_count": 1, "declared_mip_count": 1,
        "full_payload_boundary_exact_edges": 6, "consumed_plus_ignored_equals_input_edges": 6,
        "decoded_mip_zero_matches_strict_prefix_edges": 6, "dds_payload_prefix_only_edges": 6,
        "ignored_tail_excluded_from_dds_edges": 6, "ignored_tail_sha256_edges": 6,
        "dxt1_512_boundary_10_max_10_targets": 3, "dxt5_256_boundary_7_max_9_targets": 3,
        "base_plan_recovery_kind": "qtx_complete_mip_chain",
        "effective_plan_recovery_kind": "qtx_declared_mip_payload_prefix",
        "effective_plan_row_set_preserved": True, "effective_plan_only_recovery_kind_changed": True},
        "P2-20A.13 observed relation drifted")
    authority = report.get("authority_boundary", {})
    require(authority == {"a4_is_authoritative": True, "authority_state_changed": False,
            "adapter_applied": False, "recovery_applied": False,
            "machine_can_select_candidate": False, "machine_can_approve_disposition": False,
            "repair_or_write": False, "delete_or_no_ref": False, "owner_approvals": 0,
            "verified_resolutions": 0}, "P2-20A.13 authority boundary drifted")
    production = [_expected_entry(root, *item, resolve_inside, sha256) for item in PRODUCTION_PATHS]
    require(report.get("production_contract") == {
                "api": "tmxy::texture::QtxReader::parse_with_declared_mip_payload_prefix",
                "default_api_remains_strict": True,
                "implementation_bindings": {"aggregate_sha256": _aggregate(production),
                                             "entries": production}},
            "P2-20A.13 production API is not exactly hash-bound")
    legacy_roles = sorted(policy["legacy_source_roles"], key=lambda item: item["role"])
    legacy_text = "".join(f"{item['role']}\t{item['sha256']}\n" for item in legacy_roles)
    require(report.get("legacy_source_provenance") == {
                "aggregate_sha256": _text_sha256(legacy_text), "roles": legacy_roles} and
            report.get("source_facts") == policy["expected_source_facts"] and
            report.get("contracts") == {
                "policy_sha256": sha256(resolve_inside(root, POLICY_PATH)),
                "schema_sha256": sha256(resolve_inside(root, SCHEMA_PATH)),
                "detail_schema_sha256": sha256(resolve_inside(root, DETAIL_SCHEMA_PATH)),
                "base_plan_contract_sha256":
                    sha256(resolve_inside(root, BASE_PLAN_CONTRACT))} and
            report.get("disclosure") == policy["disclosure"],
            "P2-20A.13 source, contract, or disclosure binding drifted")
    _validate_current_chain(root, report, policy, load_json, resolve_inside, require)


def _validate_inventory(root: Path, inventory: dict[str, Any], report: dict[str, Any],
                        report_path: Path, resolve_inside: Callable[[Path, str], Path],
                        sha256: Callable[[Path], str], require: Callable[[bool, str], None]) -> None:
    require(set(inventory) == {"schema_version", "evidence_revision", "captured_utc", "result", "review_execution_result", "task_status", "g2_06_satisfied", "p3_authorized", "measured", "report", "report_markdown", "outputs", "contracts", "implementation", "builder", "isolation", "proof_classification", "authority_boundary", "preserved_blockers", "disclosure"}, "P2-20A.13 inventory is not closed")
    require(inventory.get("schema_version") == 1 and inventory.get("captured_utc") == report["captured_utc"] and
            inventory.get("evidence_revision") == REVISION and
            inventory.get("result") == "BLOCKED" and
            inventory.get("review_execution_result") == "PASS_DIAGNOSTIC" and
            inventory.get("task_status") == "BLOCKED" and
            inventory.get("g2_06_satisfied") is False and inventory.get("p3_authorized") is False,
            "P2-20A.13 inventory was falsely promoted")
    markdown = resolve_inside(root, MARKDOWN_PATH)
    detail = resolve_inside(root, DETAIL_PATH)
    plan = resolve_inside(root, PLAN_PATH)
    require(inventory.get("report") == _output_binding(report_path, REPORT_PATH, True, sha256) and
            inventory.get("report_markdown") == _output_binding(markdown, MARKDOWN_PATH, True, sha256) and
            inventory.get("outputs") == {
                "detail_export": _output_binding(detail, DETAIL_PATH, False, sha256),
                "effective_recovery_plan": _output_binding(plan, PLAN_PATH, False, sha256)} and
            inventory.get("measured") == report["measured"] and
            inventory.get("contracts") == report["contracts"] and
            inventory.get("proof_classification") == report["proof_classification"] and
            inventory.get("authority_boundary") == report["authority_boundary"] and
            inventory.get("preserved_blockers") == report["preserved_blockers"] and
            inventory.get("disclosure") == report["disclosure"],
            "P2-20A.13 inventory output or authority chain drifted")
    implementation = [_expected_entry(root, f"implementation_{index:02d}", relative, True,
                                      resolve_inside, sha256)
                      for index, relative in enumerate(IMPLEMENTATION_PATHS, 1)]
    require(inventory.get("implementation") == {"files": implementation,
                "aggregate_sha256": _aggregate(implementation),
                "generator_self_test_assertions": 23, "probe_startup_self_tests": True} and
            inventory.get("isolation") == {"network": "none", "read_only_container": True,
                "cap_drop": "ALL", "no_new_privileges": True,
                "repository_mount": "read-only", "legacy_asset_mount": "read-only",
                "legacy_source_mounts": "read-only-files"} and
            set(inventory.get("builder", {})) == {"image_reference", "image_id", "user"} and
            all(inventory["builder"].get(key) for key in ("image_reference", "image_id")) and inventory["builder"].get("user") == "tmxy",
            "P2-20A.13 implementation or isolation evidence drifted")


def qtx_declared_mip_prefix_safe(report: dict[str, Any]) -> bool:
    measured, authority = report["measured"], report["authority_boundary"]
    proof, state = report["proof_classification"], report["scope"]["current_upstream_effective_state"]
    return (proof == {"source_basis": "SOURCE_DERIVED", "legacy_binary_executed": False,
                      "runtime_parity_proven": False} and
            measured["strict_default_rejected_edges"] == 6 and
            measured["explicit_prefix_pass_edges"] == 6 and
            measured["dds_prefix_only_edges"] == 6 and measured["ignored_tail_hashes"] == 6 and
            measured["candidate_selections"] == measured["automatic_resolutions"] == 0 and
            authority["authority_state_changed"] is False and authority["adapter_applied"] is False and
            authority["recovery_applied"] is False and
            state == {"phase": "POST_APPLICATION", "selected_targets_resolved": 6,
                      "selected_edges_pass": 6,
                      "selected_recovery_applied_edges": 6})


def qtx_declared_mip_prefix_metrics(report: dict[str, Any]) -> list[tuple[str, Any, str]]:
    scope, measured = report["scope"], report["measured"]
    proof, authority = report["proof_classification"], report["authority_boundary"]
    blockers, state = report["preserved_blockers"], scope["current_upstream_effective_state"]
    values = [
        ("diagnostic_hash_bound", True, "boolean"), ("inventory_hash_bound", True, "boolean"),
        ("detail_hash_bound", True, "boolean"), ("effective_plan_hash_bound", True, "boolean"),
        ("production_contract_hash_bound", True, "boolean"),
        ("source_derived_contract_proven", True, "boolean"),
        ("runtime_parity_proven", proof["runtime_parity_proven"], "boolean"),
        ("targets", scope["targets"], "assets"), ("candidate_edges", scope["candidate_edges"], "edges"),
        ("strict_default_rejected_edges", measured["strict_default_rejected_edges"], "edges"),
        ("explicit_prefix_pass_edges", measured["explicit_prefix_pass_edges"], "edges"),
        ("full_payload_boundary_edges", measured["full_payload_boundary_edges"], "edges"),
        ("dds_prefix_only_edges", measured["dds_prefix_only_edges"], "edges"),
        ("ignored_tail_hashes", measured["ignored_tail_hashes"], "hashes"),
        ("input_payload_bytes", measured["input_payload_bytes"], "bytes"),
        ("consumed_payload_bytes", measured["consumed_payload_bytes"], "bytes"),
        ("ignored_payload_bytes", measured["ignored_payload_bytes"], "bytes"),
        ("candidate_selections", measured["candidate_selections"], "assets"),
        ("automatic_resolutions", measured["automatic_resolutions"], "assets"),
        ("authority_state_changed", authority["authority_state_changed"], "boolean"),
        ("recovery_applied", authority["recovery_applied"], "boolean"),
        ("upstream_phase", state["phase"], "state"),
        ("upstream_selected_targets_resolved", state["selected_targets_resolved"], "assets"),
        ("upstream_selected_edges_pass", state["selected_edges_pass"], "edges"),
        ("preserved_ambiguous_targets", blockers["asset_effective_ambiguous_targets"], "assets"),
        ("preserved_ambiguous_edges", blockers["asset_effective_ambiguous_edges"], "edges"),
        ("preserved_unresolved_targets", blockers["asset_effective_unresolved_targets"], "assets"),
        ("preserved_unresolved_edges", blockers["asset_effective_unresolved_edges"], "edges"),
    ]
    return [(f"qtx_declared_mip_prefix_{name}", value, unit) for name, value, unit in values]


def qtx_declared_mip_prefix_blocker_text(
        report: dict[str, Any], asset_binding: dict[str, Any]) -> str:
    scope, state = report["scope"], report["scope"]["current_upstream_effective_state"]
    return (f"A.13 source-derives an explicit declared-mip payload-prefix PASS for "
            f"{scope['targets']} QTX targets / {scope['candidate_edges']} unique edges while default "
            "strict parsing rejects all six; ignored tail bytes are hash-recorded and excluded from "
            "effective mips and DDS output. A.13 itself selects no candidate and changes no authority "
            f"state. Its upstream phase is {state['phase']}; current A.4/A.7/A.8/Core authority retains "
            f"{asset_binding['ambiguous_targets']} targets / {asset_binding['ambiguous_edges']} edges "
            f"ambiguous and {asset_binding['unresolved_targets']} targets / "
            f"{asset_binding['unresolved_edges']} edges unresolved.")


def bind_qtx_declared_mip_payload_prefix(
    root: Path, policy: dict[str, Any], load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path], sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["qtx_declared_mip_payload_prefix"]
    require(spec == {"task_id": "P2-20A", "criterion_id": "G2-06",
                     "evidence_revision": REVISION, "path": REPORT_PATH},
            "P2-20A.13 G2 policy binding drifted")
    report_path, inventory_path = resolve_inside(root, REPORT_PATH), resolve_inside(root, INVENTORY_PATH)
    report, inventory = load_json(report_path), load_json(inventory_path)
    _validate_report(root, report, load_json, resolve_inside, sha256, require)
    _validate_inventory(root, inventory, report, report_path, resolve_inside, sha256, require)
    digests = {"report": sha256(report_path), "inventory": sha256(inventory_path),
               "detail": sha256(resolve_inside(root, DETAIL_PATH)),
               "plan": sha256(resolve_inside(root, PLAN_PATH))}
    binding = {"task_id": "P2-20A", "criterion_id": "G2-06", "evidence_revision": REVISION,
        "path": REPORT_PATH, "sha256": digests["report"],
        "inventory_path": INVENTORY_PATH, "inventory_sha256": digests["inventory"],
        "detail_path": DETAIL_PATH, "detail_sha256": digests["detail"],
        "effective_recovery_plan_path": PLAN_PATH,
        "effective_recovery_plan_sha256": digests["plan"],
        "result": report["result"], "review_execution_result": report["review_execution_result"],
        "task_status": report["task_status"],
        "completion_criteria_satisfied": report["completion_criteria_satisfied"],
        "diagnostic_scope_complete": report["diagnostic_scope_complete"],
        "remediation_scope_complete": report["remediation_scope_complete"],
        "g2_06_satisfied": report["g2_06_satisfied"], "p3_authorized": report["p3_authorized"]}
    aggregate = (f"QTX_DECLARED_MIP_PREFIX|P2-20A|G2-06|{REVISION}|{REPORT_PATH}|"
                 f"{digests['report']}|{INVENTORY_PATH}|{digests['inventory']}|{DETAIL_PATH}|"
                 f"{digests['detail']}|{PLAN_PATH}|{digests['plan']}")
    return binding, report, aggregate


def qtx_declared_mip_prefix_self_test() -> dict[str, Any]:
    current = {"proof_classification": {"source_basis": "SOURCE_DERIVED",
        "legacy_binary_executed": False, "runtime_parity_proven": False},
        "scope": {"current_upstream_effective_state": {"phase": "POST_APPLICATION",
            "selected_targets_resolved": 6, "selected_edges_pass": 6,
            "selected_recovery_applied_edges": 6}},
        "measured": {"strict_default_rejected_edges": 6, "explicit_prefix_pass_edges": 6,
            "dds_prefix_only_edges": 6, "ignored_tail_hashes": 6,
            "candidate_selections": 0, "automatic_resolutions": 0},
        "authority_boundary": {"authority_state_changed": False,
            "adapter_applied": False, "recovery_applied": False}}
    if not qtx_declared_mip_prefix_safe(current):
        raise ValueError("QTX declared-mip prefix source proof self-test failed")
    strict_forged = json.loads(json.dumps(current))
    strict_forged["measured"]["strict_default_rejected_edges"] = 5
    authority_forged = json.loads(json.dumps(current))
    authority_forged["authority_boundary"]["authority_state_changed"] = True
    pre_forged = json.loads(json.dumps(current))
    pre_forged["scope"]["current_upstream_effective_state"] = {
        "phase": "PRE_APPLICATION", "selected_targets_resolved": 0,
        "selected_edges_pass": 0, "selected_recovery_applied_edges": 0}
    if (qtx_declared_mip_prefix_safe(strict_forged) or
            qtx_declared_mip_prefix_safe(authority_forged) or
            qtx_declared_mip_prefix_safe(pre_forged)):
        raise ValueError("QTX declared-mip prefix false promotion was accepted")
    return {"result": "PASS", "assertions": 4, "source_derived_safe": True,
            "default_strict_promotion_rejected": True, "authority_promotion_rejected": True,
            "pre_application_rejected": True}
