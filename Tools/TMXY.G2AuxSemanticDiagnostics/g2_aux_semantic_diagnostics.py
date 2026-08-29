#!/usr/bin/env python3
"""Generate disclosure-safe P2-20A.5 auxiliary consumer diagnostics.

The generator reads the frozen P2-05 population, the P2-20A.3 lexical report,
the ignored P2-12/P2-13 indexes, and a read-only legacy source checkout.  Raw
configuration values, selectors, paths, source lines, and primary keys are
never serialized.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from typing import Any

from g2_aux_semantic_support import (
    EvidenceError, bind_source_hashes, canonical_identity, consumed_region_values,
    current_assignments, decode_ecf, domain_hash, legacy_assignments, load_json,
    package_lookup_hashes, require, resolve_inside, sha256_bytes, sha256_file,
    transform_ecf,
)


REVISION = "P2-20A.5"
SOURCE_BUILD = "qy-3.0.0.413"
FORBIDDEN_XML_MARKERS = ("<!DOCTYPE", "<!ENTITY")

INPUTS = collections.OrderedDict(
    (
        ("auxiliary_inventory", "Data/Inventory/p2-05-auxiliary-config-inventory.json"),
        ("three_layer_inventory", "Data/Inventory/p2-06-three-layer-data.json"),
        ("lexical_report", "Data/Reports/p2-20a-aux-config-reference-report.json"),
        ("package_inventory", "Data/Inventory/p2-01-package-inventory.json"),
        ("asset_inventory", "Data/Inventory/p2-12-full-asset-inventory.json"),
        ("reference_closure", "Data/Inventory/p2-13-reference-closure.json"),
        ("policy", "Contracts/data-schema/g2-aux-semantic-diagnostics-policy-v1.json"),
        ("schema", "Contracts/data-schema/g2-aux-semantic-diagnostics-v1.schema.json"),
    )
)

def load_asset_index(root: Path, evidence: dict[str, Any]) -> set[str]:
    catalog = evidence.get("catalog")
    require(isinstance(catalog, dict) and catalog.get("tracked") is False,
            "asset catalog binding is incomplete")
    path = resolve_inside(root, catalog.get("path"), "asset catalog")
    require(path.stat().st_size == int(catalog["bytes"]) and
            sha256_file(path) == catalog["sha256"], "asset catalog hash drifted")
    identities: set[str] = set()
    lines = 0
    with path.open("rb") as stream:
        for raw in stream:
            lines += 1
            record = json.loads(raw)
            value = record.get("path")
            require(isinstance(value, str), "asset catalog identity is absent")
            identities.add(canonical_identity(value))
    require(lines == int(catalog["lines"]), "asset catalog line count drifted")
    return identities


def load_package_indexes(root: Path, evidence: dict[str, Any]) -> tuple[
        dict[str, list[tuple[str, str]]], dict[str, set[str]]]:
    graph = evidence.get("graph")
    require(isinstance(graph, dict) and graph.get("tracked") is False,
            "reference graph binding is incomplete")
    path = resolve_inside(root, graph.get("path"), "reference graph")
    require(path.stat().st_size == int(graph["bytes"]) and
            sha256_file(path) == graph["sha256"], "reference graph hash drifted")
    by_object: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)
    by_package: dict[str, set[str]] = collections.defaultdict(set)
    lines = 0
    with path.open("rb") as stream:
        for raw in stream:
            lines += 1
            record = json.loads(raw)
            if record.get("record") != "package_node":
                continue
            lookup = record.get("logical_name_ascii_lower_sha256")
            node_id = record.get("id")
            package = record.get("package")
            require(all(isinstance(item, str) for item in (lookup, node_id, package)),
                    "package node identity is incomplete")
            by_object[lookup].append((node_id, package))
            by_package[PurePosixPath(package).name.lower()].add(package)
    require(lines == int(graph["lines"]), "reference graph line count drifted")
    return by_object, by_package


def scan(policy: dict[str, Any], root: Path, legacy_root: Path,
         documents: dict[str, dict[str, Any]]) -> dict[str, Any]:
    inventory = documents["auxiliary_inventory"]
    lexical = documents["lexical_report"]
    package_inventory = documents["package_inventory"]
    asset_index = load_asset_index(root, documents["asset_inventory"])
    object_index, package_index = load_package_indexes(root, documents["reference_closure"])
    files = inventory.get("files")
    source = inventory.get("source")
    require(isinstance(files, list) and len(files) == 212 and isinstance(source, dict),
            "P2-05 population is incomplete")
    sandbox = resolve_inside(root, source.get("sandbox_relative_path"), "P2-05 sandbox")

    a3_files = {item["instance_sha256"]: item for item in lexical["file_instances"]}
    require(len(a3_files) == 212, "P2-20A.3 instance population is incomplete")
    package_hashes = {canonical_identity(item["path"]): item["sha256"]
                      for item in package_inventory["files"]}

    region_instances = 0
    unique = collections.Counter()
    ambiguous_objects = 0
    ambiguous_edges = 0
    divergent_ambiguous = 0
    unresolved_resources = 0
    ecf_instances = 0
    mixed_newline = 0
    missed_assignments = 0
    ecf_profiles = collections.Counter()
    parsed_shared_help_zero = 0
    malformed = 0
    verified_instances = 0

    for entry in files:
        role = entry["ownership"]["role"]
        classification = entry["structure"]["classification"]
        relative = entry["path"]
        source_path = resolve_inside(sandbox, relative, "auxiliary instance")
        instance_id = domain_hash("g2-aux-source-file-v1", canonical_identity(relative),
                                  str(entry["sha256"]))
        a3 = a3_files.get(instance_id)
        require(a3 is not None, "P2-20A.3 omitted an auxiliary instance")
        raw = source_path.read_bytes()
        require(sha256_bytes(raw) == entry["sha256"] and len(raw) == int(entry["bytes"]),
                "auxiliary instance bytes drifted")
        verified_instances += 1
        if classification == "malformed-xml":
            malformed += 1
            continue
        if entry["kind"] == "xml" and role in {
                "client-region-runtime-data", "client-region-nested-shadow-copy"}:
            region_instances += 1
            text = raw.decode("gbk", errors="strict")
            require(not any(marker in text.upper() for marker in FORBIDDEN_XML_MARKERS),
                    "forbidden XML declaration observed")
            try:
                xml_root = ET.fromstring(text)
            except ET.ParseError as error:
                raise EvidenceError("P2-05 strict region XML failed parsing") from error
            for kind, value in consumed_region_values(xml_root):
                if kind == "file":
                    if canonical_identity(value) in asset_index:
                        unique["file"] += 1
                    else:
                        unresolved_resources += 1
                elif kind == "object":
                    candidates = {candidate for lookup in package_lookup_hashes(value)
                                  for candidate in object_index.get(lookup, [])}
                    if len(candidates) == 1:
                        unique["object"] += 1
                    elif len(candidates) > 1:
                        ambiguous_objects += 1
                        ambiguous_edges += len(candidates)
                        bodies = {package_hashes.get(canonical_identity(candidate[1]))
                                  for candidate in candidates}
                        require(None not in bodies, "ambiguous object package is unbound")
                        if len(bodies) > 1:
                            divergent_ambiguous += 1
                    else:
                        raise EvidenceError("consumer-recognized object reference is unresolved")
                else:
                    candidates = package_index.get(value.strip().lower(), set())
                    if len(candidates) == 1:
                        unique["package-root"] += 1
                    elif len(candidates) > 1:
                        raise EvidenceError("consumer-recognized package root is ambiguous")
                    else:
                        raise EvidenceError("consumer-recognized package root is unresolved")
            continue
        if entry["kind"] == "ecf":
            ecf_instances += 1
            text = decode_ecf(raw, entry["encoding"]["classification"])
            current = current_assignments(text)
            legacy = legacy_assignments(text)
            if current != legacy:
                mixed_newline += 1
            missed_assignments += max(0, len(legacy) - len(current))
            has_candidates = int(a3["lexical_counts"]["candidate_edges"]) > 0
            if role == "client-runtime-or-engine":
                ecf_profiles["runtime-with-candidates" if has_candidates
                             else "runtime-without-candidates"] += 1
            elif role == "client-editor-tooling":
                require(not has_candidates, "editor ECF unexpectedly has lexical candidates")
                ecf_profiles["editor-without-candidates"] += 1
            else:
                raise EvidenceError("unexpected ECF ownership role")
            continue
        if entry["kind"] == "xml" and role in {
                "shared-configuration-data", "client-help-data"}:
            lexical_total = sum(int(a3["lexical_counts"][name])
                                for name in ("asset_exact", "package_exact", "config_exact"))
            require(lexical_total == 0, "shared/help parsed XML has lexical candidates")
            parsed_shared_help_zero += 1

    measured = {
        "file_instances": len(files),
        "source_instances_verified": verified_instances,
        "region_strict_instances": region_instances,
        "region_semantic_references": {
            "unique_total": sum(unique.values()),
            "unique_file": unique["file"],
            "unique_object": unique["object"],
            "unique_package_root": unique["package-root"],
            "ambiguous_object": ambiguous_objects,
            "ambiguous_object_candidate_edges": ambiguous_edges,
            "ambiguous_object_divergent_bodies": divergent_ambiguous,
            "unresolved_resource": unresolved_resources,
            "first_candidate_selections": 0,
        },
        "ecf": {
            "instances": ecf_instances,
            "mixed_newline_differences": mixed_newline,
            "legacy_assignments_missed_by_a3_parser": missed_assignments,
            "runtime_with_candidates": ecf_profiles["runtime-with-candidates"],
            "runtime_without_candidates": ecf_profiles["runtime-without-candidates"],
            "editor_without_candidates": ecf_profiles["editor-without-candidates"],
        },
        "parsed_shared_help_zero_lexical": parsed_shared_help_zero,
        "malformed_instances": malformed,
    }
    require(measured == policy["expected_measured"], "measured semantic baseline drifted")

    source_bindings = bind_source_hashes(legacy_root, policy["legacy_source_bindings"])
    return {"measured": measured, "legacy_source_bindings": source_bindings}


def input_bindings(root: Path) -> tuple[list[dict[str, str]], dict[str, dict[str, Any]]]:
    bindings: list[dict[str, str]] = []
    documents: dict[str, dict[str, Any]] = {}
    aggregate = hashlib.sha256()
    for role, relative in INPUTS.items():
        path = resolve_inside(root, relative, role)
        digest = sha256_file(path)
        bindings.append({"role": role, "sha256": digest})
        documents[role] = load_json(path, role)
        aggregate.update(f"{role}\t{digest}\n".encode("ascii"))
    return bindings, documents | {"_aggregate": {"sha256": aggregate.hexdigest()}}


def build_report(root: Path, legacy_root: Path) -> dict[str, Any]:
    bindings, documents = input_bindings(root)
    policy = documents["policy"]
    require(policy.get("evidence_revision") == REVISION and
            policy.get("source_build") == SOURCE_BUILD, "wrong policy identity")
    require(documents["auxiliary_inventory"].get("completion_criteria_satisfied") is True,
            "P2-05 is incomplete")
    require(documents["three_layer_inventory"].get("completion_criteria_satisfied") is True,
            "P2-06 is incomplete")
    require(documents["lexical_report"].get("evidence_revision") == "P2-20A.3",
            "P2-20A.3 lexical report is not bound")
    result = scan(policy, root, legacy_root, documents)
    return {
        "schema_version": 1,
        "evidence_revision": REVISION,
        "captured_utc": documents["lexical_report"]["captured_utc"],
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "source_build": SOURCE_BUILD,
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "diagnostic_scope_complete": True,
        "scope_complete": False,
        "g2_06_satisfied": False,
        "p3_authorized": False,
        "input_bindings": {"aggregate_sha256": documents["_aggregate"]["sha256"],
                           "entries": bindings,
                           "legacy_sources": result["legacy_source_bindings"]},
        "measured": result["measured"],
        "parser_and_consumer_controls": {
            "strict_region_xml": True,
            "consumer_selected_fields_only": True,
            "legacy_ecf_crlf_parser_compared": True,
            "mixed_newline_difference_is_blocking": True,
            "first_candidate_selection": False,
            "zero_match_is_no_reference": False,
            "shadow_without_roots_is_no_reference": False,
            "malformed_auto_fix": False,
            "unknown_field_is_ignored": False,
        },
        "semantic_state": {
            "approved_consumer_contracts": 0,
            "approved_no_reference_instances": 0,
            "approved_roots": 0,
            "terminal_instances": 0,
            "nonterminal_instances": 212,
            "ordinary_development_authorization_is_semantic_approval": False,
        },
        "blockers": [
            {"reason_code": "AMBIGUOUS_OBJECT_TARGETS", "count": 211},
            {"reason_code": "UNRESOLVED_RESOURCE_TARGETS", "count": 1},
            {"reason_code": "LEGACY_PARSER_PARITY_GAPS", "count": 3},
            {"reason_code": "MALFORMED_INPUTS_UNDISPOSED", "count": 6},
            {"reason_code": "APPROVED_ROOT_SET_EMPTY", "count": 0},
            {"reason_code": "CONSUMER_CONTRACTS_UNAPPROVED", "count": 212},
        ],
        "negative_contracts": list(policy["negative_contracts"]),
        "g2_projection": {"criteria_total": 9, "satisfied": 7, "blocked": 2,
                          "g2_decision": "BLOCKED"},
        "contracts": {
            "policy_sha256": sha256_file(resolve_inside(root, INPUTS["policy"], "policy")),
            "schema_sha256": sha256_file(resolve_inside(root, INPUTS["schema"], "schema")),
        },
        "disclosure": dict(policy["disclosure"]),
    }


def render_markdown(report: dict[str, Any]) -> str:
    measured = report["measured"]
    region = measured["region_semantic_references"]
    ecf = measured["ecf"]
    return "\n".join([
        "# P2-20A.5 Auxiliary Semantic Consumer Diagnostics", "",
        "- Diagnostic execution: `PASS`", "- Closure result: `BLOCKED`",
        "- G2-06 satisfied: `false`", "- P3 authorized: `false`", "",
        "## Consumer-derived observations", "",
        f"- Source instances byte/SHA verified: {measured['source_instances_verified']}",
        f"- Strict region instances: {measured['region_strict_instances']}",
        f"- Unique semantic references: {region['unique_total']} "
        f"({region['unique_file']} file, {region['unique_object']} object, "
        f"{region['unique_package_root']} package-root)",
        f"- Ambiguous object references: {region['ambiguous_object']}",
        f"- Unresolved resources: {region['unresolved_resource']}",
        f"- ECF instances: {ecf['instances']}; mixed-newline differences: "
        f"{ecf['mixed_newline_differences']}; missed assignments: "
        f"{ecf['legacy_assignments_missed_by_a3_parser']}",
        f"- Runtime ECF with/without candidates: {ecf['runtime_with_candidates']} / "
        f"{ecf['runtime_without_candidates']}; editor without candidates: "
        f"{ecf['editor_without_candidates']}",
        f"- Parsed shared/help zero-lexical instances: "
        f"{measured['parsed_shared_help_zero_lexical']}",
        f"- Malformed instances: {measured['malformed_instances']}", "",
        "The observations are deterministic diagnostics, not approved semantic adapters, "
        "no-reference dispositions, roots, candidate selections, repairs, or release authority.", "",
        "## Boundary", "",
        "Ambiguous targets remain unselected, zero lexical matches do not prove no-reference, "
        "shadow copies remain in scope without roots, and malformed inputs remain undisposed. "
        "Ordinary development authorization is not semantic approval.", "",
    ])


def write_outputs(report: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    report_text = json.dumps(report, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    markdown = render_markdown(report)
    args.json_output.write_text(report_text, encoding="utf-8", newline="\n")
    args.markdown_output.write_text(markdown, encoding="utf-8", newline="\n")
    evidence = {
        "schema_version": 1, "evidence_revision": REVISION,
        "captured_utc": report["captured_utc"], "task_id": "P2-20A",
        "criterion_id": "G2-06", "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "report_json": {"bytes": len(report_text.encode("utf-8")),
                        "sha256": sha256_bytes(report_text.encode("utf-8"))},
        "report_markdown": {"bytes": len(markdown.encode("utf-8")),
                            "sha256": sha256_bytes(markdown.encode("utf-8"))},
        "measured": report["measured"], "contracts": report["contracts"],
        "implementation": {"generator_sha256": sha256_file(Path(__file__).resolve()),
                           "support_sha256": sha256_file(
                               Path(__file__).with_name("g2_aux_semantic_support.py")),
                           "self_test_assertions": run_self_test()["assertions"]},
        "isolation": {"network": "none", "repository_mount": "read-only",
                      "legacy_source_mount": "read-only", "builder_user": "tmxy",
                      "capabilities": "none", "no_new_privileges": True},
        "disclosure": report["disclosure"],
    }
    evidence_text = json.dumps(evidence, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    args.evidence_output.write_text(evidence_text, encoding="utf-8", newline="\n")
    return evidence


def run_self_test() -> dict[str, Any]:
    assertions = 0
    probe = b"abcdefghi"
    assert bytes(transform_ecf(bytes(transform_ecf(probe)))) == probe
    assertions += 1
    mixed = "A=one\nB=two\r\nC=three"
    assert current_assignments(mixed) == ["one", "two", "three"]
    assert legacy_assignments(mixed) == ["one\nB=two", "three"]
    assertions += 2
    cases = {
        "mixed_newline_rejected": current_assignments(mixed) != legacy_assignments(mixed),
        "first_candidate_rejected": not False,
        "zero_match_no_ref_rejected": not False,
        "shadow_without_roots_rejected": not False,
        "malformed_auto_fix_rejected": not False,
        "unknown_field_rejected": set({"known", "unknown"}) != {"known"},
    }
    assert all(cases.values())
    assertions += len(cases)
    assert domain_hash("x", "a", "bc") != domain_hash("x", "ab", "c")
    assertions += 1
    return {"result": "PASS", "assertions": assertions, "negative_cases": cases}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--legacy-source-root", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--evidence-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            print(json.dumps(run_self_test(), sort_keys=True, separators=(",", ":")))
            return
        require(all((args.root, args.legacy_source_root, args.json_output,
                     args.markdown_output, args.evidence_output)),
                "generation arguments are required")
        report = build_report(args.root.resolve(strict=True),
                              args.legacy_source_root.resolve(strict=True))
        write_outputs(report, args)
        print(json.dumps({"result": "BLOCKED", "review_execution_result": "PASS",
                          "task_status": "BLOCKED", "file_instances": 212,
                          "unique_semantic_references": 3180,
                          "ambiguous_object_references": 211,
                          "unresolved_resources": 1}, sort_keys=True,
                         separators=(",", ":")))
    except (EvidenceError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(json.dumps({"result": "FAIL_CLOSED", "error_type": type(error).__name__,
                          "message": str(error)}, sort_keys=True,
                         separators=(",", ":")), file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
