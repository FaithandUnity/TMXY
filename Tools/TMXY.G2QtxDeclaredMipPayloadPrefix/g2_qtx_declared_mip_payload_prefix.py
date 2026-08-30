"""Deterministic P2-20A.13 QTX declared-mip payload-prefix source proof."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any, Iterable

from qtx_declared_mip_prefix_common import (
    DETAIL_CANDIDATE_FIELDS, DETAIL_FIELDS, INPUTS, binding, binding_set,
    candidate_set_sha256, load_json, output_binding, prepare_scope_and_plan, require,
    sha256_file, sha256_text, validate_final_context, write_text,
)


REPORT_PATH = "Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.json"
MARKDOWN_PATH = "Data/Reports/p2-20a-qtx-declared-mip-payload-prefix-report.md"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix.jsonl"
PLAN_PATH = "Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv"
EVIDENCE_PATH = "Data/Inventory/p2-20a-qtx-declared-mip-payload-prefix.json"
PRODUCTION_SOURCES = [
    ("texture_types_header", "Tools/TMXY.Texture/include/tmxy/texture/texture_types.hpp", True),
    ("qtx_reader_header", "Tools/TMXY.Texture/include/tmxy/texture/qtx_reader.hpp", True),
    ("qtx_reader_implementation", "Tools/TMXY.Texture/src/qtx_reader.cpp", True),
    ("texture_decode_internal_header", "Tools/TMXY.Texture/src/texture_decode_internal.hpp", True),
    ("texture_decode_implementation", "Tools/TMXY.Texture/src/texture_decode.cpp", True),
    ("dds_writer_implementation", "Tools/TMXY.Texture/src/dds_writer.cpp", True),
    ("texture_export_implementation", "Tools/TMXY.Texture/src/texture_export.cpp", True),
    ("texture_error_implementation", "Tools/TMXY.Texture/src/texture_error.cpp", True),
]
IMPLEMENTATION_SOURCES = [
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/CMakeLists.txt",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/README.md",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/New-G2QtxDeclaredMipPayloadPrefix.ps1",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/g2_qtx_declared_mip_payload_prefix.py",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/qtx_declared_mip_prefix_common.py",
    "Tools/TMXY.G2QtxDeclaredMipPayloadPrefix/apps/qtx_declared_mip_prefix_probe_main.cpp",
    "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json",
    "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-v1.schema.json",
    "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json",
    "Docs/Formats/G2-QTX-DECLARED-MIP-PAYLOAD-PREFIX.md",
    "Tests/Contract/Test-G2QtxDeclaredMipPayloadPrefix.ps1",
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
    require(is_sha256(value["asset_id"]) and value["family"] == "qtx" and
            value["candidate_count"] == 1 and is_sha256(value["candidate_set_sha256"]) and
            value["recovery_kind"] == "qtx_declared_mip_payload_prefix" and
            value["basis"] == "declared_mip_payload_prefix_contract" and
            value["source_strict_resolution"] == "UNRESOLVED" and
            value["a13_resolution_change"] is False and value["candidate_selected"] is False and
            value["automatic_resolution"] is False and value["authority_state_changed"] is False,
            "Probe root state drifted")
    candidate = value["candidate"]
    require(isinstance(candidate, dict) and set(candidate) == DETAIL_CANDIDATE_FIELDS,
            "Probe candidate is not closed")
    hash_fields = [key for key in DETAIL_CANDIDATE_FIELDS if key.endswith("_sha256")]
    require(all(is_sha256(candidate[key]) for key in hash_fields), "Probe candidate hash is invalid")
    require(candidate["strict_binding"] == "REJECTED" and
            candidate["strict_error_code"] == "payload_size_mismatch" and
            candidate["strict_prefix_binding"] == "PASS" and
            candidate["explicit_prefix_binding"] == "PASS" and
            candidate["stored_mip_count"] == candidate["declared_mip_count"] ==
            candidate["effective_mip_count"] == 1 and
            candidate["payload_boundary_mip_count"] > 1 and
            candidate["payload_boundary_mip_count"] <= candidate["maximum_natural_mip_count"] and
            candidate["input_payload_bytes"] == candidate["consumed_payload_bytes"] +
            candidate["ignored_payload_bytes"] and candidate["ignored_payload_bytes"] > 0 and
            candidate["dds_header_bytes"] == 128 and
            candidate["dds_payload_bytes"] == candidate["consumed_payload_bytes"] and
            candidate["dds_bytes"] == 128 + candidate["consumed_payload_bytes"] and
            candidate["dds_declared_mip_count"] == 1 and
            candidate["dds_payload_sha256"] == candidate["consumed_payload_sha256"] and
            candidate["dds_payload_prefix_only"] is True and
            candidate["ignored_tail_excluded_from_dds"] is True and
            candidate["payload_extent_basis"] == "declared_mip_payload_prefix_contract" and
            candidate["recovery_applied"] is False and candidate["adapter_applied"] is False and
            candidate["content_disposition"] == "NONE", "Probe prefix relation drifted")
    patterns = {
        ("dxt1", 512, 512, 10, 10, 174776, 131072, 43704, 1048576, 131200),
        ("dxt5", 256, 256, 7, 9, 87376, 65536, 21840, 262144, 65664),
    }
    observed = (candidate["format"], candidate["width"], candidate["height"],
        candidate["payload_boundary_mip_count"], candidate["maximum_natural_mip_count"],
        candidate["input_payload_bytes"], candidate["consumed_payload_bytes"],
        candidate["ignored_payload_bytes"], candidate["decoded_mip_zero_bytes"],
        candidate["dds_bytes"])
    require(observed in patterns, "Probe format/extent pattern drifted")
    require(candidate_set_sha256([candidate["candidate_id"]]) == value["candidate_set_sha256"],
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
    expected = {str(item["role"]): str(item["sha256"]) for item in policy["legacy_source_roles"]}
    require(set(supplied) == set(expected), "Legacy source role set is incomplete or extra")
    require(all(sha256_file(supplied[role]) == digest for role, digest in expected.items()),
            "Legacy source role hash drifted")
    descriptor = compact_source(supplied["legacy_qrender_mip_descriptor"])
    upload = compact_source(supplied["legacy_d3d9_texture_upload"])
    facts = {
        "mip_level_is_serialized_with_zero_default": b"pint(miplevel,0)" in descriptor,
        "stored_zero_is_normalized_to_one_before_upload":
            has_all(upload, (b"if(tex->miplevel==0)", b"tex->miplevel=1;")),
        "texture_allocation_uses_declared_mip_count":
            b"createtexture(tex->usize,tex->vsize,tex->miplevel,0,fmt" in upload,
        "copy_loop_is_bounded_by_declared_mip_count": b"for(inti=0;i<tex->miplevel;i++)" in upload,
        "copy_offset_advances_by_declared_mip_sizes":
            has_all(upload, (b"memcpy(lockedrect.pbits,pfile+offset,size);", b"offset+=size;")),
        "bytes_after_declared_copy_prefix_are_not_read_by_that_loop":
            has_all(upload, (b"for(inti=0;i<tex->miplevel;i++)", b"pfile+offset", b"offset+=size;")),
    }
    require(facts == policy["expected_source_facts"], "Legacy source-fact proof drifted")
    roles = [{"role": role, "sha256": expected[role]} for role in sorted(expected)]
    aggregate = sha256_text("".join(f"{x['role']}\t{x['sha256']}\n" for x in roles))
    return {"aggregate_sha256": aggregate, "roles": roles}, facts


def read_probe(path: Path) -> list[dict[str, Any]]:
    records = []
    with path.open("r", encoding="utf-8-sig") as stream:
        for line in stream:
            value = json.loads(line)
            require(isinstance(value, dict), "Probe JSONL root is not an object")
            records.append(value)
    return records


def reconcile_probe(context: dict[str, Any], records: list[dict[str, Any]]) -> dict[str, int]:
    require(len(records) == 6, "Probe must emit exactly six target records")
    observed = {str(item.get("asset_id")): item for item in records}
    require(len(observed) == 6 and set(observed) == set(context["selected"]),
            "Probe target set differs from frozen scope")
    counts = {"dxt1": 0, "dxt5": 0}
    for asset_id, detail in observed.items():
        validate_detail(detail)
        candidate, expected = detail["candidate"], context["selected"][asset_id]
        require(candidate["candidate_id"] == expected["candidate_id"] and
                candidate["body_sha256"] == expected["body_sha256"] and
                candidate["descriptor_semantic_sha256"] == expected["descriptor_semantic_sha256"] and
                candidate["input_payload_sha256"] == expected["source_sha256"],
                "Probe identity or upstream hash drifted")
        for key in ("format", "width", "height", "stored_mip_count", "declared_mip_count",
                    "payload_boundary_mip_count", "maximum_natural_mip_count",
                    "input_payload_bytes", "consumed_payload_bytes", "ignored_payload_bytes"):
            require(candidate[key] == expected[key], f"Probe frozen metric drifted: {key}")
        a4_candidates = {str(x["candidate_id"]): x for x in context["frozen"][asset_id]["a4"]["candidates"]}
        require(candidate["candidate_id"] in a4_candidates and
                candidate["strict_semantic_sha256"] ==
                a4_candidates[candidate["candidate_id"]]["semantic_sha256"],
                "Probe strict semantic differs from A.4")
        counts[candidate["format"]] += 1
    require(counts == {"dxt1": 3, "dxt5": 3}, "Probe format count drifted")
    return {"dxt1_targets": 3, "dxt5_targets": 3}


def validate_effective_plan(context: dict[str, Any], path: Path) -> None:
    effective = [line.split("\t") for line in path.read_text(encoding="utf-8-sig").splitlines()]
    base = context["base_plan"]
    require(len(effective) == len(base) == 21, "Effective plan row count drifted")
    selected_edges = {(x["asset_id"], x["candidate_id"]) for x in context["selected"].values()}
    changed = 0
    for before, after in zip(base, effective):
        require(len(after) == 7 and before[:5] + before[6:] == after[:5] + after[6:],
                "Effective plan changed a non-kind field")
        if (before[0], before[1]) in selected_edges:
            require(before[5] == "qtx_complete_mip_chain" and
                    after[5] == "qtx_declared_mip_payload_prefix", "Selected plan kind drifted")
            changed += 1
        else:
            require(before == after, "Excluded plan row changed")
    require(changed == 6, "Effective plan changed-row count drifted")


def production_contract(root: Path) -> dict[str, Any]:
    entries = [binding(root, role, relative, tracked) for role, relative, tracked in PRODUCTION_SOURCES]
    return {"api": "tmxy::texture::QtxReader::parse_with_declared_mip_payload_prefix",
            "default_api_remains_strict": True, "implementation_bindings": binding_set(entries)}


def implementation_evidence(root: Path) -> dict[str, Any]:
    entries = [binding(root, f"implementation_{index:02d}", relative, True)
               for index, relative in enumerate(IMPLEMENTATION_SOURCES, 1)]
    return {"files": entries, "aggregate_sha256": binding_set(entries)["aggregate_sha256"],
            "generator_self_test_assertions": 23, "probe_startup_self_tests": True}


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    context = validate_final_context(root)
    records = read_probe(Path(args.probe_jsonl))
    reconcile_probe(context, records)
    detail_path = Path(args.detail_output)
    write_text(detail_path, "".join(canonical_detail(item) for item in
                                     sorted(records, key=lambda x: str(x["asset_id"]))))
    effective_path = Path(args.effective_plan)
    validate_effective_plan(context, effective_path)
    legacy, facts = legacy_source_proof(context["policy"], args.legacy_source)
    inputs = [binding(root, role, relative, tracked) for role, relative, tracked in INPUTS]
    measured = {"source_assets_reverified": 6, "candidate_packages_hashed": 6,
        "candidate_bodies_reverified": 6, "strict_default_rejected_edges": 6,
        "payload_size_mismatch_edges": 6, "strict_prefix_pass_edges": 6,
        "explicit_prefix_pass_edges": 6, "full_payload_boundary_edges": 6,
        "decoded_mip_zero_match_edges": 6, "dds_prefix_only_edges": 6,
        "ignored_tail_hashes": 6, "dxt1_targets": 3, "dxt5_targets": 3,
        "input_payload_bytes": 786456, "consumed_payload_bytes": 589824,
        "ignored_payload_bytes": 196632, "base_recovery_plan_rows": 21,
        "effective_recovery_plan_rows": 21, "effective_plan_changed_rows": 6,
        "effective_plan_unchanged_rows": 15, "candidate_selections": 0,
        "automatic_resolutions": 0, "owner_dispositions": 0, "content_dispositions": 0}
    phase = context["effective_phase"]
    require(phase == "POST_APPLICATION",
            "Final A.13 evidence requires the post-application upstream state")
    applied = 6
    authority = {"a4_is_authoritative": True, "authority_state_changed": False,
        "adapter_applied": False, "recovery_applied": False,
        "machine_can_select_candidate": False, "machine_can_approve_disposition": False,
        "repair_or_write": False, "delete_or_no_ref": False, "owner_approvals": 0,
        "verified_resolutions": 0}
    relation = {"recovery_kind": "qtx_declared_mip_payload_prefix",
        "basis": "declared_mip_payload_prefix_contract", "default_strict_binding": "REJECTED",
        "default_strict_error_code": "payload_size_mismatch", "explicit_api_binding": "PASS",
        "stored_mip_count": 1, "declared_mip_count": 1, "full_payload_boundary_exact_edges": 6,
        "consumed_plus_ignored_equals_input_edges": 6,
        "decoded_mip_zero_matches_strict_prefix_edges": 6, "dds_payload_prefix_only_edges": 6,
        "ignored_tail_excluded_from_dds_edges": 6, "ignored_tail_sha256_edges": 6,
        "dxt1_512_boundary_10_max_10_targets": 3, "dxt5_256_boundary_7_max_9_targets": 3,
        "base_plan_recovery_kind": "qtx_complete_mip_chain",
        "effective_plan_recovery_kind": "qtx_declared_mip_payload_prefix",
        "effective_plan_row_set_preserved": True, "effective_plan_only_recovery_kind_changed": True}
    report = {"schema_version": 1, "evidence_revision": "P2-20A.13",
        "captured_utc": args.captured_utc or utc_now(), "task_id": "P2-20A", "criterion_id": "G2-06",
        "result": "BLOCKED", "review_execution_result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "remediation_scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "proof_classification": {"source_basis": "SOURCE_DERIVED",
            "legacy_binary_executed": False, "runtime_parity_proven": False},
        "input_bindings": binding_set(inputs),
        "detail_export": output_binding(detail_path, DETAIL_PATH, False),
        "effective_recovery_plan": output_binding(effective_path, PLAN_PATH, False),
        "legacy_source_provenance": legacy, "source_facts": facts,
        "production_contract": production_contract(root),
        "scope": {"source_revision": "P2-20A.7", "family": "qtx", "targets": 6,
            "candidate_edges": 6, "unique_candidates": 6, "candidate_ids_distinct": True,
            "candidate_set_exact": True, "excluded_unresolved_targets": 4,
            "excluded_unresolved_edges": 6, "excluded_scope_selected": False,
            "current_upstream_effective_state": {"phase": phase,
                "selected_targets_resolved": applied, "selected_edges_pass": applied,
                "selected_recovery_applied_edges": applied}},
        "measured": measured, "observed_relation": relation, "authority_boundary": authority,
        "preserved_blockers": context["blockers"],
        "contracts": {"policy_sha256": sha256_file(context["paths"]["policy"]),
            "schema_sha256": sha256_file(context["paths"]["schema"]),
            "detail_schema_sha256": sha256_file(context["paths"]["detail_schema"]),
            "base_plan_contract_sha256":
                sha256_file(context["paths"]["base_plan_contract"])},
        "disclosure": context["policy"]["disclosure"]}
    report_path, markdown_path = Path(args.json_output), Path(args.markdown_output)
    write_text(report_path, json_text(report))
    blockers = context["blockers"]
    write_text(markdown_path,
        "# P2-20A.13 QTX Declared-Mip Payload-Prefix Source Proof\n\n"
        "- Execution: `PASS_DIAGNOSTIC`; task: `BLOCKED`\n"
        f"- Upstream effective phase: `{phase}`\n"
        "- Frozen scope: 6 targets / 6 unique candidate edges; excluded: 4 targets / 6 edges\n"
        "- DXT1: 3 x 512x512, boundary 10 / max 10, 174776 = 131072 + 43704 bytes\n"
        "- DXT5: 3 x 256x256, boundary 7 / max 9, 87376 = 65536 + 21840 bytes\n"
        "- Default strict parser: 6 payload-size rejections; explicit prefix API: 6 passes\n"
        "- Effective plan: 21 rows, exactly 6 recovery-kind cells changed\n"
        f"- Preserved effective unresolved: {blockers['asset_effective_unresolved_targets']} targets / "
        f"{blockers['asset_effective_unresolved_edges']} edges\n\n"
        "This hash-locked `SOURCE_DERIVED` diagnostic executes no legacy binary and proves no runtime parity. "
        "It makes no selection, disposition, repair, recovery application, or authority change; G2-06 and P3 remain blocked.\n")
    evidence = {"schema_version": 1, "evidence_revision": "P2-20A.13",
        "captured_utc": report["captured_utc"], "result": "BLOCKED",
        "review_execution_result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
        "g2_06_satisfied": False, "p3_authorized": False, "measured": measured,
        "report": output_binding(report_path, REPORT_PATH, True),
        "report_markdown": output_binding(markdown_path, MARKDOWN_PATH, True),
        "outputs": {"detail_export": report["detail_export"],
                    "effective_recovery_plan": report["effective_recovery_plan"]},
        "contracts": report["contracts"], "implementation": implementation_evidence(root),
        "builder": {"image_reference": args.builder_reference, "image_id": args.builder_id,
                    "user": "tmxy"},
        "isolation": {"network": "none", "read_only_container": True, "cap_drop": "ALL",
            "no_new_privileges": True, "repository_mount": "read-only",
            "legacy_asset_mount": "read-only", "legacy_source_mounts": "read-only-files"},
        "proof_classification": report["proof_classification"],
        "authority_boundary": authority, "preserved_blockers": context["blockers"],
        "disclosure": report["disclosure"]}
    write_text(Path(args.evidence_output), json_text(evidence))
    return {"result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED", "targets": 6,
        "candidate_edges": 6, "strict_rejected_edges": 6, "prefix_pass_edges": 6,
        "effective_plan_rows": 21, "effective_plan_changed_rows": 6,
        "upstream_effective_phase": phase, "candidate_selections": 0,
        "automatic_resolutions": 0, "authority_state_changed": False,
        "g2_06_satisfied": False, "p3_authorized": False}


def self_test() -> dict[str, Any]:
    assertions = 0
    def check(condition: bool, message: str) -> None:
        nonlocal assertions
        require(condition, message); assertions += 1
    check(candidate_set_sha256(["b" * 64, "a" * 64]) ==
          candidate_set_sha256(["a" * 64, "b" * 64]), "Candidate set ordering is unstable")
    check(candidate_set_sha256(["a" * 64]) != candidate_set_sha256(["b" * 64]),
          "Candidate set is insensitive")
    for value in ("a" * 64, "0" * 64, "0123456789abcdef" * 4):
        check(is_sha256(value), "Valid digest rejected")
    for value in ("A" * 64, "a" * 63, "g" * 64, None):
        check(not is_sha256(value), "Invalid digest accepted")
    candidate = {key: "a" * 64 for key in DETAIL_CANDIDATE_FIELDS if key.endswith("_sha256")}
    candidate.update({"candidate_id": "b" * 64, "strict_binding": "REJECTED",
        "strict_error_code": "payload_size_mismatch", "strict_prefix_binding": "PASS",
        "explicit_prefix_binding": "PASS", "format": "dxt5", "width": 256, "height": 256,
        "stored_mip_count": 1, "declared_mip_count": 1, "effective_mip_count": 1,
        "payload_boundary_mip_count": 7, "maximum_natural_mip_count": 9,
        "input_payload_bytes": 87376, "consumed_payload_bytes": 65536,
        "ignored_payload_bytes": 21840, "decoded_mip_zero_bytes": 262144,
        "dds_header_bytes": 128, "dds_payload_bytes": 65536, "dds_bytes": 65664,
        "dds_declared_mip_count": 1, "dds_payload_prefix_only": True,
        "ignored_tail_excluded_from_dds": True,
        "payload_extent_basis": "declared_mip_payload_prefix_contract",
        "recovery_applied": False, "adapter_applied": False, "content_disposition": "NONE"})
    candidate["dds_payload_sha256"] = candidate["consumed_payload_sha256"]
    sample = {"asset_id": "1" * 64, "family": "qtx", "candidate_count": 1,
        "candidate_set_sha256": candidate_set_sha256([candidate["candidate_id"]]),
        "recovery_kind": "qtx_declared_mip_payload_prefix",
        "basis": "declared_mip_payload_prefix_contract", "source_strict_resolution": "UNRESOLVED",
        "a13_resolution_change": False, "candidate_selected": False,
        "automatic_resolution": False, "authority_state_changed": False, "candidate": candidate}
    validate_detail(sample); assertions += 1
    mutations = [
        ("root", "candidate_selected", True), ("root", "a13_resolution_change", True),
        ("candidate", "recovery_applied", True), ("candidate", "adapter_applied", True),
        ("candidate", "ignored_payload_bytes", 21839),
        ("candidate", "payload_boundary_mip_count", 6), ("candidate", "dds_bytes", 65665),
        ("candidate", "dds_payload_prefix_only", False),
        ("candidate", "dds_payload_sha256", "c" * 64),
    ]
    for where, key, value in mutations:
        changed = json.loads(json.dumps(sample))
        if where == "root": changed[key] = value
        else: changed["candidate"][key] = value
        try: validate_detail(changed)
        except ValueError: assertions += 1
        else: require(False, f"Tampered detail accepted: {key}")
    for where in ("root", "candidate"):
        changed = json.loads(json.dumps(sample))
        target = changed if where == "root" else changed["candidate"]
        target["unknown"] = False
        try: validate_detail(changed)
        except ValueError: assertions += 1
        else: require(False, f"Unknown {where} field accepted")
    check(sha256_text("role\tdigest\n") != sha256_text("role\tdigest2\n"),
          "Aggregate source binding is insensitive")
    check(assertions == 22, "Self-test assertion count drifted")
    return {"result": "PASS", "assertions": assertions}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--self-test", action="store_true")
    sub = result.add_subparsers(dest="command")
    prepare = sub.add_parser("prepare")
    for name in ("root", "asset-tsv", "candidate-tsv", "effective-plan-output"):
        prepare.add_argument(f"--{name}", required=True)
    final = sub.add_parser("finalize")
    for name in ("root", "probe-jsonl", "detail-output", "effective-plan", "json-output",
                 "markdown-output", "evidence-output", "builder-reference", "builder-id"):
        final.add_argument(f"--{name}", required=True)
    final.add_argument("--legacy-source", action="append", default=[])
    final.add_argument("--captured-utc")
    return result


def main() -> None:
    args = parser().parse_args()
    if args.self_test:
        value = self_test()
    elif args.command == "prepare":
        value = prepare_scope_and_plan(Path(args.root).resolve(), Path(args.asset_tsv),
            Path(args.candidate_tsv), Path(args.effective_plan_output))
    elif args.command == "finalize":
        value = finalize(args)
    else:
        raise ValueError("A command or --self-test is required")
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
