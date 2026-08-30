"""P2-20A.12 static-mesh payload-section-prefix diagnostic binding for G2."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Callable


REVISION = "P2-20A.12"
REPORT_PATH = "Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json"
INVENTORY_PATH = "Data/Inventory/p2-20a-static-mesh-payload-section-prefix.json"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl"
POLICY_PATH = "Contracts/data-schema/g2-static-mesh-payload-section-prefix-policy-v1.json"
SCHEMA_PATH = "Contracts/data-schema/g2-static-mesh-payload-section-prefix-v1.schema.json"
DETAIL_SCHEMA_PATH = (
    "Contracts/data-schema/g2-static-mesh-payload-section-prefix-detail-v1.schema.json")
HEADER_PATH = "Tools/TMXY.StaticMesh/include/tmxy/static_mesh/package_static_mesh_reader.hpp"
IMPLEMENTATION_PATH = "Tools/TMXY.StaticMesh/src/package_static_mesh_reader.cpp"
PRODUCTION_PATHS = [
    ("static_mesh_types_header",
     "Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_types.hpp", True),
    ("static_mesh_api_header", HEADER_PATH, True),
    ("static_mesh_binding_implementation", IMPLEMENTATION_PATH, True),
    ("static_mesh_payload_parser", "Tools/TMXY.StaticMesh/src/sm_reader.cpp", True),
    ("static_mesh_error_source", "Tools/TMXY.StaticMesh/src/static_mesh_error.cpp", True),
]
INPUT_PATHS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_inventory", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a7_report", "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True),
    ("a7_inventory", "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
    ("a7_detail", "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False),
    ("a8_report", "Data/Reports/p2-20a-asset-binding-recovery-report.json", True),
    ("a8_inventory", "Data/Inventory/p2-20a-asset-binding-recovery.json", True),
    ("a8_detail", "Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl", False),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("policy", POLICY_PATH, True),
    ("schema", SCHEMA_PATH, True),
    ("detail_schema", DETAIL_SCHEMA_PATH, True),
]
IMPLEMENTATION_PATHS = [
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/CMakeLists.txt",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/README.md",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/New-G2StaticMeshPayloadSectionPrefix.ps1",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/static_mesh_prefix_common.py",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/apps/prefix_probe_main.cpp",
    POLICY_PATH,
    SCHEMA_PATH,
    DETAIL_SCHEMA_PATH,
    "Docs/Formats/G2-STATIC-MESH-PAYLOAD-SECTION-PREFIX.md",
    "Tests/Contract/Test-G2StaticMeshPayloadSectionPrefix.ps1",
    "Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.cpp",
    "Tools/TMXY.G2AssetBindingFailureDiagnostics/apps/probe_support.hpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.cpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/semantic_hash.hpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.cpp",
    "Tools/TMXY.G2AssetDescriptorDiagnostics/sha256.hpp",
    "Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.cpp",
    "Tools/TMXY.AssetInventory/apps/descriptor_semantic_signature.hpp",
]


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def _text_sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _expected_entry(root: Path, role: str, relative: str, tracked: bool,
                    resolve_inside: Callable[[Path, str], Path],
                    sha256: Callable[[Path], str]) -> dict[str, Any]:
    path = resolve_inside(root, relative)
    return {"role": role, "path": relative, "tracked": tracked,
            "bytes": path.stat().st_size, "lines": _line_count(path),
            "sha256": sha256(path)}


def _binding_aggregate(entries: list[dict[str, Any]]) -> str:
    value = "".join(
        f"{item['role']}\t{item['path']}\t{str(item['tracked']).lower()}\t"
        f"{item['bytes']}\t{item['lines']}\t{item['sha256']}\n"
        for item in entries)
    return _text_sha256(value)


def _validate_detail(path: Path, report: dict[str, Any],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> None:
    advertised = report.get("detail_export", {})
    require(advertised == {"path": DETAIL_PATH, "tracked": False,
                           "bytes": path.stat().st_size, "lines": 1,
                           "sha256": sha256(path)},
            "P2-20A.12 ignored detail hash or shape drifted")
    lines = path.read_text(encoding="utf-8").splitlines()
    require(len(lines) == 1, "P2-20A.12 ignored detail row count drifted")
    row = json.loads(lines[0])
    require(isinstance(row, dict) and row.get("family") == "sm" and
            row.get("candidate_count") == 2 and
            row.get("recovery_kind") == "sm_payload_section_prefix" and
            row.get("basis") == "payload_section_prefix_contract" and
            row.get("effective_resolution") == "UNRESOLVED" and
            row.get("candidate_selected") is False and
            row.get("automatic_resolution") is False and
            row.get("authority_state_changed") is False,
            "P2-20A.12 ignored detail authority state drifted")
    candidates = row.get("candidates", [])
    require(isinstance(candidates, list) and len(candidates) == 2 and
            len({item.get("candidate_id") for item in candidates}) == 2 and
            all(item.get("strict_binding") == "REJECTED" and
                item.get("strict_error_code") == "material_slot_mismatch" and
                item.get("prefix_binding") == "PASS" and
                item.get("declared_material_slots") == 2 and
                item.get("payload_sections") == 1 and
                item.get("nonempty_payload_sections") == 1 and
                item.get("ignored_trailing_material_slots") == 1 and
                item.get("slot_basis") == "payload_section_prefix_contract" and
                item.get("recovery_applied") is False and
                item.get("adapter_applied") is False and
                item.get("content_disposition") == "NONE" for item in candidates),
            "P2-20A.12 ignored candidate relation drifted")
    for field in ("body_sha256", "descriptor_semantic_sha256",
                  "strict_semantic_sha256", "prefix_semantic_sha256"):
        require(len({item.get(field) for item in candidates}) == 1,
                f"P2-20A.12 {field} variant count drifted")


def _validate_report(root: Path, report: dict[str, Any],
                     load_json: Callable[[Path], dict[str, Any]],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> None:
    require(report.get("evidence_revision") == REVISION and
            report.get("task_id") == "P2-20A" and
            report.get("criterion_id") == "G2-06" and
            report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS_DIAGNOSTIC" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            report.get("diagnostic_scope_complete") is True and
            report.get("remediation_scope_complete") is False and
            report.get("g2_06_satisfied") is False and
            report.get("p3_authorized") is False,
            "P2-20A.12 diagnostic was falsely promoted")
    require(report.get("proof_classification") == {
                "source_basis": "SOURCE_DERIVED", "legacy_binary_executed": False,
                "runtime_parity_proven": False},
            "P2-20A.12 proof classification drifted")
    expected_entries = [_expected_entry(root, *item, resolve_inside, sha256)
                        for item in INPUT_PATHS]
    bindings = report.get("input_bindings", {})
    require(bindings.get("entries") == expected_entries and
            bindings.get("aggregate_sha256") == _binding_aggregate(expected_entries),
            "P2-20A.12 report inputs are not exactly hash-bound")
    _validate_detail(resolve_inside(root, DETAIL_PATH), report, sha256, require)
    policy = load_json(resolve_inside(root, POLICY_PATH))
    require(report.get("scope") == {
                "source_revision": "P2-20A.7", "family": "sm", "targets": 1,
                "candidate_edges": 2, "unique_candidates": 2,
                "candidate_ids_distinct": True, "candidate_set_exact": True},
            "P2-20A.12 diagnostic scope drifted")
    require(report.get("measured") == {
                "source_assets_reverified": 1, "package_files_hashed": 2,
                "candidate_bodies_reverified": 2, "strict_rejected_edges": 2,
                "material_slot_mismatch_edges": 2, "prefix_pass_edges": 2,
                "body_variants": 1, "descriptor_semantic_variants": 1,
                "strict_semantic_variants": 1, "prefix_semantic_variants": 1,
                "candidate_selections": 0, "automatic_resolutions": 0,
                "owner_dispositions": 0, "content_dispositions": 0},
            "P2-20A.12 measurements drifted")
    require(report.get("observed_relation") == {
                "recovery_kind": "sm_payload_section_prefix",
                "basis": "payload_section_prefix_contract",
                "descriptor_material_slots": 2, "payload_sections": 1,
                "nonempty_payload_sections": 1, "ignored_trailing_material_slots": 1,
                "dense_material_slots": True, "observed_edges": 2},
            "P2-20A.12 observed prefix relation drifted")
    require(report.get("authority_boundary") == {
                "a4_is_authoritative": True, "authority_state_changed": False,
                "adapter_applied": False, "recovery_applied": False,
                "machine_can_select_candidate": False,
                "machine_can_approve_disposition": False, "repair_or_write": False,
                "delete_or_no_ref": False, "owner_approvals": 0,
                "verified_resolutions": 0},
            "P2-20A.12 authority boundary drifted")
    require(report.get("preserved_blockers") == policy["preserved_blockers"],
            "P2-20A.12 preserved blockers drifted")
    expected_legacy = sorted(policy["legacy_source_roles"], key=lambda item: item["role"])
    legacy = report.get("legacy_source_provenance", {})
    legacy_text = "".join(f"{item['role']}\t{item['sha256']}\n"
                          for item in expected_legacy)
    require(legacy == {"aggregate_sha256": _text_sha256(legacy_text),
                       "roles": expected_legacy} and
            report.get("source_facts") == policy["expected_source_facts"],
            "P2-20A.12 legacy source proof drifted")
    contracts = report.get("contracts", {})
    require(contracts == {
                "policy_sha256": sha256(resolve_inside(root, POLICY_PATH)),
                "schema_sha256": sha256(resolve_inside(root, SCHEMA_PATH)),
                "detail_schema_sha256": sha256(resolve_inside(root, DETAIL_SCHEMA_PATH))},
            "P2-20A.12 contract hashes drifted")
    production_entries = [_expected_entry(root, *item, resolve_inside, sha256)
                          for item in PRODUCTION_PATHS]
    require(report.get("production_contract") == {
                "api": "bind_static_mesh_with_payload_section_prefix",
                "implementation_bindings": {
                    "aggregate_sha256": _binding_aggregate(production_entries),
                    "entries": production_entries}},
            "P2-20A.12 production contract hash drifted")
    require(report.get("disclosure") == policy["disclosure"],
            "P2-20A.12 disclosure boundary drifted")


def _validate_inventory(root: Path, inventory: dict[str, Any], report_path: Path,
                        detail_path: Path, sha256: Callable[[Path], str],
                        resolve_inside: Callable[[Path, str], Path],
                        require: Callable[[bool, str], None]) -> None:
    require(inventory.get("evidence_revision") == REVISION and
            inventory.get("result") == "BLOCKED" and
            inventory.get("review_execution_result") == "PASS_DIAGNOSTIC" and
            inventory.get("task_status") == "BLOCKED" and
            inventory.get("g2_06_satisfied") is False and
            inventory.get("p3_authorized") is False,
            "P2-20A.12 inventory state drifted")
    report_binding = inventory.get("report", {})
    require(report_binding.get("path") == REPORT_PATH and
            report_binding.get("tracked") is True and
            report_binding.get("bytes") == report_path.stat().st_size and
            report_binding.get("lines") == _line_count(report_path) and
            report_binding.get("sha256") == sha256(report_path),
            "P2-20A.12 inventory report hash drifted")
    detail_binding = inventory.get("outputs", {}).get("detail_export", {})
    require(detail_binding == {"path": DETAIL_PATH, "tracked": False,
                               "bytes": detail_path.stat().st_size,
                               "lines": 1, "sha256": sha256(detail_path)},
            "P2-20A.12 inventory detail hash drifted")
    require(inventory.get("proof_classification") == {
                "source_basis": "SOURCE_DERIVED", "legacy_binary_executed": False,
                "runtime_parity_proven": False} and
            inventory.get("authority_boundary", {}).get("authority_state_changed") is False and
            inventory.get("authority_boundary", {}).get("adapter_applied") is False and
            inventory.get("authority_boundary", {}).get("recovery_applied") is False and
            inventory.get("preserved_blockers", {}).get("asset_effective_ambiguous_targets") == 189 and
            inventory.get("preserved_blockers", {}).get("asset_effective_ambiguous_edges") == 546 and
            inventory.get("preserved_blockers", {}).get("asset_effective_unresolved_targets") == 12 and
            inventory.get("preserved_blockers", {}).get("asset_effective_unresolved_edges") == 15,
             "P2-20A.12 inventory authority or blocker state drifted")
    implementation_entries = [
        _expected_entry(root, f"implementation_{index:02d}", relative, True,
                        resolve_inside, sha256)
        for index, relative in enumerate(IMPLEMENTATION_PATHS, 1)]
    require(inventory.get("implementation") == {
                "files": implementation_entries,
                "aggregate_sha256": _binding_aggregate(implementation_entries),
                "generator_self_test_assertions": 20,
                "probe_startup_self_tests": True},
            "P2-20A.12 implementation evidence drifted")


def static_mesh_prefix_safe(report: dict[str, Any]) -> bool:
    measured = report["measured"]
    authority = report["authority_boundary"]
    proof = report["proof_classification"]
    blockers = report["preserved_blockers"]
    return (proof == {"source_basis": "SOURCE_DERIVED", "legacy_binary_executed": False,
                      "runtime_parity_proven": False} and
            measured["strict_rejected_edges"] == 2 and
            measured["prefix_pass_edges"] == 2 and
            measured["candidate_selections"] == 0 and
            measured["automatic_resolutions"] == 0 and
            authority["authority_state_changed"] is False and
            authority["adapter_applied"] is False and
            authority["recovery_applied"] is False and
            blockers["asset_effective_ambiguous_targets"] == 189 and
            blockers["asset_effective_unresolved_targets"] == 12)


def static_mesh_prefix_metrics(report: dict[str, Any]) -> list[tuple[str, Any, str]]:
    scope = report["scope"]
    measured = report["measured"]
    relation = report["observed_relation"]
    proof = report["proof_classification"]
    authority = report["authority_boundary"]
    blockers = report["preserved_blockers"]
    return [
        ("static_mesh_prefix_diagnostic_hash_bound", True, "boolean"),
        ("static_mesh_prefix_inventory_hash_bound", True, "boolean"),
        ("static_mesh_prefix_detail_hash_bound", True, "boolean"),
        ("static_mesh_prefix_source_derived_contract_proven", True, "boolean"),
        ("static_mesh_prefix_runtime_parity_proven", proof["runtime_parity_proven"], "boolean"),
        ("static_mesh_prefix_targets", scope["targets"], "assets"),
        ("static_mesh_prefix_candidate_edges", scope["candidate_edges"], "edges"),
        ("static_mesh_prefix_strict_rejected_edges", measured["strict_rejected_edges"], "edges"),
        ("static_mesh_prefix_explicit_prefix_pass_edges", measured["prefix_pass_edges"], "edges"),
        ("static_mesh_prefix_payload_sections", relation["payload_sections"], "sections"),
        ("static_mesh_prefix_material_slots", relation["descriptor_material_slots"], "slots"),
        ("static_mesh_prefix_ignored_trailing_material_slots",
         relation["ignored_trailing_material_slots"], "slots"),
        ("static_mesh_prefix_candidate_selections", measured["candidate_selections"], "assets"),
        ("static_mesh_prefix_automatic_resolutions", measured["automatic_resolutions"], "assets"),
        ("static_mesh_prefix_adapter_applied", authority["adapter_applied"], "boolean"),
        ("static_mesh_prefix_authority_state_changed",
         authority["authority_state_changed"], "boolean"),
        ("static_mesh_prefix_recovery_applied", authority["recovery_applied"], "boolean"),
        ("static_mesh_prefix_preserved_ambiguous_targets",
         blockers["asset_effective_ambiguous_targets"], "assets"),
        ("static_mesh_prefix_preserved_ambiguous_edges",
         blockers["asset_effective_ambiguous_edges"], "edges"),
        ("static_mesh_prefix_preserved_unresolved_targets",
         blockers["asset_effective_unresolved_targets"], "assets"),
        ("static_mesh_prefix_preserved_unresolved_edges",
         blockers["asset_effective_unresolved_edges"], "edges"),
    ]


def static_mesh_prefix_blocker_text(
        report: dict[str, Any], asset_binding: dict[str, Any]) -> str:
    """Describe the diagnostic without granting A.4/A.8 authority."""
    scope = report["scope"]
    relation = report["observed_relation"]
    return (
        f"A.12 source-derives an explicit payload-section-prefix PASS for "
        f"{scope['targets']} static-mesh target / {scope['candidate_edges']} edges, where "
        f"{relation['descriptor_material_slots']} declared material slots map to "
        f"{relation['nonempty_payload_sections']} nonempty payload section with "
        f"{relation['ignored_trailing_material_slots']} ignored trailing slot. It changes no "
        "A.4/A.8 authority state, selects no candidate, applies no adapter or recovery, and "
        "proves no runtime parity; the full asset workset remains "
        f"{asset_binding['ambiguous_targets']} targets / {asset_binding['ambiguous_edges']} "
        f"edges ambiguous and {asset_binding['unresolved_targets']} targets / "
        f"{asset_binding['unresolved_edges']} edges unresolved.")


def bind_static_mesh_payload_section_prefix(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["static_mesh_payload_section_prefix"]
    require(spec == {"task_id": "P2-20A", "criterion_id": "G2-06",
                     "evidence_revision": REVISION, "path": REPORT_PATH},
            "P2-20A.12 G2 policy binding drifted")
    report_path = resolve_inside(root, REPORT_PATH)
    inventory_path = resolve_inside(root, INVENTORY_PATH)
    detail_path = resolve_inside(root, DETAIL_PATH)
    report = load_json(report_path)
    inventory = load_json(inventory_path)
    _validate_report(root, report, load_json, resolve_inside, sha256, require)
    _validate_inventory(root, inventory, report_path, detail_path, sha256,
                        resolve_inside, require)
    report_digest = sha256(report_path)
    inventory_digest = sha256(inventory_path)
    detail_digest = sha256(detail_path)
    binding = {
        "task_id": "P2-20A", "criterion_id": "G2-06", "evidence_revision": REVISION,
        "path": REPORT_PATH, "sha256": report_digest,
        "inventory_path": INVENTORY_PATH, "inventory_sha256": inventory_digest,
        "detail_path": DETAIL_PATH, "detail_sha256": detail_digest,
        "result": report["result"],
        "review_execution_result": report["review_execution_result"],
        "task_status": report["task_status"],
        "completion_criteria_satisfied": report["completion_criteria_satisfied"],
        "diagnostic_scope_complete": report["diagnostic_scope_complete"],
        "remediation_scope_complete": report["remediation_scope_complete"],
        "g2_06_satisfied": report["g2_06_satisfied"],
    }
    aggregate = (f"STATIC_MESH_PREFIX|P2-20A|G2-06|{REVISION}|{REPORT_PATH}|"
                 f"{report_digest}|{INVENTORY_PATH}|{inventory_digest}|{DETAIL_PATH}|"
                 f"{detail_digest}")
    return binding, report, aggregate


def static_mesh_prefix_self_test() -> dict[str, Any]:
    current = {
        "proof_classification": {"source_basis": "SOURCE_DERIVED",
                                 "legacy_binary_executed": False,
                                 "runtime_parity_proven": False},
        "measured": {"strict_rejected_edges": 2, "prefix_pass_edges": 2,
                     "candidate_selections": 0, "automatic_resolutions": 0},
        "authority_boundary": {"authority_state_changed": False,
                               "adapter_applied": False, "recovery_applied": False},
        "preserved_blockers": {"asset_effective_ambiguous_targets": 189,
                               "asset_effective_unresolved_targets": 12},
    }
    if not static_mesh_prefix_safe(current):
        raise ValueError("Static-mesh prefix source proof self-test failed")
    forged = json.loads(json.dumps(current))
    forged["authority_boundary"]["authority_state_changed"] = True
    if static_mesh_prefix_safe(forged):
        raise ValueError("Static-mesh prefix authority promotion was accepted")
    return {"result": "PASS", "assertions": 2,
            "source_derived_safe": True, "authority_promotion_rejected": True}
