#!/usr/bin/env python3
"""Generate P2-20A.9 package-context consumer binding evidence."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from typing import Any

from aux_package_context_support import (
    REQUIRED_IGNORED_ARTIFACT_ROLES, EvidenceError, bind_source_hashes,
    canonical_identity, consumed_region_values, domain_hash, load_json, lower_ascii_text,
    package_lookup_hashes, package_prefix, render_markdown, require,
    require_policy_boundaries, resolve_inside, run_self_test, select_package_context,
    sha256_bytes, sha256_file, sha256_lines,
)


REVISION = "P2-20A.9"
SOURCE_BUILD = "qy-3.0.0.413"
DETAIL_RELATIVE = "Data/Exports/P2-20/p2-20a-aux-package-context.jsonl"
INPUTS = collections.OrderedDict((
    ("auxiliary_inventory", "Data/Inventory/p2-05-auxiliary-config-inventory.json"),
    ("a3_report", "Data/Reports/p2-20a-aux-config-reference-report.json"),
    ("a3_evidence", "Data/Inventory/p2-20a-aux-config-reference-evidence.json"),
    ("a5_report", "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json"),
    ("a5_evidence", "Data/Inventory/p2-20a-aux-semantic-diagnostics.json"),
    ("package_inventory", "Data/Inventory/p2-01-package-inventory.json"),
    ("asset_inventory", "Data/Inventory/p2-12-full-asset-inventory.json"),
    ("reference_closure", "Data/Inventory/p2-13-reference-closure.json"),
    ("policy", "Contracts/data-schema/g2-aux-package-context-policy-v1.json"),
    ("schema", "Contracts/data-schema/g2-aux-package-context-v1.schema.json"),
    ("detail_schema", "Contracts/data-schema/g2-aux-package-context-detail-v1.schema.json"),
))


def load_asset_index(root: Path, evidence: dict[str, Any]) -> tuple[set[str], dict[str, Any]]:
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
            require(isinstance(record.get("path"), str), "asset identity is absent")
            identities.add(canonical_identity(record["path"]))
    require(lines == int(catalog["lines"]), "asset catalog line count drifted")
    binding = {"role": "asset_catalog", "path": catalog["path"],
               "bytes": path.stat().st_size, "lines": lines,
               "sha256": sha256_file(path), "tracked": False}
    return identities, binding


def load_package_indexes(root: Path, evidence: dict[str, Any]) -> tuple[
        dict[str, list[tuple[str, str]]], dict[str, set[str]], dict[str, Any]]:
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
            lookup, node_id, package = (record.get(name) for name in
                                        ("logical_name_ascii_lower_sha256", "id", "package"))
            require(all(isinstance(item, str) for item in (lookup, node_id, package)),
                    "package node identity is incomplete")
            by_object[lookup].append((node_id, package))
            by_package[lower_ascii_text(PurePosixPath(package).name)].add(package)
    require(lines == int(graph["lines"]), "reference graph line count drifted")
    binding = {"role": "reference_graph", "path": graph["path"],
               "bytes": path.stat().st_size, "lines": lines,
               "sha256": sha256_file(path), "tracked": False}
    return by_object, by_package, binding


def bind_a3_detail(root: Path, evidence: dict[str, Any]) -> dict[str, Any]:
    outputs = evidence.get("outputs")
    export = outputs.get("anonymous_candidate_export") if isinstance(outputs, dict) else None
    require(isinstance(export, dict) and export.get("tracked") is False,
            "A.3 anonymous candidate export binding is incomplete")
    path = resolve_inside(root, export.get("path"), "A.3 candidate export")
    lines = sum(1 for _ in path.open("rb"))
    require(path.stat().st_size == int(export["bytes"]) and
            sha256_file(path) == export["sha256"] and lines == int(export["lines"]),
            "A.3 anonymous candidate export drifted")
    return {"role": "a3_detail", "path": export["path"], "bytes": path.stat().st_size,
            "lines": lines, "sha256": sha256_file(path), "tracked": False}


def object_proof(instance_id: str, ordinal: int, value: str,
                 candidates: list[tuple[str, str]], package_index: dict[str, set[str]],
                 strict_state: str) -> dict[str, Any]:
    ordered = sorted(set(candidates))
    require(len(ordered) == len(set(item[0] for item in ordered)),
            "candidate identifiers are not unique")
    selected, compatible = select_package_context(value, ordered)
    reversed_selected, _ = select_package_context(value, list(reversed(ordered)))
    require(selected == reversed_selected, "candidate ordering changed package-context result")
    global_matches = package_index.get(package_prefix(value), set())
    require(len(global_matches) == 1 and selected[1] in global_matches,
            "package filename is not globally unique in the frozen package population")
    occurrence_id = domain_hash("g2-aux-package-context-occurrence-v1", instance_id,
                                str(ordinal), "object")
    candidate_hash = sha256_lines([item[0] for item in ordered])
    context_hash = domain_hash("g2-aux-package-context-prefix-v1", package_prefix(value))
    proof_hash = domain_hash("g2-aux-package-context-proof-v1", occurrence_id,
                             strict_state, candidate_hash, context_hash, selected[0])
    require(len(compatible) == 1 and selected in ordered,
            "selected package-context candidate escaped the frozen set")
    return {
        "occurrence_id": occurrence_id,
        "strict_state": strict_state,
        "candidate_count": len(ordered),
        "candidate_set_sha256": candidate_hash,
        "package_context_sha256": context_hash,
        "compatible_count": 1,
        "selected_candidate_id": selected[0],
        "order_invariant": True,
        "proof_sha256": proof_hash,
    }


def scan(policy: dict[str, Any], root: Path, legacy_root: Path,
         documents: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], list[dict[str, Any]],
                                                       list[dict[str, Any]]]:
    inventory = documents["auxiliary_inventory"]
    semantic = documents["a5_report"]
    files = inventory.get("files")
    source = inventory.get("source")
    require(isinstance(files, list) and len(files) == 212 and isinstance(source, dict),
            "P2-05 population is incomplete")
    sandbox = resolve_inside(root, source.get("sandbox_relative_path"), "P2-05 sandbox")
    asset_index, asset_binding = load_asset_index(root, documents["asset_inventory"])
    object_index, package_index, graph_binding = load_package_indexes(
        root, documents["reference_closure"])
    package_hashes = {canonical_identity(item["path"]): item["sha256"]
                      for item in documents["package_inventory"]["files"]}

    verified = 0
    region_instances = 0
    strict = collections.Counter()
    context = collections.Counter()
    instance_partition = collections.Counter()
    effective_instances = collections.Counter()
    detail: list[dict[str, Any]] = []

    for entry in files:
        relative = entry["path"]
        source_path = resolve_inside(sandbox, relative, "auxiliary instance")
        raw = source_path.read_bytes()
        require(sha256_bytes(raw) == entry["sha256"] and len(raw) == int(entry["bytes"]),
                "auxiliary instance bytes drifted")
        verified += 1
        role = entry["ownership"]["role"]
        if entry["kind"] != "xml" or entry["structure"]["classification"] == "malformed-xml" or role not in {
                "client-region-runtime-data", "client-region-nested-shadow-copy"}:
            continue
        region_instances += 1
        instance_id = domain_hash("g2-aux-source-file-v1", canonical_identity(relative),
                                  str(entry["sha256"]))
        try:
            xml_root = ET.fromstring(raw.decode("gbk", errors="strict"))
        except (UnicodeDecodeError, ET.ParseError) as error:
            raise EvidenceError("strict region source failed parsing") from error
        counts = collections.Counter()
        proofs: list[dict[str, Any]] = []
        object_ordinal = 0
        for kind, value in consumed_region_values(xml_root):
            if kind == "file":
                if canonical_identity(value) in asset_index:
                    strict["unique_file"] += 1
                    counts["strict_unique"] += 1
                    counts["effective_resolved"] += 1
                else:
                    strict["unresolved_resource"] += 1
                    counts["unresolved_resource"] += 1
                continue
            if kind == "package-root":
                candidates = package_index.get(lower_ascii_text(value.strip()), set())
                require(len(candidates) == 1, "package-root consumer binding is not unique")
                strict["unique_package_root"] += 1
                counts["strict_unique"] += 1
                counts["effective_resolved"] += 1
                continue
            candidates = sorted({candidate for lookup in package_lookup_hashes(value)
                                 for candidate in object_index.get(lookup, [])})
            require(candidates, "object consumer binding is unresolved")
            object_ordinal += 1
            if len(candidates) == 1:
                state = "UNIQUE"
                strict["unique_object"] += 1
                context["preexisting_unique_verified"] += 1
                counts["strict_unique"] += 1
            else:
                state = "AMBIGUOUS"
                require(len(candidates) == 2, "ambiguous candidate cardinality drifted")
                strict["ambiguous_object"] += 1
                strict["ambiguous_candidate_edges"] += len(candidates)
                bodies = {package_hashes.get(canonical_identity(item[1])) for item in candidates}
                require(None not in bodies, "ambiguous package body is unbound")
                if len(bodies) > 1:
                    strict["divergent_ambiguous_bodies"] += 1
                context["ambiguous_attempted"] += 1
                context["original_candidate_edges"] += len(candidates)
            proof = object_proof(instance_id, object_ordinal, value, candidates,
                                 package_index, state)
            if state == "AMBIGUOUS":
                proofs.append(proof)
            counts["effective_resolved"] += 1
            if state == "AMBIGUOUS":
                context["singleton_matches"] += 1
                context["selected_edges"] += 1
                context["incompatible_context_edges"] += len(candidates) - 1
                context["order_invariant"] += int(proof["order_invariant"])

        if counts["unresolved_resource"]:
            require(counts["unresolved_resource"] == 1,
                    "region unresolved-resource cardinality drifted")
            effective_state = "UNRESOLVED"
            effective_instances["unresolved_resource"] += 1
        else:
            effective_state = "RESOLVED_ONLY"
            effective_instances["resolved_only"] += 1
        if any(item["strict_state"] == "AMBIGUOUS" for item in proofs):
            if counts["unresolved_resource"]:
                instance_partition["strict_ambiguous_and_unresolved"] += 1
            else:
                instance_partition["strict_ambiguous_only"] += 1
        else:
            instance_partition["strict_clean"] += 1
        proof_hashes = [item["proof_sha256"] for item in proofs]
        detail.append({
            "schema_version": 1,
            "instance_id": instance_id,
            "technical_state": effective_state,
            "strict_counts": {
                "resolved": counts["strict_unique"],
                "ambiguous": len(proofs),
                "unresolved": counts["unresolved_resource"],
            },
            "effective_counts": {
                "resolved": counts["effective_resolved"],
                "ambiguous": 0,
                "unresolved": counts["unresolved_resource"],
            },
            "object_proofs": proofs,
            "proof_set_sha256": sha256_lines(proof_hashes),
        })

    require(len({item["instance_id"] for item in detail}) == len(detail),
            "region instance identifiers are not unique")
    strict_baseline = {
        "region_instances": region_instances,
        "unique_total": strict["unique_file"] + strict["unique_object"] +
                        strict["unique_package_root"],
        "unique_file": strict["unique_file"],
        "unique_object": strict["unique_object"],
        "unique_package_root": strict["unique_package_root"],
        "ambiguous_object": strict["ambiguous_object"],
        "ambiguous_candidate_edges": strict["ambiguous_candidate_edges"],
        "divergent_ambiguous_bodies": strict["divergent_ambiguous_bodies"],
        "unresolved_resource": strict["unresolved_resource"],
        "first_candidate_selections": 0,
    }
    require(strict_baseline == policy["strict_baseline"],
            "strict consumer baseline drifted")
    measured = {
        "source_instances_verified": verified,
        "region_instance_partition": {
            "strict_clean": instance_partition["strict_clean"],
            "strict_ambiguous_only": instance_partition["strict_ambiguous_only"],
            "strict_ambiguous_and_unresolved":
                instance_partition["strict_ambiguous_and_unresolved"],
        },
        "package_context": {
            "preexisting_unique_verified": context["preexisting_unique_verified"],
            "ambiguous_attempted": context["ambiguous_attempted"],
            "original_candidate_edges": context["original_candidate_edges"],
            "singleton_matches": context["singleton_matches"],
            "zero_matches": 0,
            "multiple_matches": 0,
            "selected_edges": context["selected_edges"],
            "incompatible_context_edges": context["incompatible_context_edges"],
            "order_invariant": context["order_invariant"],
            "first_candidate_selections": 0,
        },
        "effective_resolution": {
            "total_occurrences": strict_baseline["unique_total"] +
                                 strict_baseline["ambiguous_object"] +
                                 strict_baseline["unresolved_resource"],
            "resolved_total": strict_baseline["unique_total"] +
                              strict_baseline["ambiguous_object"],
            "resolved_file": strict_baseline["unique_file"],
            "resolved_object": strict_baseline["unique_object"] +
                               strict_baseline["ambiguous_object"],
            "resolved_package_root": strict_baseline["unique_package_root"],
            "ambiguous_object": 0,
            "ambiguous_candidate_edges": 0,
            "unresolved_resource": strict_baseline["unresolved_resource"],
        },
        "effective_region_instances": {
            "resolved_only": effective_instances["resolved_only"],
            "unresolved_resource": effective_instances["unresolved_resource"],
        },
    }
    require(measured == policy["expected_measured"], "package-context measurements drifted")
    a5 = semantic["measured"]["region_semantic_references"]
    require(a5["unique_total"] == strict_baseline["unique_total"] and
            a5["ambiguous_object"] == strict_baseline["ambiguous_object"] and
            a5["ambiguous_object_candidate_edges"] ==
            strict_baseline["ambiguous_candidate_edges"] and
            a5["unresolved_resource"] == strict_baseline["unresolved_resource"],
            "P2-20A.5 strict semantic baseline drifted")
    sources = bind_source_hashes(legacy_root, policy["legacy_source_bindings"])
    return {"strict_baseline": strict_baseline, "measured": measured,
            "legacy_sources": sources}, sorted(detail, key=lambda item: item["instance_id"]), [
                bind_a3_detail(root, documents["a3_evidence"]), asset_binding, graph_binding]


def input_bindings(root: Path) -> tuple[list[dict[str, str]], dict[str, dict[str, Any]]]:
    entries: list[dict[str, str]] = []
    documents: dict[str, dict[str, Any]] = {}
    for role, relative in INPUTS.items():
        path = resolve_inside(root, relative, role)
        digest = sha256_file(path)
        entries.append({"role": role, "sha256": digest})
        documents[role] = load_json(path, role)
    return entries, documents


def build_report(root: Path, legacy_root: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    entries, documents = input_bindings(root)
    policy = documents["policy"]
    require(policy.get("evidence_revision") == REVISION and
            policy.get("source_build") == SOURCE_BUILD, "wrong policy identity")
    require_policy_boundaries(policy)
    require(documents["a5_report"].get("evidence_revision") == "P2-20A.5" and
            documents["a5_report"].get("result") == "BLOCKED",
            "P2-20A.5 diagnostic is not bound")
    result, detail, ignored = scan(policy, root, legacy_root, documents)
    require([item.get("role") for item in ignored] == REQUIRED_IGNORED_ARTIFACT_ROLES,
            "ignored-artifact bindings drifted")
    aggregate = hashlib.sha256()
    for item in entries:
        aggregate.update(f"{item['role']}\t{item['sha256']}\n".encode("ascii"))
    for item in ignored:
        aggregate.update(f"{item['role']}\t{item['sha256']}\n".encode("ascii"))
    controls = dict(policy["expected_consumer_controls"])
    technical = dict(policy["technical_state"])
    authority = dict(policy["authority_state"])
    preserved = dict(policy["preserved_blockers"])
    return {
        "schema_version": 1,
        "evidence_revision": REVISION,
        "captured_utc": documents["a5_report"]["captured_utc"],
        "task_id": "P2-20A", "criterion_id": "G2-06", "source_build": SOURCE_BUILD,
        "result": "BLOCKED", "review_execution_result": "PASS",
        "task_status": "BLOCKED", "completion_criteria_satisfied": False,
        "diagnostic_scope_complete": True, "scope_complete": False,
        "g2_06_satisfied": False, "p3_authorized": False,
        "input_bindings": {"aggregate_sha256": aggregate.hexdigest(), "entries": entries,
                           "ignored_artifacts": ignored,
                           "legacy_sources": result["legacy_sources"]},
        "strict_baseline": result["strict_baseline"],
        "measured": result["measured"],
        "consumer_controls": controls,
        "technical_state": technical,
        "authority_state": authority,
        "preserved_blockers": preserved,
        "blockers": list(policy["blockers"]),
        "negative_contracts": list(policy["negative_contracts"]),
        "detail_export": {},
        "g2_projection": {"criteria_total": 9, "satisfied": 7, "blocked": 2,
                          "g2_decision": "BLOCKED"},
        "contracts": {
            "policy_sha256": sha256_file(resolve_inside(root, INPUTS["policy"], "policy")),
            "schema_sha256": sha256_file(resolve_inside(root, INPUTS["schema"], "schema")),
            "detail_schema_sha256": sha256_file(resolve_inside(
                root, INPUTS["detail_schema"], "detail schema")),
        },
        "disclosure": dict(policy["disclosure"]),
    }, detail


def write_outputs(report: dict[str, Any], detail: list[dict[str, Any]],
                  args: argparse.Namespace) -> None:
    detail_text = "".join(json.dumps(item, ensure_ascii=True, allow_nan=False,
                                     sort_keys=True, separators=(",", ":")) + "\n"
                          for item in detail)
    detail_bytes = detail_text.encode("utf-8")
    args.detail_output.write_bytes(detail_bytes)
    report["detail_export"] = {"tracked": False, "path": DETAIL_RELATIVE,
                               "lines": len(detail), "bytes": len(detail_bytes),
                               "sha256": sha256_bytes(detail_bytes)}
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
        "detail_export": report["detail_export"],
        "strict_baseline": report["strict_baseline"], "measured": report["measured"],
        "contracts": report["contracts"],
        "implementation": {
            "generator_sha256": sha256_file(Path(__file__).resolve()),
            "support_sha256": sha256_file(Path(__file__).with_name(
                "aux_package_context_support.py")),
            "self_test_assertions": run_self_test()["assertions"],
        },
        "isolation": {"network": "none", "repository_mount": "read-only",
                      "legacy_source_mount": "read-only", "builder_user": "tmxy",
                      "capabilities": "none", "no_new_privileges": True},
        "disclosure": report["disclosure"],
    }
    evidence_text = json.dumps(evidence, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    args.evidence_output.write_text(evidence_text, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--legacy-source-root", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--evidence-output", type=Path)
    parser.add_argument("--detail-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            print(json.dumps(run_self_test(), sort_keys=True, separators=(",", ":")))
            return
        require(all((args.root, args.legacy_source_root, args.json_output,
                     args.markdown_output, args.evidence_output, args.detail_output)),
                "generation arguments are required")
        report, detail = build_report(args.root.resolve(strict=True),
                                      args.legacy_source_root.resolve(strict=True))
        write_outputs(report, detail, args)
        print(json.dumps({"result": "BLOCKED", "review_execution_result": "PASS",
                          "task_status": "BLOCKED", "ambiguous_attempted": 211,
                          "singleton_matches": 211, "effective_resolved": 3391,
                          "effective_ambiguous": 0, "unresolved_resources": 1},
                         sort_keys=True, separators=(",", ":")))
    except (EvidenceError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(json.dumps({"result": "FAIL_CLOSED", "error_type": type(error).__name__,
                          "message": str(error)}, sort_keys=True, separators=(",", ":")),
              file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
