"""Versioned projections and build provenance for P2-20A.11 evidence."""

from __future__ import annotations

import hashlib
import json
import xml.etree.ElementTree as ET
from typing import Any, Iterable, Mapping, Sequence

from aux_malformed_xml_support import EvidenceError, require, sha256_bytes


AUTHORITY = {
    "source_derived_probe_is_runtime_execution": False,
    "legacy_runtime_executed": False,
    "runtime_binary_parity_claimed": False,
    "windows_crt_text_mode_runtime_parity_claimed": False,
    "runtime_input_tail_observed": False,
    "semantic_values_extracted": 0,
    "semantic_imports_claimed": 0,
    "repair_applied": 0,
    "deletion_authorized": 0,
    "approved_adapter": 0,
    "no_ref_approved": 0,
    "approved_root": 0,
    "terminal_disposition_approved": 0,
}
EVIDENCE_BOUNDARY = {
    "source_derived_only": True,
    "legacy_binary_executed": False,
    "runtime_parity_claimed": False,
    "windows_crt_parity_claimed": False,
    "null_tail_parity_claimed": False,
    "probe_input_nul_appended": True,
    "client_input_null_termination_proven": False,
    "runtime_memory_tail_observed": False,
    "api_success_grants_disposition": False,
}
SERIALIZATION = "utf-8-json-sort-keys-compact-lf"
PROJECTIONS = {
    "elementtree": (
        "g2-a11-elementtree-outcome-v1",
        ("projection_version", "member_id", "accepted", "error_code",
         "error_class_code", "failure_location_sha256"),
    ),
    "tinyxml_api_and_completeness": (
        "g2-a11-tinyxml-api-completeness-outcome-v1",
        ("projection_version", "member_id", "probe_input_nul_appended",
         "client_load_file_success", "server_load_file_success",
         "client_error_flag", "server_error_flag", "client_root_present",
         "server_root_present", "direct_parse_returned_null",
         "full_input_consumed", "client_server_tree_shape_equal"),
    ),
    "tinyxml_tree": (
        "g2-a11-tinyxml-tree-outcome-v1",
        ("projection_version", "member_id", "nodes", "elements",
         "attributes", "texts", "comments"),
    ),
}


def json_bytes(value: Any, compact: bool = False) -> bytes:
    separators = (",", ":") if compact else None
    return (json.dumps(value, ensure_ascii=False, sort_keys=compact,
                       indent=None if compact else 2,
                       separators=separators) + "\n").encode("utf-8")


def canonical_identity(value: str) -> str:
    return "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch
                   for ch in value.strip().replace("\\", "/"))


def domain_hash(domain: str, *parts: str) -> str:
    digest = hashlib.sha256()
    for part in (domain, *parts):
        raw = part.encode("utf-8", errors="strict")
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def string_set_hash(values: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for value in sorted(set(values)):
        digest.update((json.dumps(value, ensure_ascii=True,
                                  separators=(",", ":")) + "\n").encode("ascii"))
    return digest.hexdigest()


def independent_elementtree(text: str, support_result: Mapping[str, Any]) -> dict[str, Any]:
    require(support_result.get("accepted") is False and
            support_result.get("error_code") in {4, 9},
            "ElementTree support outcome drifted")
    try:
        ET.fromstring(text)
    except ET.ParseError as error:
        line, column = error.position
        code = int(error.code)
    else:
        raise EvidenceError("independent ElementTree accepted malformed XML")
    require(code == support_result["error_code"], "ElementTree ports disagreed")
    names = {4: "INVALID_TOKEN", 9: "JUNK_AFTER_DOCUMENT_ELEMENT"}
    return {"accepted": False, "error_code": code, "error_class_code": names[code],
            "failure_location_sha256": domain_hash(
                "g2-aux-malformed-elementtree-location-v1", str(line), str(column))}


def _projection(name: str, rows: Sequence[dict[str, Any]]) -> dict[str, Any]:
    version, fields = PROJECTIONS[name]
    require(len(rows) == 6 and all(tuple(row) == fields for row in rows),
            f"{name} projection fields drifted")
    blob = b"".join(json_bytes(row, compact=True) for row in rows)
    return {"version": version, "serialization": SERIALIZATION,
            "record_order": "member_id-ascending", "fields": list(fields),
            "rows": len(rows), "bytes": len(blob), "sha256": sha256_bytes(blob)}


def derive_outcome_projections(details: Sequence[dict[str, Any]],
                               probes: Mapping[str, Any]) -> dict[str, Any]:
    ordered = sorted(details, key=lambda row: row["member_id"])
    require(list(details) == ordered and len(ordered) == 6,
            "detail projection order drifted")
    client = {row["member"]: row for row in probes["records"]
              if row["family"] == "client"}
    server = {row["member"]: row for row in probes["records"]
              if row["family"] == "server"}
    et_rows, api_rows, tree_rows = [], [], []
    for member, detail in enumerate(ordered):
        left, right = client[member], server[member]
        tiny, tree = detail["source_derived_tinyxml"], detail["source_derived_tinyxml"]["tree_shape"]
        require(left["content_sha256"] == right["content_sha256"] == detail["content_sha256"] and
                tiny["client_load_file_success"] == left["load_file_success"] and
                tiny["server_load_file_success"] == right["load_file_success"] and
                tiny["client_error_flag"] == left["load_file_error_flag"] and
                tiny["server_error_flag"] == right["load_file_error_flag"] and
                tiny["full_input_consumed"] == left["full_input_consumed"] and
                all(tree[field] == left[field] == right[field]
                    for field in ("nodes", "elements", "attributes", "texts", "comments")),
                "detail and probe projections diverged")
        et = detail["elementtree"]
        et_rows.append({
            "projection_version": PROJECTIONS["elementtree"][0],
            "member_id": detail["member_id"], "accepted": et["accepted"],
            "error_code": et["error_code"], "error_class_code": et["error_class_code"],
            "failure_location_sha256": et["failure_location_sha256"]})
        api_rows.append({
            "projection_version": PROJECTIONS["tinyxml_api_and_completeness"][0],
            "member_id": detail["member_id"], "probe_input_nul_appended": left["probe_input_nul_appended"],
            "client_load_file_success": left["load_file_success"],
            "server_load_file_success": right["load_file_success"],
            "client_error_flag": left["load_file_error_flag"],
            "server_error_flag": right["load_file_error_flag"],
            "client_root_present": left["load_file_root_present"],
            "server_root_present": right["load_file_root_present"],
            "direct_parse_returned_null": left["direct_parse_returned_null"],
            "full_input_consumed": left["full_input_consumed"],
            "client_server_tree_shape_equal": True})
        tree_rows.append({
            "projection_version": PROJECTIONS["tinyxml_tree"][0],
            "member_id": detail["member_id"], **{field: left[field] for field in
                ("nodes", "elements", "attributes", "texts", "comments")}})
    return {"elementtree": _projection("elementtree", et_rows),
            "tinyxml_api_and_completeness": _projection(
                "tinyxml_api_and_completeness", api_rows),
            "tinyxml_tree": _projection("tinyxml_tree", tree_rows)}


def validate_execution_environment(lock: Mapping[str, Any], args: Any,
                                   probes: Mapping[str, Any], lock_sha256: str,
                                   wrapper_sha256: str) -> tuple[dict[str, Any], dict[str, Any]]:
    backend = lock.get("backend_toolchain", {})
    require(args.builder_image_reference == backend.get("container_image_reference") and
            args.builder_image_digest == backend.get("container_image_digest"),
            "wrapper image arguments do not match the toolchain lock")
    expected_args = {"network_mode": "none", "repository_mount_mode": "read-only",
                     "client_legacy_mount_mode": "read-only",
                     "server_legacy_mount_mode": "read-only", "builder_user": "tmxy",
                     "capabilities": "none", "no_new_privileges": "true"}
    require(all(getattr(args, key) == value for key, value in expected_args.items()),
            "wrapper isolation arguments drifted")
    boundary = probes.get("evidence_boundary")
    require(boundary == EVIDENCE_BOUNDARY, "probe evidence boundary drifted")
    compiler = probes["compiler"]
    require(compiler["executable"] == "clang++-21" and compiler["major"] == 21,
            "compiler identity drifted")
    environment = {
        "builder_image_reference": args.builder_image_reference,
        "builder_image_digest": args.builder_image_digest,
        "toolchain_lock_sha256": lock_sha256, "wrapper_sha256": wrapper_sha256,
        "compiler_executable": compiler["executable"], "compiler_major": compiler["major"],
        "compiler_version_output_sha256": compiler["version_output_sha256"],
        "client_source_set_sha256": probes["source_bindings"]["client"]["source_set_sha256"],
        "server_source_set_sha256": probes["source_bindings"]["server"]["source_set_sha256"],
        "network": args.network_mode, "repository_mount": args.repository_mount_mode,
        "client_legacy_mount": args.client_legacy_mount_mode,
        "server_legacy_mount": args.server_legacy_mount_mode,
        "builder_user": args.builder_user, "capabilities": args.capabilities,
        "no_new_privileges": args.no_new_privileges == "true",
    }
    return environment, dict(boundary)
