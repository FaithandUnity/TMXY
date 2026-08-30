"""Deterministic P2-20A.12 static-mesh payload-section-prefix source proof."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import tempfile
from pathlib import Path
from typing import Any

from static_mesh_prefix_common import (
    DETAIL_CANDIDATE_FIELDS, DETAIL_FIELDS, INPUTS, binding, binding_set,
    candidate_set_sha256, line_count, load_json, output_binding, prepare_from_a7,
    require, sha256_file, sha256_text, validate_frozen, write_text,
)


REPORT_PATH = "Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.json"
MARKDOWN_PATH = "Data/Reports/p2-20a-static-mesh-payload-section-prefix-report.md"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-static-mesh-payload-section-prefix.jsonl"
EVIDENCE_PATH = "Data/Inventory/p2-20a-static-mesh-payload-section-prefix.json"
PRODUCTION_SOURCES = [
    ("static_mesh_types_header", "Tools/TMXY.StaticMesh/include/tmxy/static_mesh/static_mesh_types.hpp", True),
    ("static_mesh_api_header", "Tools/TMXY.StaticMesh/include/tmxy/static_mesh/package_static_mesh_reader.hpp", True),
    ("static_mesh_binding_implementation", "Tools/TMXY.StaticMesh/src/package_static_mesh_reader.cpp", True),
    ("static_mesh_payload_parser", "Tools/TMXY.StaticMesh/src/sm_reader.cpp", True),
    ("static_mesh_error_source", "Tools/TMXY.StaticMesh/src/static_mesh_error.cpp", True),
]
IMPLEMENTATION_SOURCES = [
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/CMakeLists.txt",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/README.md",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/New-G2StaticMeshPayloadSectionPrefix.ps1",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/g2_static_mesh_payload_section_prefix.py",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/static_mesh_prefix_common.py",
    "Tools/TMXY.G2StaticMeshPayloadSectionPrefix/apps/prefix_probe_main.cpp",
    "Contracts/data-schema/g2-static-mesh-payload-section-prefix-policy-v1.json",
    "Contracts/data-schema/g2-static-mesh-payload-section-prefix-v1.schema.json",
    "Contracts/data-schema/g2-static-mesh-payload-section-prefix-detail-v1.schema.json",
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


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def canonical_detail(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def validate_detail(value: dict[str, Any]) -> None:
    require(set(value) == DETAIL_FIELDS, "Probe detail root is not closed")
    require(is_sha256(value["asset_id"]) and value["family"] == "sm" and
            value["candidate_count"] == 2 and is_sha256(value["candidate_set_sha256"]) and
            value["recovery_kind"] == "sm_payload_section_prefix" and
            value["basis"] == "payload_section_prefix_contract" and
            value["effective_resolution"] == "UNRESOLVED" and
            value["candidate_selected"] is False and
            value["automatic_resolution"] is False and
            value["authority_state_changed"] is False, "Probe root state drifted")
    candidates = value["candidates"]
    require(isinstance(candidates, list) and len(candidates) == 2, "Probe candidate count drifted")
    for candidate in candidates:
        require(set(candidate) == DETAIL_CANDIDATE_FIELDS, "Probe candidate is not closed")
        require(all(is_sha256(candidate[key]) for key in (
            "candidate_id", "package_sha256", "body_sha256", "descriptor_semantic_sha256",
            "strict_semantic_sha256", "prefix_semantic_sha256")), "Probe hash is invalid")
        require(candidate["strict_binding"] == "REJECTED" and
                candidate["strict_error_code"] == "material_slot_mismatch" and
                candidate["prefix_binding"] == "PASS" and
                candidate["declared_material_slots"] == 2 and
                candidate["payload_sections"] == 1 and
                candidate["nonempty_payload_sections"] == 1 and
                candidate["ignored_trailing_material_slots"] == 1 and
                candidate["slot_basis"] == "payload_section_prefix_contract" and
                candidate["recovery_applied"] is False and
                candidate["adapter_applied"] is False and
                candidate["content_disposition"] == "NONE", "Probe relation drifted")
    ids = [str(item["candidate_id"]) for item in candidates]
    require(len(set(ids)) == 2 and candidate_set_sha256(ids) == value["candidate_set_sha256"],
            "Probe candidate set drifted")


def compact_source(path: Path) -> bytes:
    return re.sub(rb"\s+", b"", path.read_bytes()).lower()


def has_all(source: bytes, tokens: tuple[bytes, ...]) -> bool:
    return all(token.lower() in source for token in tokens)


def legacy_source_proof(policy: dict[str, Any], specifications: list[str]) -> tuple[dict[str, Any], dict[str, bool]]:
    supplied: dict[str, Path] = {}
    for specification in specifications:
        role, separator, path_text = specification.partition("=")
        require(separator == "=" and role and path_text and role not in supplied,
                "Legacy source role argument is invalid or duplicated")
        path = Path(path_text).resolve()
        require(path.is_file(), f"Legacy source role is unreadable: {role}")
        supplied[role] = path
    expected = {str(item["role"]): str(item["sha256"])
                for item in policy["legacy_source_roles"]}
    require(set(supplied) == set(expected), "Legacy source role set is incomplete or extra")
    require(all(sha256_file(supplied[role]) == digest for role, digest in expected.items()),
            "Legacy source role hash drifted")
    sources = {role: compact_source(path) for role, path in supplied.items()}
    exporter_tokens = (b'"set%s.%sskins%d\\n"', b'"[meshsection%02d]\\n"',
                       b"if(numface<=0){continue;}", b"curtriangle.materialindex=nm;")
    exporter_alignment = all(has_all(sources[role], exporter_tokens) for role in
                             ("legacy_exporter_v1", "legacy_exporter_v2010"))
    factory_omission = has_all(sources["legacy_factory_zero_face_filter"], (
        b'printf("meshsection%02d",secid)', b"if(ms.totlefaces>0){data->sections.push(ms);}"))
    programmable = has_all(sources["legacy_renderer_programmable_loop"], (
        b"sectionnum=mesh->sections.size();", b"i<sectionnum", b"mesh->sections[i]",
        b"getmeshmaterial(staticmesh,skins,i)"))
    fixed = has_all(sources["legacy_renderer_fixed_loop"], (
        b"sectionnum=mesh->sections.size();", b"i<sectionnum", b"mesh->sections[i]",
        b"getmeshmaterial(staticmesh,skins,i)"))
    same_index = has_all(sources["legacy_renderer_material_lookup"], (
        b"getmeshmaterial(qmesh*mesh", b"section<skins.size()", b"skins[section]",
        b"section<mesh->skins.size()", b"mesh->skins[section]"))
    payload_order = has_all(sources["legacy_payload_reader_writer"], (
        b"(*binreader)<<pdata->sections;", b"<<pdata->sections<<"))
    facts = {
        "exporter_material_section_ordinal_alignment": exporter_alignment,
        "factory_zero_face_section_omission": factory_omission,
        "renderer_iteration_bounded_by_payload_sections": programmable and fixed,
        "same_index_material_lookup": same_index,
        "trailing_material_slot_not_consumed": programmable and fixed and same_index,
        "payload_section_order_preserved": payload_order,
    }
    require(facts == policy["expected_source_facts"], "Legacy role source-fact proof drifted")
    roles = [{"role": role, "sha256": expected[role]} for role in sorted(expected)]
    aggregate = sha256_text("".join(f"{item['role']}\t{item['sha256']}\n" for item in roles))
    return {"aggregate_sha256": aggregate, "roles": roles}, facts


def reconcile_probe(context: dict[str, Any], detail: dict[str, Any]) -> dict[str, Any]:
    validate_detail(detail)
    frozen, a4_candidates = context["frozen"], context["a4_candidates"]
    require(detail["asset_id"] == frozen["asset_id"] and
            detail["candidate_set_sha256"] == frozen["candidate_set_sha256"],
            "Probe target identity drifted")
    a7_candidates = {str(item["candidate_id"]): item for item in frozen["candidates"]}
    observed = {str(item["candidate_id"]): item for item in detail["candidates"]}
    require(set(observed) == set(a7_candidates) == set(a4_candidates),
            "Probe candidate set differs from A.4/A.7")
    for identity, candidate in observed.items():
        require(candidate["body_sha256"] == a7_candidates[identity]["body_sha256"] and
                candidate["descriptor_semantic_sha256"] ==
                a7_candidates[identity]["descriptor_semantic_sha256"] and
                candidate["strict_semantic_sha256"] == a4_candidates[identity]["semantic_sha256"],
                "Probe body or semantic hash drifted from A.4/A.7")
    variants = {
        "body_variants": len({item["body_sha256"] for item in observed.values()}),
        "descriptor_semantic_variants": len({item["descriptor_semantic_sha256"] for item in observed.values()}),
        "strict_semantic_variants": len({item["strict_semantic_sha256"] for item in observed.values()}),
        "prefix_semantic_variants": len({item["prefix_semantic_sha256"] for item in observed.values()}),
    }
    require(set(variants.values()) == {1}, "Frozen SM semantic equivalence drifted")
    return variants


def production_contract(root: Path) -> dict[str, Any]:
    entries = [binding(root, role, relative, tracked)
               for role, relative, tracked in PRODUCTION_SOURCES]
    return {"api": "bind_static_mesh_with_payload_section_prefix",
            "implementation_bindings": binding_set(entries)}


def implementation_evidence(root: Path) -> dict[str, Any]:
    entries = [binding(root, f"implementation_{index:02d}", relative, True)
               for index, relative in enumerate(IMPLEMENTATION_SOURCES, 1)]
    return {"files": entries, "aggregate_sha256": binding_set(entries)["aggregate_sha256"],
            "generator_self_test_assertions": 20, "probe_startup_self_tests": True}


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    context = validate_frozen(root)
    records = list(iter_probe(Path(args.probe_jsonl)))
    require(len(records) == 1, "Probe must emit exactly one target record")
    detail = records[0]
    variants = reconcile_probe(context, detail)
    detail_path = Path(args.detail_output)
    write_text(detail_path, canonical_detail(detail))
    policy = context["policy"]
    legacy, facts = legacy_source_proof(policy, args.legacy_source)
    inputs = [binding(root, role, relative, tracked) for role, relative, tracked in INPUTS]
    measured = {
        "source_assets_reverified": 1, "package_files_hashed": 2,
        "candidate_bodies_reverified": 2, "strict_rejected_edges": 2,
        "material_slot_mismatch_edges": 2, "prefix_pass_edges": 2, **variants,
        "candidate_selections": 0, "automatic_resolutions": 0,
        "owner_dispositions": 0, "content_dispositions": 0,
    }
    report = {
        "schema_version": 1, "evidence_revision": "P2-20A.12",
        "captured_utc": args.captured_utc or utc_now(), "task_id": "P2-20A",
        "criterion_id": "G2-06", "result": "BLOCKED",
        "review_execution_result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "remediation_scope_complete": False, "g2_06_satisfied": False,
        "p3_authorized": False,
        "proof_classification": {"source_basis": "SOURCE_DERIVED",
                                 "legacy_binary_executed": False,
                                 "runtime_parity_proven": False},
        "input_bindings": binding_set(inputs),
        "detail_export": output_binding(detail_path, DETAIL_PATH, False),
        "legacy_source_provenance": legacy, "source_facts": facts,
        "production_contract": production_contract(root),
        "scope": {"source_revision": "P2-20A.7", "family": "sm", "targets": 1,
                  "candidate_edges": 2, "unique_candidates": 2,
                  "candidate_ids_distinct": True, "candidate_set_exact": True},
        "measured": measured,
        "observed_relation": {"recovery_kind": "sm_payload_section_prefix",
            "basis": "payload_section_prefix_contract", "descriptor_material_slots": 2,
            "payload_sections": 1, "nonempty_payload_sections": 1,
            "ignored_trailing_material_slots": 1, "dense_material_slots": True,
            "observed_edges": 2},
        "authority_boundary": {"a4_is_authoritative": True,
            "authority_state_changed": False, "adapter_applied": False,
            "recovery_applied": False, "machine_can_select_candidate": False,
            "machine_can_approve_disposition": False, "repair_or_write": False,
            "delete_or_no_ref": False, "owner_approvals": 0, "verified_resolutions": 0},
        "preserved_blockers": context["blockers"],
        "contracts": {"policy_sha256": sha256_file(context["paths"]["policy"]),
            "schema_sha256": sha256_file(context["paths"]["schema"]),
            "detail_schema_sha256": sha256_file(context["paths"]["detail_schema"])},
        "disclosure": policy["disclosure"],
    }
    report_path, markdown_path = Path(args.json_output), Path(args.markdown_output)
    write_text(report_path, json_text(report))
    write_text(markdown_path,
        "# P2-20A.12 Static-Mesh Payload-Section Prefix Source Proof\n\n"
        "- Execution: `PASS_DIAGNOSTIC`; task: `BLOCKED`\n"
        "- Frozen scope: 1 target / 2 candidate edges\n"
        "- Strict production binding: 2 `material_slot_mismatch` rejections\n"
        "- Explicit prefix API: 2 passes with 2 declared slots / 1 nonempty payload section / 1 ignored trailing slot\n"
        "- Semantic variants: body 1, descriptor 1, strict 1, prefix 1\n\n"
        "This is a hash-locked `SOURCE_DERIVED` diagnostic. No legacy binary was executed, "
        "runtime parity was not proven, and no adapter, recovery, selection, disposition, repair, "
        "or authority change occurred. A.4 remains authoritative; the current A.4/A.7/A.8 chain "
        f"reconciles to {context['blockers']['asset_effective_unresolved_targets']} unresolved "
        f"targets / {context['blockers']['asset_effective_unresolved_edges']} unresolved edges; "
        "G2-06 and P3 remain blocked.\n")
    evidence = {
        "schema_version": 1, "evidence_revision": "P2-20A.12",
        "captured_utc": report["captured_utc"], "result": "BLOCKED",
        "review_execution_result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
        "g2_06_satisfied": False, "p3_authorized": False, "measured": measured,
        "report": output_binding(report_path, REPORT_PATH, True),
        "report_markdown": output_binding(markdown_path, MARKDOWN_PATH, True),
        "outputs": {"detail_export": report["detail_export"]},
        "contracts": report["contracts"], "implementation": implementation_evidence(root),
        "builder": {"image_reference": args.builder_reference,
                    "image_id": args.builder_id, "user": "tmxy"},
        "isolation": {"network": "none", "read_only_container": True,
                      "cap_drop": "ALL", "no_new_privileges": True,
                      "repository_mount": "read-only", "legacy_asset_mount": "read-only",
                      "legacy_source_mounts": "read-only-files"},
        "proof_classification": report["proof_classification"],
        "authority_boundary": report["authority_boundary"],
        "preserved_blockers": report["preserved_blockers"], "disclosure": report["disclosure"],
    }
    write_text(Path(args.evidence_output), json_text(evidence))
    return {"result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED", "targets": 1,
            "candidate_edges": 2, "strict_rejected_edges": 2, "prefix_pass_edges": 2,
            **variants, "candidate_selections": 0, "automatic_resolutions": 0,
            "g2_06_satisfied": False, "p3_authorized": False}


def iter_probe(path: Path):
    with path.open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            value = json.loads(line)
            require(isinstance(value, dict), "Probe JSONL root is not an object")
            yield value


def self_test() -> dict[str, Any]:
    assertions = 0
    def check(condition: bool, message: str) -> None:
        nonlocal assertions
        require(condition, message)
        assertions += 1
    check(candidate_set_sha256(["b" * 64, "a" * 64]) ==
          candidate_set_sha256(["a" * 64, "b" * 64]), "Candidate set ordering is unstable")
    check(candidate_set_sha256(["a" * 64]) != candidate_set_sha256(["b" * 64]),
          "Candidate set is insensitive")
    for value in ("a" * 64, "0" * 64, "0123456789abcdef" * 4):
        check(is_sha256(value), "Valid digest rejected")
    for value in ("A" * 64, "a" * 63, "g" * 64, None):
        check(not is_sha256(value), "Invalid digest accepted")
    sample_candidate = {
        "candidate_id": "a" * 64, "package_sha256": "b" * 64,
        "body_sha256": "c" * 64, "descriptor_semantic_sha256": "d" * 64,
        "strict_semantic_sha256": "e" * 64, "strict_binding": "REJECTED",
        "strict_error_code": "material_slot_mismatch", "prefix_binding": "PASS",
        "prefix_semantic_sha256": "f" * 64, "declared_material_slots": 2,
        "payload_sections": 1, "nonempty_payload_sections": 1,
        "ignored_trailing_material_slots": 1, "slot_basis": "payload_section_prefix_contract",
        "recovery_applied": False, "adapter_applied": False, "content_disposition": "NONE"}
    sample = {"asset_id": "1" * 64, "family": "sm", "candidate_count": 2,
        "candidate_set_sha256": candidate_set_sha256(["a" * 64, "2" * 64]),
        "recovery_kind": "sm_payload_section_prefix", "basis": "payload_section_prefix_contract",
        "effective_resolution": "UNRESOLVED", "candidate_selected": False,
        "automatic_resolution": False, "authority_state_changed": False,
        "candidates": [sample_candidate, {**sample_candidate, "candidate_id": "2" * 64}]}
    validate_detail(sample); assertions += 1
    for key in ("candidate_selected", "automatic_resolution", "authority_state_changed"):
        mutated = json.loads(json.dumps(sample)); mutated[key] = True
        try: validate_detail(mutated)
        except ValueError: assertions += 1
        else: require(False, f"False authority state accepted: {key}")
    for key in ("recovery_applied", "adapter_applied"):
        mutated = json.loads(json.dumps(sample)); mutated["candidates"][0][key] = True
        try: validate_detail(mutated)
        except ValueError: assertions += 1
        else: require(False, f"False application state accepted: {key}")
    mutated = json.loads(json.dumps(sample)); mutated["candidates"][0]["payload_sections"] = 2
    try: validate_detail(mutated)
    except ValueError: assertions += 1
    else: require(False, "Forged relation accepted")
    mutated = json.loads(json.dumps(sample)); mutated["unknown"] = False
    try: validate_detail(mutated)
    except ValueError: assertions += 1
    else: require(False, "Unknown root field accepted")
    mutated = json.loads(json.dumps(sample)); mutated["candidates"][0]["unknown"] = False
    try: validate_detail(mutated)
    except ValueError: assertions += 1
    else: require(False, "Unknown nested field accepted")
    check(sha256_text("role\tdigest\n") != sha256_text("role\tdigest2\n"),
          "Aggregate source binding is insensitive")
    check(assertions == 19, "Self-test assertion count drifted")
    return {"result": "PASS", "assertions": assertions}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--self-test", action="store_true")
    sub = result.add_subparsers(dest="command")
    prepare = sub.add_parser("prepare")
    prepare.add_argument("--root", required=True); prepare.add_argument("--a7-asset-tsv", required=True)
    prepare.add_argument("--a7-candidate-tsv", required=True); prepare.add_argument("--asset-tsv", required=True)
    prepare.add_argument("--candidate-tsv", required=True)
    final = sub.add_parser("finalize")
    for name in ("root", "probe-jsonl", "detail-output", "json-output", "markdown-output",
                 "evidence-output", "builder-reference", "builder-id"):
        final.add_argument(f"--{name}", required=True)
    final.add_argument("--legacy-source", action="append", default=[])
    final.add_argument("--captured-utc")
    return result


def main() -> None:
    args = parser().parse_args()
    if args.self_test:
        value = self_test()
    elif args.command == "prepare":
        value = prepare_from_a7(Path(args.root).resolve(), Path(args.a7_asset_tsv),
                                Path(args.a7_candidate_tsv), Path(args.asset_tsv),
                                Path(args.candidate_tsv))
    elif args.command == "finalize":
        value = finalize(args)
    else:
        raise ValueError("A command or --self-test is required")
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
