#!/usr/bin/env python3
"""Generate closed, anonymous P2-20A.11 malformed-XML diagnostics."""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path
from typing import Any

from aux_malformed_xml_support import (
    EvidenceError, compile_and_run_tinyxml_probes, make_probe_input,
    probe_elementtree, profile_bytes, require, run_self_test, sha256_bytes,
    sha256_file, strict_gbk_decode,
)
from g2_aux_malformed_xml_evidence import (
    AUTHORITY, canonical_identity, derive_outcome_projections, domain_hash,
    independent_elementtree, json_bytes, string_set_hash,
    validate_execution_environment,
)


REVISION = "P2-20A.11"
DETAIL_RELATIVE = "Data/Exports/P2-20/p2-20a-aux-malformed-xml-diagnostics.jsonl"


class ArgumentContractError(Exception):
    pass


class ClosedArgumentParser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        raise ArgumentContractError


INPUTS = {
    "auxiliary_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "a3_report": "Data/Reports/p2-20a-aux-config-reference-report.json",
    "a3_evidence": "Data/Inventory/p2-20a-aux-config-reference-evidence.json",
    "a5_report": "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json",
    "a5_evidence": "Data/Inventory/p2-20a-aux-semantic-diagnostics.json",
    "p2_05_transform_implementation": "Tools/TMXY.Table/New-AuxiliaryConfigInventory.ps1",
    "a3_extract_implementation": "Tools/TMXY.G2AuxConfigClosure/aux_extract_runner.py",
    "a5_diagnostic_implementation": "Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_diagnostics.py",
    "policy": "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-policy-v1.json",
    "schema": "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-v1.schema.json",
    "detail_schema": "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-detail-v1.schema.json",
    "generator": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_diagnostics.py",
    "support": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/aux_malformed_xml_support.py",
    "tinyxml_probe": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/tinyxml_probe.cpp",
    "evidence_helper": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_evidence.py",
    "wrapper": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/New-G2AuxMalformedXmlDiagnostics.ps1",
    "toolchain_lock": "Data/Toolchain/toolchain.lock.json",
}
LEGACY = {
    "client_tinyxml_header": ("client", "tinyxml/tinyxml.h"),
    "client_tinyxml_loader": ("client", "tinyxml/tinyxml.cpp"),
    "client_tinyxml_parser": ("client", "tinyxml/tinyxmlparser.cpp"),
    "client_tinyxml_error": ("client", "tinyxml/tinyxmlerror.cpp"),
    "client_tinystr_implementation": ("client", "tinyxml/tinystr.cpp"),
    "client_tinystr_header": ("client", "tinyxml/tinystr.h"),
    "server_tinyxml_header": ("server", "tinyxml/tinyxml.h"),
    "server_tinyxml_loader": ("server", "tinyxml/tinyxml.cpp"),
    "server_tinyxml_parser": ("server", "tinyxml/tinyxmlparser.cpp"),
    "server_tinyxml_error": ("server", "tinyxml/tinyxmlerror.cpp"),
    "server_tinystr_implementation": ("server", "tinyxml/tinystr.cpp"),
    "server_tinystr_header": ("server", "tinyxml/tinystr.h"),
    "client_xml_load_macro": ("client", "Game/Hdr/GamePrivate.h"),
    "client_region_consumer": ("client", "Game/Src/QRegionMgr.cpp"),
    "client_file_reader": ("client", "Base/Src/Base.cpp"),
    "client_array_contract": ("client", "Base/Hdr/QArray.h"),
    "server_box_consumer": ("server", "GameServer/QPBoxItem.cpp"),
    "server_character_consumer": ("server", "GameServer/QPlayerCharInfo.cpp"),
    "server_guild_consumer": ("server", "ServerCommon/GuildCommonInfo.cpp"),
    "server_profession_consumer": ("server", "GameServer/QProfessionInfo.cpp"),
}


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), "JSON input is not an object")
    return value


def write_output(path: Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)


def resolve_file(root: Path, relative: object, label: str) -> Path:
    require(isinstance(relative, str) and relative and "\\" not in relative and
            "\x00" not in relative, f"{label} path is not portable")
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts,
            f"{label} path escaped its root")
    resolved_root = root.resolve(strict=True)
    resolved = (resolved_root / candidate).resolve(strict=True)
    require(resolved.is_file() and resolved.is_relative_to(resolved_root),
            f"{label} path escaped its root")
    return resolved


def validate_upstream(root: Path, docs: dict[str, dict[str, Any]],
                      policy: dict[str, Any]) -> None:
    inventory, a3, a5 = (docs[name] for name in
                          ("auxiliary_inventory", "a3_report", "a5_report"))
    require(inventory.get("task") == "P2-05" and inventory.get("result") == "PASS" and
            inventory.get("completion_criteria_satisfied") is True and
            inventory.get("summary", {}).get("xml", {}).get("malformed_isolated") == 6,
            "frozen P2-05 baseline drifted")
    require(a3.get("evidence_revision") == "P2-20A.3" and
            a3.get("result") == "BLOCKED" and a3.get("review_execution_result") == "PASS" and
            a3.get("g2_06_satisfied") is False, "P2-20A.3 state drifted")
    require(a5.get("evidence_revision") == "P2-20A.5" and
            a5.get("result") == "BLOCKED" and a5.get("review_execution_result") == "PASS" and
            a5.get("g2_06_satisfied") is False and
            a5.get("measured", {}).get("malformed_instances") == 6 and
            a5.get("parser_and_consumer_controls", {}).get("malformed_auto_fix") is False,
            "P2-20A.5 malformed boundary drifted")
    for report_role, evidence_role, nested in (
        ("a3_report", "a3_evidence", True), ("a5_report", "a5_evidence", False)):
        evidence = docs[evidence_role]
        binding = (evidence.get("outputs", {}).get("report_json") if nested
                   else evidence.get("report_json"))
        require(isinstance(binding, dict) and
                binding.get("sha256") == sha256_file(root / INPUTS[report_role]),
                f"{report_role} cross-binding drifted")
    baseline = policy["implementation_baseline"]
    for role in ("p2_05_transform_implementation", "a3_extract_implementation",
                 "a5_diagnostic_implementation"):
        require(sha256_file(root / INPUTS[role]) == baseline[f"{role}_sha256"],
                f"{role} baseline drifted")


def input_bindings(root: Path, policy: dict[str, Any], client: Path,
                   server: Path) -> dict[str, Any]:
    entries = [{"role": role, "sha256": sha256_file(root / relative)}
               for role, relative in INPUTS.items()]
    roots = {"client": client, "server": server}
    legacy = []
    for role, (family, relative) in LEGACY.items():
        digest = sha256_file(resolve_file(roots[family], relative, role))
        require(digest == policy["legacy_source_bindings"][role],
                f"{role} source binding drifted")
        legacy.append({"role": role, "sha256": digest})
    roles = [item["role"] for item in entries]
    require(roles == policy["required_input_roles"], "required input roles drifted")
    aggregate = string_set_hash(
        f"{item['role']}:{item['sha256']}" for item in (*entries, *legacy))
    return {"aggregate_sha256": aggregate, "entries": entries,
            "legacy_sources": legacy}


def scan(root: Path, client: Path, server: Path, work: Path,
         docs: dict[str, dict[str, Any]], policy: dict[str, Any]
         ) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    inventory = docs["auxiliary_inventory"]
    sandbox = resolve_file(root, inventory["source"]["sandbox_relative_path"] + "/QY.exe",
                           "P2-05 sandbox anchor").parent
    files = {canonical_identity(item["path"]): item for item in inventory["files"]}
    isolated = inventory.get("malformed_xml_isolation", [])
    require(isinstance(isolated, list) and len(isolated) == 6, "malformed set drifted")
    staged = []
    for item in isolated:
        canonical = canonical_identity(item["path"])
        entry = files.get(canonical)
        require(isinstance(entry, dict) and entry.get("kind") == "xml", "malformed member absent")
        raw_path = resolve_file(sandbox, entry["path"], "malformed XML")
        raw = raw_path.read_bytes()
        require(len(raw) == entry["bytes"] and sha256_bytes(raw) == entry["sha256"],
                "malformed content binding drifted")
        instance = domain_hash("g2-aux-source-file-v1", canonical, entry["sha256"])
        member = domain_hash("g2-aux-malformed-xml-diagnostic-member-v1",
                             canonical, entry["sha256"])
        staged.append((member, instance, entry, raw_path, raw))
    staged.sort(key=lambda value: value[0])
    probe_inputs = [make_probe_input(sandbox, item[2]["path"], index)
                    for index, item in enumerate(staged)]
    probes = compile_and_run_tinyxml_probes(
        root / INPUTS["tinyxml_probe"], client / "tinyxml", server / "tinyxml",
        probe_inputs, work_root=work)
    client_records = {item["member"]: item for item in probes["records"]
                      if item["family"] == "client"}
    server_records = {item["member"]: item for item in probes["records"]
                      if item["family"] == "server"}
    details, strict_rows = [], []
    profile_totals = collections.Counter()
    class_counts, error_codes = collections.Counter(), collections.Counter()
    for index, (member, instance, entry, _path, raw) in enumerate(staged):
        profile = profile_bytes(raw)
        require(profile["gbk_strict_decodable"] and profile["lone_lf"] == 0 and
                profile["lone_cr"] == 0 and profile["nul"] == 0 and
                profile["dtd_declaration_detected"] is False and
                profile["entity_declaration_detected"] is False,
                "malformed encoding or declaration boundary drifted")
        profile_totals.update({"bytes": profile["bytes"], "gbk": 1,
                               "crlf_only": 1, "crlf": profile["crlf"],
                               "nul_instances": int(profile["nul"] > 0),
                               "doctype_instances": int(profile["dtd_declaration_detected"]),
                               "entity_instances": int(profile["entity_declaration_detected"])})
        structure = entry["structure"]
        error = structure["error"]
        require(structure.get("classification") == "malformed-xml" and
                structure.get("accepted_by_strict_reader") is False and
                structure.get("document_conformance") is False and
                structure.get("fragment_conformance") is False and
                error == isolated[[canonical_identity(x["path"]) for x in isolated].index(
                    canonical_identity(entry["path"]))]["error"],
                "P2-05 strict member drifted")
        class_counts[error] += 1
        elementtree = independent_elementtree(strict_gbk_decode(raw),
                                               probe_elementtree(strict_gbk_decode(raw)))
        error_codes[str(elementtree["error_code"])] += 1
        left, right = client_records[index], server_records[index]
        require({key: value for key, value in left.items() if key != "family"} ==
                {key: value for key, value in right.items() if key != "family"},
                "TinyXML family outcomes diverged")
        require(left["content_sha256"] == entry["sha256"] and
                left["load_file_success"] and not left["load_file_error_flag"] and
                left["load_file_root_present"] and not left["direct_parse_error_flag"] and
                left["direct_parse_root_present"], "TinyXML API boundary drifted")
        role = entry["ownership"]["role"]
        if role == "client-region-runtime-data":
            consumer, termination = ("dynamic-client-source-bound",
                                      "unproven-client-qarray-tail")
        elif entry["ownership"].get("server_reference") is True:
            consumer, termination = ("literal-server-source-bound",
                                      "server-load-file-c-str")
        else:
            consumer, termination = ("unresolved-no-source-literal", "unresolved-consumer")
        detail = {
            "schema_version": 1, "record": "malformed_xml_diagnostic",
            "closed_record": True, "member_id": member, "instance_sha256": instance,
            "content_sha256": entry["sha256"], "source_bytes": len(raw),
            "source_role": role,
            "p2_05_strict": {"classification": "malformed-xml",
                             "document_conformance": False,
                             "fragment_conformance": False,
                             "error_category": error},
            "elementtree": elementtree,
            "source_derived_tinyxml": {
                "version": "2.3.4", "probe_input_nul_appended": True,
                "client_load_file_success": left["load_file_success"],
                "server_load_file_success": right["load_file_success"],
                "client_error_flag": left["load_file_error_flag"],
                "server_error_flag": right["load_file_error_flag"],
                "client_root_present": left["load_file_root_present"],
                "server_root_present": right["load_file_root_present"],
                "direct_parse_returned_null": left["direct_parse_returned_null"],
                "full_input_consumed": left["full_input_consumed"],
                "client_server_tree_shape_equal": True,
                "tree_shape": {field: left[field] for field in
                               ("nodes", "elements", "attributes", "texts", "comments")}},
            "consumer_binding_state": consumer,
            "consumer_input_termination_state": termination,
            "authority": dict(AUTHORITY),
        }
        details.append(detail)
        strict_rows.append({"instance_sha256": instance, "content_sha256": entry["sha256"],
                            "bytes": len(raw), "encoding": "gbk", "source_role": role,
                            "diagnostic_class": error, "document_conformance": False,
                            "fragment_conformance": False})
    expected = policy["expected_population"]
    population = {
        "instances": len(details), "unique_contents": len({x["content_sha256"] for x in details}),
        "source_bytes": profile_totals["bytes"], "gbk_instances": profile_totals["gbk"],
        "crlf_only_instances": profile_totals["crlf_only"], "crlf_pairs": profile_totals["crlf"],
        "lone_lf": 0, "lone_cr": 0, "nul_instances": profile_totals["nul_instances"],
        "doctype_instances": profile_totals["doctype_instances"],
        "entity_instances": profile_totals["entity_instances"],
        "instance_set_sha256": string_set_hash(x["instance_sha256"] for x in details),
        "content_set_sha256": string_set_hash(x["content_sha256"] for x in details),
    }
    require(population == expected,
            f"malformed population aggregate drifted: {population!r}")
    strict_blob = b"".join(json_bytes(row, compact=True)
                           for row in sorted(strict_rows, key=lambda row: row["instance_sha256"]))
    strict_digest = sha256_bytes(strict_blob)
    require(strict_digest == policy["expected_p2_05_strict"]["strict_baseline_sha256"],
            f"strict baseline outcome hash drifted: {len(strict_blob)}:{strict_digest}")
    require(dict(class_counts) == policy["expected_p2_05_strict"]["classifications"] and
            dict(error_codes) == policy["expected_elementtree"]["error_codes"],
            "strict or ElementTree distribution drifted")
    return population, details, probes


def markdown(report: dict[str, Any]) -> bytes:
    text = f"""# G2 malformed XML diagnostic\n\nP2-20A.11 is `BLOCKED / PASS / BLOCKED`. It diagnoses all six frozen P2-05 malformed XML instances without repairing, deleting, normalizing, importing, or approving them.\n\n## Separated evidence layers\n\n- Frozen P2-05 strict .NET evidence rejects 6/6 as documents and 6/6 as fragments.\n- Independent GBK-to-Unicode ElementTree evidence rejects 6/6: error code 4 occurs five times and code 9 once.\n- Source-built Client and Server TinyXML 2.3.4 both report LoadFile success, no error, and a root for 6/6; both tree shapes agree.\n- Direct Parse consumes the full input for 5/6. One API-success instance returns null while retaining a partial tree of 132 elements and 529 attributes.\n\n## Authority boundary\n\nLoadFile success is not a disposition. No legacy binary or runtime was executed; binary, Windows CRT text-mode, client C-string termination, and memory-tail parity remain unproven. Repairs, writes, deletions, semantic imports, adapters, no-reference approvals, roots, and terminal dispositions remain zero. G2 remains 7/9 and P3 remains unauthorized.\n\nThe tracked artifacts contain aggregates and hashes only. The ignored detail contains six closed anonymous records and no file names, paths, XML names, values, snippets, or raw parser locations.\n"""
    return text.encode("utf-8")


def generate(args: argparse.Namespace) -> dict[str, Any]:
    require(args.verify_derived_sources, "source-derived verification is mandatory")
    root, client, server, work = (Path(args.root).resolve(strict=True),
                                  Path(args.client_source_root).resolve(strict=True),
                                  Path(args.server_source_root).resolve(strict=True),
                                  Path(args.work_root).resolve(strict=True))
    docs = {role: load_json(root / relative) for role, relative in INPUTS.items()
            if role in {"auxiliary_inventory", "a3_report", "a3_evidence",
                        "a5_report", "a5_evidence", "policy", "toolchain_lock"}}
    policy = docs["policy"]
    validate_upstream(root, docs, policy)
    bindings = input_bindings(root, policy, client, server)
    population, details, probes = scan(root, client, server, work, docs, policy)
    outcomes = derive_outcome_projections(details, probes)
    require(outcomes["elementtree"] ==
            policy["expected_elementtree"]["outcome_projection"] and
            outcomes["tinyxml_api_and_completeness"] ==
            policy["expected_source_derived_tinyxml"]["api_and_completeness_projection"] and
            outcomes["tinyxml_tree"] ==
            policy["expected_source_derived_tinyxml"]["tree_projection"],
            "versioned outcome projection drifted")
    environment, evidence_boundary = validate_execution_environment(
        docs["toolchain_lock"], args, probes,
        sha256_file(root / INPUTS["toolchain_lock"]),
        sha256_file(root / INPUTS["wrapper"]))
    require(environment == policy["expected_execution_environment"] and
            evidence_boundary == policy["expected_evidence_boundary"],
            "execution environment evidence drifted")
    detail_bytes = b"".join(json_bytes(item, compact=True) for item in details)
    detail_binding = {"tracked": False, "path": DETAIL_RELATIVE, "lines": len(details),
                      "bytes": len(detail_bytes), "sha256": sha256_bytes(detail_bytes)}
    require(detail_binding["lines"] == policy["expected_detail"]["lines"] and
            detail_binding["sha256"] == policy["expected_detail"]["sha256"],
            f"anonymous detail hash drifted: {detail_binding['bytes']}:{detail_binding['sha256']}")
    write_output(Path(args.detail_output), detail_bytes)
    tiny = policy["expected_source_derived_tinyxml"]
    authority = policy["authority_controls"]
    metrics = {
        "aux_malformed_xml_diagnostic_hash_bound": True,
        "aux_malformed_xml_instances": 6,
        "aux_malformed_xml_strict_document_rejections": 6,
        "aux_malformed_xml_strict_fragment_rejections": 6,
        "aux_malformed_xml_elementtree_rejections": 6,
        "aux_malformed_xml_tinyxml_api_successes": 6,
        "aux_malformed_xml_tinyxml_full_consumption": 5,
        "aux_malformed_xml_tinyxml_silent_partial": 1,
        "aux_malformed_xml_consumer_bound": 5,
        "aux_malformed_xml_consumer_unresolved": 1,
        "aux_malformed_xml_client_input_termination_proven": False,
        "aux_malformed_xml_legacy_runtime_executed": False,
        "aux_malformed_xml_runtime_binary_parity_claimed": False,
        "aux_malformed_xml_repairs": 0, "aux_malformed_xml_deletions": 0,
        "aux_malformed_xml_semantic_imports_claimed": 0,
        "aux_malformed_xml_terminal_dispositions": 0,
    }
    report = {
        "schema_version": 1, "evidence_revision": REVISION,
        "captured_utc": docs["a5_report"]["captured_utc"], "task_id": "P2-20A",
        "criterion_id": "G2-06", "source_build": "qy-3.0.0.413", "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "input_bindings": bindings, "population": population,
        "p2_05_strict": {"evidence_revision": "P2-05", "frozen_baseline": True,
                          **policy["expected_p2_05_strict"]},
        "independent_elementtree": {
            "implementation": "python-xml.etree.ElementTree",
            "decode_boundary": "strict-gbk-to-unicode", "dtd_enabled": False,
            "external_resolver_enabled": False,
            "accepted": 0, "rejected": 6,
            "error_codes": policy["expected_elementtree"]["error_codes"],
            "outcome_projection": outcomes["elementtree"],
            "outcome_sha256": outcomes["elementtree"]["sha256"]},
        "source_derived_tinyxml": {
            "derivation_scope": "SOURCE_DERIVED_DIAGNOSTIC_ONLY", "version": tiny["version"],
            "source_families": tiny["source_families"],
            "instances_per_family": tiny["instances_per_family"],
            "probe_input_nul_appended": True,
            "api_acceptance": {
                "client_load_file_successes": tiny["client_load_file_successes"],
                "server_load_file_successes": tiny["server_load_file_successes"],
                "client_error_false": tiny["client_error_false"],
                "server_error_false": tiny["server_error_false"],
                "client_roots_present": tiny["client_roots_present"],
                "server_roots_present": tiny["server_roots_present"],
                "client_server_tree_shape_equal": tiny["client_server_tree_shape_equal"],
                "accepted_as_terminal_disposition": False},
            "parse_completeness": {
                "full_input_consumed": tiny["direct_parse_full_input_consumed"],
                "direct_parse_returned_null": tiny["direct_parse_returned_null"],
                "silent_partial_instances": tiny["silent_partial_instances"],
                "partial_content_sha256": tiny["partial_content_sha256"],
                "partial_elements": tiny["partial_elements"],
                "partial_attributes": tiny["partial_attributes"]},
            "tree_totals": tiny["tree_totals"],
            "api_and_completeness_projection": outcomes["tinyxml_api_and_completeness"],
            "api_and_completeness_outcome_sha256":
                outcomes["tinyxml_api_and_completeness"]["sha256"],
            "tree_projection": outcomes["tinyxml_tree"],
            "tree_outcome_sha256": outcomes["tinyxml_tree"]["sha256"],
            "execution_environment": environment,
            "evidence_boundary": evidence_boundary},
        "consumer_boundary": policy["expected_consumer_boundary"],
        "authority_boundaries": authority, "blockers": policy["blockers"],
        "negative_contracts": policy["negative_contracts"], "detail_export": detail_binding,
        "g2_projection": {**policy["g2_projection"], "g2_06_satisfied": False,
                          "metrics": metrics},
        "contracts": {"policy_sha256": sha256_file(root / INPUTS["policy"]),
                      "schema_sha256": sha256_file(root / INPUTS["schema"]),
                      "detail_schema_sha256": sha256_file(root / INPUTS["detail_schema"])},
        "disclosure": policy["disclosure"],
    }
    report_bytes, markdown_bytes = json_bytes(report), markdown(report)
    write_output(Path(args.json_output), report_bytes)
    write_output(Path(args.markdown_output), markdown_bytes)
    self_test = run_self_test()
    evidence = {
        "schema_version": 1, "evidence_revision": REVISION,
        "captured_utc": report["captured_utc"], "task_id": "P2-20A", "criterion_id": "G2-06",
        "result": "BLOCKED", "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "report_json": {"bytes": len(report_bytes), "sha256": sha256_bytes(report_bytes)},
        "report_markdown": {"bytes": len(markdown_bytes), "sha256": sha256_bytes(markdown_bytes)},
        "detail_export": detail_binding, "population": population,
        "layer_outcomes": {"p2_05_document_rejections": 6,
                           "p2_05_fragment_rejections": 6,
                           "elementtree_rejections": 6, "tinyxml_api_successes": 6,
                           "tinyxml_full_consumption": 5, "tinyxml_silent_partial": 1},
        "consumer_boundary": policy["expected_consumer_boundary"],
        "authority_boundaries": authority, "blockers": policy["blockers"],
        "contracts": report["contracts"],
        "implementation": {"generator_sha256": sha256_file(root / INPUTS["generator"]),
                           "support_sha256": sha256_file(root / INPUTS["support"]),
                           "probe_sha256": sha256_file(root / INPUTS["tinyxml_probe"]),
                           "evidence_helper_sha256": sha256_file(
                               root / INPUTS["evidence_helper"]),
                           "self_test_assertions": self_test["assertions"]},
        "source_verification": {
            "performed": True, "source_families": 2, **environment,
            "evidence_boundary": evidence_boundary,
            "elementtree_outcome_sha256": outcomes["elementtree"]["sha256"],
            "tinyxml_api_and_completeness_outcome_sha256":
                outcomes["tinyxml_api_and_completeness"]["sha256"],
            "tinyxml_tree_outcome_sha256": outcomes["tinyxml_tree"]["sha256"],
            "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False},
        "isolation": {"network": environment["network"],
                      "repository_mount": environment["repository_mount"],
                      "client_legacy_mount": environment["client_legacy_mount"],
                      "server_legacy_mount": environment["server_legacy_mount"],
                      "builder_user": environment["builder_user"],
                      "capabilities": environment["capabilities"],
                      "no_new_privileges": environment["no_new_privileges"]},
        "disclosure": policy["disclosure"],
    }
    write_output(Path(args.evidence_output), json_bytes(evidence))
    return {"result": "BLOCKED", "review_execution_result": "PASS",
            "instances": 6, "strict_rejections": 6, "elementtree_rejections": 6,
            "tinyxml_api_successes": 6, "tinyxml_full_consumption": 5,
            "tinyxml_silent_partial": 1, "detail_sha256": detail_binding["sha256"],
            "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False}


def parse_args() -> argparse.Namespace:
    parser = ClosedArgumentParser(prog="g2-a11-malformed-xml-diagnostics")
    parser.add_argument("--root", required=True)
    parser.add_argument("--client-source-root", required=True)
    parser.add_argument("--server-source-root", required=True)
    parser.add_argument("--work-root", required=True)
    parser.add_argument("--builder-image-reference", required=True)
    parser.add_argument("--builder-image-digest", required=True)
    parser.add_argument("--network-mode", required=True)
    parser.add_argument("--repository-mount-mode", required=True)
    parser.add_argument("--client-legacy-mount-mode", required=True)
    parser.add_argument("--server-legacy-mount-mode", required=True)
    parser.add_argument("--builder-user", required=True)
    parser.add_argument("--capabilities", required=True)
    parser.add_argument("--no-new-privileges", required=True)
    parser.add_argument("--detail-output", required=True)
    parser.add_argument("--json-output", required=True)
    parser.add_argument("--markdown-output", required=True)
    parser.add_argument("--evidence-output", required=True)
    parser.add_argument("--verify-derived-sources", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    try:
        print(json.dumps(generate(parse_args()), sort_keys=True))
    except ArgumentContractError:
        print('{"error_code":"A11_ARGUMENT_VALIDATION_FAILED","result":"ERROR"}',
              file=sys.stderr)
        raise SystemExit(1)
    except EvidenceError:
        print('{"error_code":"A11_EVIDENCE_CONTRACT_FAILED","result":"ERROR"}',
              file=sys.stderr)
        raise SystemExit(1)
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, json.JSONDecodeError):
        print('{"error_code":"A11_INPUT_OR_IO_FAILED","result":"ERROR"}', file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        print('{"error_code":"A11_INTERNAL_FAILURE","result":"ERROR"}', file=sys.stderr)
        raise SystemExit(1)
