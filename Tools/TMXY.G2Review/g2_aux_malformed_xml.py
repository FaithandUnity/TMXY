"""P2-20A.11 malformed-XML diagnostic binding for the G2 review."""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any, Callable


REVISION = "P2-20A.11"
REPORT_PATH = "Data/Reports/p2-20a-aux-malformed-xml-diagnostics-report.json"
DETAIL_PATH = "Data/Exports/P2-20/p2-20a-aux-malformed-xml-diagnostics.jsonl"
POLICY_PATH = "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-policy-v1.json"
SCHEMA_PATH = "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-v1.schema.json"
DETAIL_SCHEMA_PATH = (
    "Contracts/data-schema/g2-aux-malformed-xml-diagnostics-detail-v1.schema.json")
INPUT_PATHS = {
    "auxiliary_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "a3_report": "Data/Reports/p2-20a-aux-config-reference-report.json",
    "a3_evidence": "Data/Inventory/p2-20a-aux-config-reference-evidence.json",
    "a5_report": "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json",
    "a5_evidence": "Data/Inventory/p2-20a-aux-semantic-diagnostics.json",
    "p2_05_transform_implementation": "Tools/TMXY.Table/New-AuxiliaryConfigInventory.ps1",
    "a3_extract_implementation": "Tools/TMXY.G2AuxConfigClosure/aux_extract_runner.py",
    "a5_diagnostic_implementation": (
        "Tools/TMXY.G2AuxSemanticDiagnostics/g2_aux_semantic_diagnostics.py"),
    "policy": POLICY_PATH,
    "schema": SCHEMA_PATH,
    "detail_schema": DETAIL_SCHEMA_PATH,
    "generator": (
        "Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_diagnostics.py"),
    "support": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/aux_malformed_xml_support.py",
    "tinyxml_probe": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/tinyxml_probe.cpp",
    "evidence_helper": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/g2_aux_malformed_xml_evidence.py",
    "wrapper": "Tools/TMXY.G2AuxMalformedXmlDiagnostics/New-G2AuxMalformedXmlDiagnostics.ps1",
    "toolchain_lock": "Data/Toolchain/toolchain.lock.json",
}
TOP_FIELDS = {
    "schema_version", "evidence_revision", "captured_utc", "task_id", "criterion_id",
    "source_build", "result", "review_execution_result", "task_status",
    "completion_criteria_satisfied", "diagnostic_scope_complete", "scope_complete",
    "g2_06_satisfied", "p3_authorized", "input_bindings", "population",
    "p2_05_strict", "independent_elementtree", "source_derived_tinyxml",
    "consumer_boundary", "authority_boundaries", "blockers", "negative_contracts",
    "detail_export", "g2_projection", "contracts", "disclosure",
}
DETAIL_FIELDS = {
    "schema_version", "record", "closed_record", "member_id", "instance_sha256",
    "content_sha256", "source_bytes", "source_role", "p2_05_strict", "elementtree",
    "source_derived_tinyxml", "consumer_binding_state",
    "consumer_input_termination_state", "authority",
}
SHA256 = re.compile(r"[0-9a-f]{64}")
EXPECTED_IMPLEMENTATIONS = {
    "p2_05_transform_implementation_sha256":
        "0e4828ef6eda2f61e2b727ffe2fe2e13b26d668e8083594945cc7b589462797b",
    "a3_extract_implementation_sha256":
        "4482ae73ec1dae12b8e5ea3782bcc4286f1bea21ff230bb96c0e6c2c8186c238",
    "a5_diagnostic_implementation_sha256":
        "2cf825f0105cc720915d6c3420cc46343f4aa1fd91233f907a7ad889525a0d16",
}
EXPECTED_LEGACY_SOURCES = {
    "client_tinyxml_header": "f8d69dc35242d9ba7132203f14122b29fb7b95798f35fc29dc4d63abfcad6d98",
    "client_tinyxml_loader": "30630b58cf6e4c984fa1a692b6daadf95caeb5af444ba729f57a45c89af378fc",
    "client_tinyxml_parser": "c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b",
    "client_tinyxml_error": "d74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef",
    "client_tinystr_implementation": "5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052",
    "client_tinystr_header": "9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412",
    "server_tinyxml_header": "e4ea963af819f872750c278912c51eb0a313895256cfde7774d3a250ce56af44",
    "server_tinyxml_loader": "bd6b363b0b43c9cb059831e04978879f9d8758197e63dd9e0562406c5db96246",
    "server_tinyxml_parser": "c586adaee04634fa0d8f4063f83a7f6fe510cfb70d95401724b692676bc9859b",
    "server_tinyxml_error": "d74ff9be4a320f0933d399799220d2b2f5ff0acc9c40c951aa5694b92b9871ef",
    "server_tinystr_implementation": "5c69220764ca7575abf59e062a1bf40dbc94aa20ab1989a92e5d5d0afbf86052",
    "server_tinystr_header": "9045654e46ea0f1f0fae25b89768e66723fab27754baa6090df4febd732c0412",
    "client_xml_load_macro": "d1478f1e2d20030cee88b11dddc62828bfa426ef58512ef49c4b17e346f7e060",
    "client_region_consumer": "a1e5d33643d633234b2eeb07c6dc9358814d9802d4a9f43c959c1a4b155f1853",
    "client_file_reader": "2541318310e369536f7c13ef1f1486dd1456b57349d703bd2b8fb4d02741ac69",
    "client_array_contract": "831485b5d3392f57c6cb9a832362eb4566111e03b3b9de8225e6f0a09788617a",
    "server_box_consumer": "1c01172da74aefd6ff602c4192e984c3a56b3d4076f80fbb84df526e995bc0e6",
    "server_character_consumer": "79b57221f3d3a976700323e447ffad441b23362e57f87fb804698619ee77cb84",
    "server_guild_consumer": "5b33d8a95c5bbec41e6545c1a708f475f38df4b27839ee0ffbddb72e7e3544c8",
    "server_profession_consumer": "559466f5bc5deb58776b0d8df4e3b0e4273ff96b658c73d1bff685cac570a9b5",
}
EXPECTED_AUTHORITY = {
    "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False,
    "windows_crt_text_mode_runtime_parity_claimed": False, "repair_applied": 0,
    "source_writes": 0, "deletions_authorized": 0, "semantic_values_extracted": 0,
    "semantic_imports_claimed": 0, "approved_adapters": 0,
    "approved_no_reference_instances": 0, "approved_roots": 0,
    "terminal_dispositions": 0,
}
EXPECTED_DETAIL_AUTHORITY = {
    "source_derived_probe_is_runtime_execution": False,
    "legacy_runtime_executed": False, "runtime_binary_parity_claimed": False,
    "windows_crt_text_mode_runtime_parity_claimed": False,
    "runtime_input_tail_observed": False, "semantic_values_extracted": 0,
    "semantic_imports_claimed": 0, "repair_applied": 0, "deletion_authorized": 0,
    "approved_adapter": 0, "no_ref_approved": 0, "approved_root": 0,
    "terminal_disposition_approved": 0,
}
EXPECTED_POPULATION = {
    "instances": 6, "unique_contents": 6, "source_bytes": 1082028,
    "gbk_instances": 6, "crlf_only_instances": 6, "crlf_pairs": 17981,
    "lone_lf": 0, "lone_cr": 0, "nul_instances": 0, "doctype_instances": 0,
    "entity_instances": 0,
    "instance_set_sha256": "effc19aa0fa8ba9cf3ac534aca8bb3e9f07999e363eee5a8c2e7f288df5ee802",
    "content_set_sha256": "17e163f68108f9c471734e7b105415cac5aa75fbd0bd22a3be7364ce54a36268",
}
EXPECTED_ET_PROJECTION = {
    "version": "g2-a11-elementtree-outcome-v1", "serialization": "utf-8-json-sort-keys-compact-lf",
    "record_order": "member_id-ascending", "fields": ["projection_version", "member_id",
        "accepted", "error_code", "error_class_code", "failure_location_sha256"],
    "rows": 6, "bytes": 1778, "sha256": "cf1c56d9f99ff2c379d3ed7640c057c0ceadaa2908ed9aa3d898e591f22a52e6"}
EXPECTED_API_PROJECTION = {
    "version": "g2-a11-tinyxml-api-completeness-outcome-v1",
    "serialization": "utf-8-json-sort-keys-compact-lf", "record_order": "member_id-ascending",
    "fields": ["projection_version", "member_id", "probe_input_nul_appended",
        "client_load_file_success", "server_load_file_success", "client_error_flag",
        "server_error_flag", "client_root_present", "server_root_present",
        "direct_parse_returned_null", "full_input_consumed", "client_server_tree_shape_equal"],
    "rows": 6, "bytes": 2694, "sha256": "2d0e19ea598284a59532082a495c3dd739aae10d69ca4d7be8dd35bf09f61e3f"}
EXPECTED_TREE_PROJECTION = {
    "version": "g2-a11-tinyxml-tree-outcome-v1", "serialization": "utf-8-json-sort-keys-compact-lf",
    "record_order": "member_id-ascending", "fields": ["projection_version", "member_id",
        "nodes", "elements", "attributes", "texts", "comments"], "rows": 6, "bytes": 1222,
    "sha256": "6d1a33ecde5cc3c1de346c02671c8a421c264c1f468db5b4a722881c6a425fcd"}
EXPECTED_ENVIRONMENT = {
    "builder_image_reference": "tmxy-backend-builder:p0-08",
    "builder_image_digest": "sha256:95f30cbb0f406f387a8aa0d4d56323105610ad6fc0629196bc5074847cac90a9",
    "toolchain_lock_sha256": "ce98f28ae229234443039ca9b0881d2e7a9316aea2c2e04b3deb8b691d85a37b",
    "wrapper_sha256": "8619aae715d008d5fe2ad5b05a6d5f3387195e0fb8419a04864c2a566eb11538",
    "compiler_executable": "clang++-21", "compiler_major": 21,
    "compiler_version_output_sha256": "9ded319aa70710f5d9300798de0b09f31a78129fd661a68173fb7d455eb8ef4e",
    "client_source_set_sha256": "0f26c4e1f3630576635bffdba16b03a921ee5921896c12e386cde711d37499c2",
    "server_source_set_sha256": "1056cbb66b3b0f429871422c2d6698f8ca8a7ca75ca379dd7e8b0e6b80e9b575",
    "network": "none", "repository_mount": "read-only", "client_legacy_mount": "read-only",
    "server_legacy_mount": "read-only", "builder_user": "tmxy", "capabilities": "none",
    "no_new_privileges": True}
EXPECTED_BOUNDARY = {
    "source_derived_only": True, "legacy_binary_executed": False,
    "runtime_parity_claimed": False, "windows_crt_parity_claimed": False,
    "null_tail_parity_claimed": False, "probe_input_nul_appended": True,
    "client_input_null_termination_proven": False, "runtime_memory_tail_observed": False,
    "api_success_grants_disposition": False}
EXPECTED_BLOCKERS = [
    {"reason_code": "STRICT_XML_REJECTED", "count": 6},
    {"reason_code": "TINYXML_ACCEPTS_STRICT_INVALID_INPUT", "count": 6},
    {"reason_code": "TINYXML_SILENT_PARTIAL_PARSE", "count": 1},
    {"reason_code": "CONSUMER_BINDING_UNRESOLVED", "count": 1},
    {"reason_code": "CLIENT_XML_CSTRING_TERMINATION_UNPROVEN", "count": 1},
    {"reason_code": "MALFORMED_DISPOSITIONS_PENDING", "count": 6},
    {"reason_code": "LEGACY_RUNTIME_NOT_EXECUTED", "count": 1},
    {"reason_code": "RUNTIME_BINARY_PARITY_UNPROVEN", "count": 1},
]


def _exact(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return (set(left) == set(right) and
                all(_exact(left[key], right[key]) for key in left))
    if isinstance(left, list):
        return len(left) == len(right) and all(
            _exact(a, b) for a, b in zip(left, right, strict=True))
    return left == right


def _set_hash(values: list[str]) -> str:
    digest = hashlib.sha256()
    for value in sorted(set(values)):
        digest.update((json.dumps(value, ensure_ascii=True,
                                  separators=(",", ":")) + "\n").encode("ascii"))
    return digest.hexdigest()


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def _validate_detail(root: Path, report: dict[str, Any],
                     resolve_inside: Callable[[Path, str], Path],
                     sha256: Callable[[Path], str],
                     require: Callable[[bool, str], None]) -> None:
    path = resolve_inside(root, DETAIL_PATH)
    binding = {"tracked": False, "path": DETAIL_PATH, "lines": _line_count(path),
               "bytes": path.stat().st_size, "sha256": sha256(path)}
    require(_exact(report.get("detail_export"), binding) and
            binding["lines"] == 6 and binding["bytes"] == 10097 and
            binding["sha256"] ==
            "cae0c0f2ba3a043315b683097486a0fbfd40cfa7eea210d27d4f4e7c8260dd57",
            "P2-20A.11 anonymous detail binding drifted")
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            require(isinstance(row, dict) and set(row) == DETAIL_FIELDS and
                    row.get("schema_version") == 1 and
                    row.get("record") == "malformed_xml_diagnostic" and
                    row.get("closed_record") is True and
                    all(SHA256.fullmatch(str(row.get(field))) for field in
                        ("member_id", "instance_sha256", "content_sha256")),
                    "P2-20A.11 anonymous detail shape drifted")
            rows.append(row)
    member_ids = [row["member_id"] for row in rows]
    instances = [row["instance_sha256"] for row in rows]
    contents = [row["content_sha256"] for row in rows]
    require(member_ids == sorted(member_ids) and len(set(member_ids)) == 6 and
            len(set(instances)) == 6 and len(set(contents)) == 6 and
            sum(row["source_bytes"] for row in rows) == 1082028 and
            _set_hash(instances) == EXPECTED_POPULATION["instance_set_sha256"] and
            _set_hash(contents) == EXPECTED_POPULATION["content_set_sha256"],
            "P2-20A.11 anonymous detail population drifted")
    strict = Counter(row["p2_05_strict"]["error_category"] for row in rows)
    elementtree = Counter(str(row["elementtree"]["error_code"]) for row in rows)
    tiny = [row["source_derived_tinyxml"] for row in rows]
    consumers = Counter(row["consumer_binding_state"] for row in rows)
    terminations = Counter(row["consumer_input_termination_state"] for row in rows)
    require(strict == {"malformed-attribute-spacing": 3, "invalid-comment": 1,
                       "invalid-attribute-character": 1, "unclosed-element": 1} and
            elementtree == {"4": 5, "9": 1} and
            consumers == {"dynamic-client-source-bound": 1,
                          "literal-server-source-bound": 4,
                          "unresolved-no-source-literal": 1} and
            terminations == {"unproven-client-qarray-tail": 1,
                             "server-load-file-c-str": 4,
                             "unresolved-consumer": 1},
            "P2-20A.11 strict, ElementTree, or consumer layer drifted")
    require(all(row["p2_05_strict"]["document_conformance"] is False and
                row["p2_05_strict"]["fragment_conformance"] is False and
                row["elementtree"]["accepted"] is False and
                item["client_load_file_success"] is True and
                item["server_load_file_success"] is True and
                item["client_error_flag"] is False and item["server_error_flag"] is False and
                item["client_root_present"] is True and item["server_root_present"] is True and
                item["client_server_tree_shape_equal"] is True and
                _exact(row["authority"], EXPECTED_DETAIL_AUTHORITY)
                for row, item in zip(rows, tiny, strict=True)) and
            sum(item["full_input_consumed"] is True for item in tiny) == 5 and
            sum(item["direct_parse_returned_null"] is True for item in tiny) == 1,
            "P2-20A.11 separated parser layers or authority boundary drifted")


def _validate_report(report: dict[str, Any], policy: dict[str, Any],
                     require: Callable[[bool, str], None]) -> None:
    strict = report.get("p2_05_strict", {})
    elementtree = report.get("independent_elementtree", {})
    tiny = report.get("source_derived_tinyxml", {})
    api = tiny.get("api_acceptance", {})
    complete = tiny.get("parse_completeness", {})
    consumer = report.get("consumer_boundary", {})
    require(_exact(report.get("population"), EXPECTED_POPULATION) and
            strict.get("document_rejections") == 6 and strict.get("fragment_rejections") == 6 and
            strict.get("frozen_baseline") is True and
            elementtree.get("accepted") == 0 and elementtree.get("rejected") == 6 and
            elementtree.get("dtd_enabled") is False and
            elementtree.get("external_resolver_enabled") is False and
            _exact(elementtree.get("outcome_projection"), EXPECTED_ET_PROJECTION) and
            elementtree.get("outcome_sha256") == EXPECTED_ET_PROJECTION["sha256"],
            "P2-20A.11 population, strict, or ElementTree layer drifted")
    require(tiny.get("derivation_scope") == "SOURCE_DERIVED_DIAGNOSTIC_ONLY" and
            api.get("client_load_file_successes") == 6 and
            api.get("server_load_file_successes") == 6 and
            api.get("client_server_tree_shape_equal") == 6 and
            api.get("accepted_as_terminal_disposition") is False and
            complete.get("full_input_consumed") == 5 and
            complete.get("direct_parse_returned_null") == 1 and
            complete.get("silent_partial_instances") == 1 and
            complete.get("partial_elements") == 132 and
            complete.get("partial_attributes") == 529 and
            _exact(tiny.get("api_and_completeness_projection"), EXPECTED_API_PROJECTION) and
            tiny.get("api_and_completeness_outcome_sha256") == EXPECTED_API_PROJECTION["sha256"] and
            _exact(tiny.get("tree_projection"), EXPECTED_TREE_PROJECTION) and
            tiny.get("tree_outcome_sha256") == EXPECTED_TREE_PROJECTION["sha256"] and
            _exact(tiny.get("execution_environment"), EXPECTED_ENVIRONMENT) and
            _exact(tiny.get("evidence_boundary"), EXPECTED_BOUNDARY),
            "P2-20A.11 TinyXML API or completeness layer drifted")
    require(_exact(consumer, {"source_bound": 5, "dynamic_client_source_bound": 1,
                "literal_server_source_bound": 4, "unresolved_no_source_literal": 1,
                "client_input_null_termination_proven": False,
                "legacy_memory_tail_observed": False}) and
            _exact(report.get("authority_boundaries"), EXPECTED_AUTHORITY) and
            _exact(report.get("blockers"), EXPECTED_BLOCKERS) and
            _exact(report.get("g2_projection", {}).get("metrics"), {
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
                "aux_malformed_xml_terminal_dispositions": 0}) and
            report["g2_projection"].get("g2_decision") == "BLOCKED" and
            report["g2_projection"].get("satisfied") == 7 and
            report["g2_projection"].get("blocked") == 2,
            "P2-20A.11 consumer, authority, blocker, or G2 projection drifted")
    require(_exact(policy.get("expected_population"), EXPECTED_POPULATION) and
            _exact(policy.get("implementation_baseline"), EXPECTED_IMPLEMENTATIONS) and
            _exact(policy.get("legacy_source_bindings"), EXPECTED_LEGACY_SOURCES) and
            _exact(policy.get("authority_controls"), EXPECTED_AUTHORITY) and
            _exact(policy.get("blockers"), EXPECTED_BLOCKERS) and
            _exact(policy.get("expected_elementtree", {}).get("outcome_projection"),
                   EXPECTED_ET_PROJECTION) and
            _exact(policy.get("expected_source_derived_tinyxml", {}).get(
                "api_and_completeness_projection"), EXPECTED_API_PROJECTION) and
            _exact(policy.get("expected_source_derived_tinyxml", {}).get("tree_projection"),
                   EXPECTED_TREE_PROJECTION) and
            _exact(policy.get("expected_execution_environment"), EXPECTED_ENVIRONMENT) and
            _exact(policy.get("expected_evidence_boundary"), EXPECTED_BOUNDARY),
            "P2-20A.11 policy baseline drifted")


def aux_malformed_xml_contract_safe(report: dict[str, Any]) -> bool:
    """True when the current blocked diagnostic is conservative and bindable."""
    return (report.get("diagnostic_scope_complete") is True and
            report.get("scope_complete") is False and
            report.get("g2_06_satisfied") is False and report.get("p3_authorized") is False and
            _exact(report.get("authority_boundaries"), EXPECTED_AUTHORITY) and
            report.get("source_derived_tinyxml", {}).get("api_acceptance", {}).get(
                "accepted_as_terminal_disposition") is False and
            report.get("source_derived_tinyxml", {}).get("parse_completeness", {}).get(
                "silent_partial_instances") == 1)


def aux_malformed_xml_closure_ready(report: dict[str, Any]) -> bool:
    """Synthetic successor predicate; the fixed BLOCKED A.11 binder never admits this state."""
    population = report.get("population", {})
    authority = report.get("authority_boundaries", {})
    instances = population.get("instances")
    terminal = authority.get("terminal_dispositions")
    adapters = authority.get("approved_adapters")
    no_reference = authority.get("approved_no_reference_instances")
    return (type(instances) is int and instances == 6 and
            type(terminal) is int and terminal == instances and instances - terminal == 0 and
            type(adapters) is int and type(no_reference) is int and
            adapters >= 0 and no_reference >= 0 and adapters + no_reference == instances and
            report.get("diagnostic_scope_complete") is True and
            report.get("scope_complete") is True and report.get("g2_06_satisfied") is True and
            report.get("result") == "PASS" and report.get("task_status") == "COMPLETE" and
            report.get("completion_criteria_satisfied") is True and
            report.get("blockers") == [] and
            report.get("g2_projection", {}).get("g2_06_satisfied") is True)


def aux_malformed_xml_self_test() -> dict[str, Any]:
    """Unit-test the predicate only; a new revision/policy/schema/binder is required in practice."""
    current = {
        "diagnostic_scope_complete": True, "scope_complete": False,
        "g2_06_satisfied": False, "p3_authorized": False,
        "population": {"instances": 6}, "authority_boundaries": dict(EXPECTED_AUTHORITY),
        "source_derived_tinyxml": {"api_acceptance": {
            "accepted_as_terminal_disposition": False},
            "parse_completeness": {"silent_partial_instances": 1}},
        "result": "BLOCKED", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "blockers": list(EXPECTED_BLOCKERS),
        "g2_projection": {"g2_06_satisfied": False},
    }
    promoted = json.loads(json.dumps(current)); promoted.update({
        "scope_complete": True, "g2_06_satisfied": True, "result": "PASS",
        "task_status": "COMPLETE", "completion_criteria_satisfied": True,
        "blockers": [], "g2_projection": {"g2_06_satisfied": True}})
    disposed = json.loads(json.dumps(promoted))
    disposed["authority_boundaries"].update({
        "approved_adapters": 6, "terminal_dispositions": 6})
    checks = [aux_malformed_xml_contract_safe(current),
              not aux_malformed_xml_closure_ready(current),
              not aux_malformed_xml_closure_ready(promoted),
              aux_malformed_xml_closure_ready(disposed)]
    if not all(checks):
        raise ValueError("P2-20A.11 fixed-contract/synthetic-predicate self-test failed")
    return {"result": "PASS", "assertions": len(checks),
            "current_contract_safe": True, "current_closure_ready": False,
            "synthetic_predicate_only": True}


def aux_malformed_xml_metric_map(report: dict[str, Any]) -> dict[str, Any]:
    """Return the exact G2 projection, including all zero-authority facts."""
    return {
        "aux_malformed_xml_diagnostic_hash_bound": True,
        "aux_malformed_xml_contract_safe": aux_malformed_xml_contract_safe(report),
        "aux_malformed_xml_closure_ready": aux_malformed_xml_closure_ready(report),
        "aux_malformed_xml_instances": 6,
        "aux_malformed_xml_source_bytes": 1082028,
        "aux_malformed_xml_strict_document_rejections": 6,
        "aux_malformed_xml_strict_fragment_rejections": 6,
        "aux_malformed_xml_elementtree_rejections": 6,
        "aux_malformed_xml_tinyxml_api_successes": 6,
        "aux_malformed_xml_tinyxml_full_consumption": 5,
        "aux_malformed_xml_tinyxml_silent_partial": 1,
        "aux_malformed_xml_client_server_agreement": 6,
        "aux_malformed_xml_consumer_bound": 5,
        "aux_malformed_xml_consumer_unresolved": 1,
        "aux_malformed_xml_client_input_termination_proven": False,
        "aux_malformed_xml_legacy_runtime_executed": False,
        "aux_malformed_xml_runtime_binary_parity_claimed": False,
        "aux_malformed_xml_windows_crt_parity_claimed": False,
        "aux_malformed_xml_repairs": 0,
        "aux_malformed_xml_deletions": 0,
        "aux_malformed_xml_dispositions": 0,
        "aux_malformed_xml_approved_adapters": 0,
        "aux_malformed_xml_approved_no_reference": 0,
        "aux_malformed_xml_approved_roots": 0,
        "aux_malformed_xml_semantic_imports_claimed": 0,
        "aux_malformed_xml_terminal_dispositions": 0,
        "aux_malformed_xml_malformed_blocked": 6,
    }


def aux_malformed_xml_metrics(report: dict[str, Any]) -> list[tuple[str, Any, str]]:
    units = {
        "instances": "files", "rejections": "files",
        "successes": "files", "consumption": "files", "partial": "files",
        "agreement": "files", "bound": "files", "unresolved": "files",
        "bytes": "bytes", "repairs": "files", "deletions": "files",
        "dispositions": "files", "adapters": "count",
        "reference": "files", "roots": "roots", "imports": "count",
        "blocked": "files",
    }
    result = []
    for name, value in aux_malformed_xml_metric_map(report).items():
        suffix = name.removeprefix("aux_malformed_xml_")
        unit = ("boolean" if type(value) is bool else
                next((unit for token, unit in units.items() if suffix.endswith(token)), "count"))
        result.append((name, value, unit))
    return result


def bind_aux_malformed_xml(
    root: Path,
    g2_policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    """Bind all four A.11 layers and their non-authority boundaries."""
    spec = g2_policy["aux_malformed_xml_diagnostics"]
    path = resolve_inside(root, spec["path"])
    report = load_json(path)
    require(set(report) == TOP_FIELDS and report.get("schema_version") == 1 and
            report.get("evidence_revision") == spec["evidence_revision"] == REVISION and
            report.get("task_id") == spec["task_id"] == "P2-20A" and
            report.get("criterion_id") == spec["criterion_id"] == "G2-06" and
            report.get("source_build") == g2_policy["source_build"] and
            isinstance(report.get("captured_utc"), str),
            "P2-20A.11 malformed-XML identity or shape drifted")
    require(report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            aux_malformed_xml_contract_safe(report),
            "P2-20A.11 malformed-XML diagnostic was falsely promoted")
    policy = load_json(resolve_inside(root, POLICY_PATH))
    require(policy.get("schema_version") == 1 and policy.get("evidence_revision") == REVISION and
            policy.get("task_id") == "P2-20A" and policy.get("criterion_id") == "G2-06" and
            policy.get("source_build") == g2_policy["source_build"] and
            policy.get("required_input_roles") == list(INPUT_PATHS),
            "P2-20A.11 policy identity or input roles drifted")
    entries = [{"role": role, "sha256": sha256(resolve_inside(root, relative))}
               for role, relative in INPUT_PATHS.items()]
    legacy = [{"role": role, "sha256": digest}
              for role, digest in EXPECTED_LEGACY_SOURCES.items()]
    declared = report.get("input_bindings", {})
    require(_exact(declared.get("entries"), entries) and
            _exact(declared.get("legacy_sources"), legacy),
            "P2-20A.11 input or legacy source binding drifted")
    aggregate = _set_hash([f"{item['role']}:{item['sha256']}"
                           for item in (*entries, *legacy)])
    require(declared.get("aggregate_sha256") == aggregate,
            "P2-20A.11 input aggregate drifted")
    contracts = report.get("contracts", {})
    require(_exact(contracts, {
                "policy_sha256": sha256(resolve_inside(root, POLICY_PATH)),
                "schema_sha256": sha256(resolve_inside(root, SCHEMA_PATH)),
                "detail_schema_sha256": sha256(resolve_inside(root, DETAIL_SCHEMA_PATH))}),
            "P2-20A.11 contract hashes drifted")
    _validate_detail(root, report, resolve_inside, sha256, require)
    _validate_report(report, policy, require)
    digest = sha256(path)
    binding = {
        "task_id": "P2-20A", "criterion_id": "G2-06", "evidence_revision": REVISION,
        "path": REPORT_PATH, "sha256": digest, "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False,
    }
    return binding, report, f"AUX_MALFORMED_XML|{REVISION}|{REPORT_PATH}|{digest}"
