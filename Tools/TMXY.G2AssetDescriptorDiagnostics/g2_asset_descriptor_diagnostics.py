"""Deterministic P2-20A.4 full-semantic descriptor diagnostics.

Preparation files are local-only and may contain legacy-relative names.  Final
outputs contain anonymous identities and aggregate evidence only.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
from pathlib import Path
from typing import Any

from diagnostic_self_test import run_self_test
from diagnostic_common import (ASSET_FIELDS, FAMILIES, canonical_json, iter_jsonl,
                               load_json, load_selected_workset,
                               probe_candidate_set_sha256, require, sha256_file,
                               sha256_lines, stable_asset_id, validate_bound_export,
                               write_text)


PROBE_FIELDS = {"asset_id", "family", "structure", "candidate_set_sha256",
                "candidates", "counts"}
CANDIDATE_FIELDS = {"candidate_id", "body_sha256", "descriptor", "binding",
                    "semantic_sha256", "descriptor_semantic_sha256",
                    "identity_normalized_descriptor_semantic_sha256",
                    "identity_normalized_semantic_sha256",
                    "identity_mirror_ascii_lower_match"}
COUNT_FIELDS = {"candidates", "descriptor_parsed", "descriptor_rejected",
                "binding_pass", "binding_rejected", "semantic_distinct"}
CLASS_BY_FAMILY = {
    "qtx": "QTexture",
    "sm": "QStaticMesh",
    "skem": "QSkelMesh",
    "anim": "QSkelMesh",
}


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    p203 = load_json(root / "Data/Inventory/p2-03-package-dependency-graph.json")
    p212 = load_json(root / "Data/Inventory/p2-12-full-asset-inventory.json")
    p213 = load_json(root / "Data/Inventory/p2-13-reference-closure.json")
    policy = load_json(root / "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json")

    graph203 = validate_bound_export(root, p203, "graph", 269064)
    catalog = validate_bound_export(root, p212, "catalog", 40090)
    graph213 = validate_bound_export(root, p213, "graph", 683355)
    asset_workset_binding = dict(policy["scope"]["base_workset"])
    asset_workset_binding["lines"] = asset_workset_binding.pop("targets")
    workset = validate_bound_export(root, {"binding": asset_workset_binding}, "binding", 21494)
    selected = load_selected_workset(workset)

    expected: dict[str, set[str]] = collections.defaultdict(set)
    node213: dict[str, tuple[str, str, str, str, str]] = {}
    for item in iter_jsonl(graph213):
        record = item.get("record")
        if record == "package_asset_edge" and item.get("target") in selected:
            asset_id = str(item["target"])
            require(item.get("family") == selected[asset_id]["family"],
                    "P2-13 edge family disagrees with the selected asset")
            expected[asset_id].add(str(item["source"]))
        elif record == "package_node":
            node_id = str(item["id"])
            node213[node_id] = (
                str(item["package"]), str(item["class"]), str(item["category"]),
                str(item["logical_name_sha256"]),
                str(item["logical_name_ascii_lower_sha256"]),
            )

    expected_ids: set[str] = set()
    for asset_id, prior in selected.items():
        candidates = expected.get(asset_id, set())
        require(len(candidates) == int(prior["candidate_count"]),
                "P2-13 candidate count disagrees with the binding workset")
        require(sha256_lines(candidates) == prior["candidate_set_sha256"],
                "P2-13 candidate identity set disagrees with the binding workset")
        expected_ids.update(candidates)
    require(len(expected_ids) > 0, "P2-20A.4 has no candidate identities")

    assets: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(catalog):
        asset_id = stable_asset_id(str(item["path"]), str(item["sha256"]))
        if asset_id in selected:
            require(asset_id not in assets, "P2-12 selected asset is duplicated")
            require(item["family"] == selected[asset_id]["family"] and
                    item["structure"] == selected[asset_id]["structure"],
                    "P2-12 selected asset metadata disagrees with the workset")
            assets[asset_id] = item
    require(set(assets) == set(selected), "P2-12 selected target set is incomplete")

    nodes203: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(graph203):
        if item.get("record") != "node" or item.get("class") not in set(CLASS_BY_FAMILY.values()):
            continue
        node_id = str(item["id"])
        require(node_id not in nodes203, "P2-03 candidate identity is duplicated")
        require(node_id in node213, "P2-03 candidate is absent from P2-13")
        frozen = node213[node_id]
        observed = (str(item["package"]), str(item["class"]), str(item["category"]),
                    str(item["logical_name_sha256"]),
                    str(item["logical_name_ascii_lower_sha256"]))
        require(observed == frozen, "P2-03 and P2-13 candidate identities disagree")
        nodes203[node_id] = item
    require(expected_ids.issubset(nodes203), "P2-03 selected candidate identity set is incomplete")
    require(len(nodes203) == 46865,
            "P2-03 descriptor-candidate map drifted from 46,865 objects")

    asset_rows: list[str] = []
    for asset_id in sorted(selected):
        item = assets[asset_id]
        candidates = sorted(expected[asset_id])
        fields = [asset_id, str(item["path"]), str(item["sha256"]), str(item["bytes"]),
                  str(item["family"]), str(item["structure"]), ",".join(candidates)]
        require(all("\t" not in value and "\n" not in value and "\r" not in value
                    for value in fields), "Asset preparation field is not TSV-safe")
        asset_rows.append("\t".join(fields))
    candidate_rows: list[str] = []
    for candidate_id in sorted(nodes203):
        item = nodes203[candidate_id]
        if candidate_id in expected_ids:
            owning_families = {
                selected[asset_id]["family"] for asset_id in selected
                if candidate_id in expected[asset_id]
            }
            require(all(item["class"] == CLASS_BY_FAMILY[family]
                        for family in owning_families),
                    "Candidate class disagrees with a selected asset family")
        fields = [candidate_id, str(item["package"]), str(item["body_offset"]),
                  str(item["body_size"]), str(item["class"])]
        require(all("\t" not in value and "\n" not in value and "\r" not in value
                    for value in fields), "Candidate preparation field is not TSV-safe")
        candidate_rows.append("\t".join(fields))

    write_text(Path(args.asset_tsv), "\n".join(asset_rows) + "\n")
    write_text(Path(args.candidate_tsv), "\n".join(candidate_rows) + "\n")
    return {
        "result": "PASS",
        "targets": len(asset_rows),
        "candidate_edges": sum(len(value) for value in expected.values()),
        "candidate_objects": len(candidate_rows),
        "asset_tsv_sha256": sha256_file(Path(args.asset_tsv)),
        "candidate_tsv_sha256": sha256_file(Path(args.candidate_tsv)),
    }


def validate_candidate(candidate: dict[str, Any]) -> None:
    require(set(candidate) == CANDIDATE_FIELDS, "Probe candidate record is not closed")
    require(candidate["descriptor"] in {"PARSED", "REJECTED"},
            "Unknown descriptor disposition")
    require(candidate["binding"] in {"PASS", "REJECTED"},
            "Unknown binding disposition")
    for key in ("candidate_id", "body_sha256"):
        require(isinstance(candidate[key], str) and len(candidate[key]) == 64,
                f"Candidate {key} is not a SHA-256 identity")
    exact_semantics = [candidate[name] for name in (
        "semantic_sha256", "descriptor_semantic_sha256")]
    normalized_semantics = [candidate[name] for name in (
        "identity_normalized_descriptor_semantic_sha256",
        "identity_normalized_semantic_sha256")]
    semantics = exact_semantics + normalized_semantics
    require(all(value is None or (isinstance(value, str) and len(value) == 64)
                for value in semantics), "Candidate semantic identity is invalid")
    require((candidate["descriptor"] == "PARSED") ==
            all(value is not None for value in exact_semantics),
            "Descriptor disposition and exact semantic identities disagree")
    require(all(value is None for value in normalized_semantics) or
            all(value is not None for value in normalized_semantics),
            "Normalized semantic identities are partially populated")
    require(isinstance(candidate["identity_mirror_ascii_lower_match"], bool),
            "Candidate identity mirror flag is invalid")
    require(not candidate["identity_mirror_ascii_lower_match"] or
            all(value is not None for value in normalized_semantics),
            "Matching identity mirror has no normalized semantic identities")
    require(candidate["descriptor"] == "PARSED" or candidate["binding"] == "REJECTED",
            "Rejected descriptor cannot pass production binding")


def classify_probe(prior: dict[str, Any], probe: dict[str, Any]) -> dict[str, Any]:
    require(set(probe) == PROBE_FIELDS, "Probe asset record is not closed")
    require(probe["asset_id"] == prior["asset_id"] and
            probe["family"] == prior["family"] and
            probe["structure"] == prior["structure"],
            "Probe asset identity or metadata disagrees with the prior workset")
    candidates = probe["candidates"]
    require(isinstance(candidates, list) and candidates, "Probe candidate set is empty")
    for candidate in candidates:
        validate_candidate(candidate)
    ids = [str(item["candidate_id"]) for item in candidates]
    require(ids == sorted(ids) and len(ids) == len(set(ids)),
            "Probe candidate set is unordered or duplicated")
    require(len(ids) == int(prior["candidate_count"]) and
            sha256_lines(ids) == prior["candidate_set_sha256"],
            "Probe candidate identity set disagrees with P2-13")
    require(probe["candidate_set_sha256"] == probe_candidate_set_sha256(ids),
            "Probe candidate-set canonical digest is invalid")
    counts = probe["counts"]
    require(set(counts) == COUNT_FIELDS, "Probe count record is not closed")
    measured = {
        "candidates": len(candidates),
        "descriptor_parsed": sum(x["descriptor"] == "PARSED" for x in candidates),
        "descriptor_rejected": sum(x["descriptor"] == "REJECTED" for x in candidates),
        "binding_pass": sum(x["binding"] == "PASS" for x in candidates),
        "binding_rejected": sum(x["binding"] == "REJECTED" for x in candidates),
        "semantic_distinct": len({x["semantic_sha256"] for x in candidates
                                  if x["semantic_sha256"] is not None}),
    }
    require(counts == measured, "Probe candidate aggregates disagree with detail")
    compatible_signatures = {x["semantic_sha256"] for x in candidates
                             if x["binding"] == "PASS"}
    rejected_descriptor = measured["descriptor_rejected"]
    if not compatible_signatures:
        resolution, basis = "UNRESOLVED", "NO_PRODUCTION_COMPATIBLE_CANDIDATE"
    elif rejected_descriptor:
        resolution, basis = "AMBIGUOUS", "UNREADABLE_CANDIDATE_OPEN"
    elif len(compatible_signatures) == 1:
        resolution, basis = "RESOLVED", "SINGLE_COMPATIBLE_SEMANTIC_CLASS"
    else:
        resolution, basis = "AMBIGUOUS", "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"
    return {
        "asset_id": prior["asset_id"],
        "family": prior["family"],
        "structure": prior["structure"],
        "prior_resolution": prior["resolution"],
        "prior_resolution_basis": prior["resolution_basis"],
        "candidate_count": len(candidates),
        "candidate_set_sha256": prior["candidate_set_sha256"],
        "candidate_identity_exact": True,
        "production_binder_used": True,
        "heuristic_selection": False,
        "candidate_selected": False,
        "candidates": candidates,
        "counts": measured,
        "compatible_semantic_variants": len(compatible_signatures),
        "resolution": resolution,
        "resolution_basis": basis,
    }


def file_binding(root: Path, path: Path, tracked: bool,
                 advertised_path: str | None = None) -> dict[str, Any]:
    return {
        "path": advertised_path or path.resolve().relative_to(root).as_posix(),
        "tracked": tracked,
        "bytes": path.stat().st_size,
        "lines": sum(1 for _ in path.open("rb")),
        "sha256": sha256_file(path),
    }


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    policy_path = root / "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json"
    policy = load_json(policy_path)
    asset_workset_binding = dict(policy["scope"]["base_workset"])
    asset_workset_binding["lines"] = asset_workset_binding.pop("targets")
    workset = validate_bound_export(root, {"binding": asset_workset_binding},
                                    "binding", 21494)
    selected = load_selected_workset(workset)
    observed: dict[str, dict[str, Any]] = {}
    for probe in iter_jsonl(Path(args.probe_jsonl)):
        asset_id = str(probe.get("asset_id", ""))
        require(asset_id in selected and asset_id not in observed,
                "Probe target is outside scope or duplicated")
        observed[asset_id] = classify_probe(selected[asset_id], probe)
    require(set(observed) == set(selected), "Probe target scope is incomplete")
    records = [observed[key] for key in sorted(observed)]
    detail_path = Path(args.detail_output)
    write_text(detail_path, "\n".join(canonical_json(item) for item in records) + "\n")

    aggregate = collections.Counter()
    basis_targets: collections.Counter[str] = collections.Counter()
    basis_edges: collections.Counter[str] = collections.Counter()
    family_targets: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    prior_basis: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    prior_resolution_targets: collections.Counter[str] = collections.Counter()
    prior_resolution_edges: collections.Counter[str] = collections.Counter()
    for item in records:
        aggregate["targets"] += 1
        aggregate["candidate_edges"] += item["candidate_count"]
        aggregate["descriptor_parsed"] += item["counts"]["descriptor_parsed"]
        aggregate["descriptor_rejected"] += item["counts"]["descriptor_rejected"]
        aggregate["binding_pass"] += item["counts"]["binding_pass"]
        aggregate["binding_rejected"] += item["counts"]["binding_rejected"]
        aggregate[item["resolution"].lower()] += 1
        basis_targets[item["resolution_basis"]] += 1
        basis_edges[item["resolution_basis"]] += item["candidate_count"]
        family_targets[item["family"]][item["resolution"].lower()] += 1
        family_targets[item["family"]]["targets"] += 1
        family_targets[item["family"]]["candidate_edges"] += item["candidate_count"]
        prior_basis[item["prior_resolution_basis"]]["targets"] += 1
        prior_basis[item["prior_resolution_basis"]]["candidate_edges"] += item["candidate_count"]
        prior_basis[item["prior_resolution_basis"]][item["resolution"].lower()] += 1
        prior_resolution_targets[item["prior_resolution"].lower()] += 1
        prior_resolution_edges[item["prior_resolution"].lower()] += item["candidate_count"]

    frozen_targets = policy["scope"]["base_workset"]["resolution_targets"]
    frozen_edges = policy["scope"]["base_workset"]["resolution_edges"]
    reconciled_targets = {
        state: int(frozen_targets[state]) - prior_resolution_targets[state] + aggregate[state]
        for state in ("resolved", "ambiguous", "unresolved")
    }
    reconciled_targets["unknown"] = int(frozen_targets["unknown"])
    reconciled_edges = {
        state: int(frozen_edges[state]) - prior_resolution_edges[state] + basis_edges[
            {"resolved": "SINGLE_COMPATIBLE_SEMANTIC_CLASS",
             "ambiguous": "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES",
             "unresolved": "NO_PRODUCTION_COMPATIBLE_CANDIDATE"}[state]
        ] for state in ("resolved", "ambiguous", "unresolved")
    }
    reconciled_edges["unknown"] = int(frozen_edges["unknown"])
    require(sum(reconciled_targets.values()) == int(policy["scope"]["base_workset"]["targets"]),
            "Reconciled full target workset does not close")
    require(sum(reconciled_edges.values()) == 39351,
            "Reconciled full candidate-edge workset does not close")

    captured = args.captured_utc
    if not captured:
        captured = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    input_paths = [
        root / "Data/Inventory/p2-03-package-dependency-graph.json",
        root / "Data/Inventory/p2-12-full-asset-inventory.json",
        root / "Data/Inventory/p2-13-reference-closure.json",
        workset,
        policy_path,
        root / "Contracts/data-schema/g2-asset-descriptor-diagnostics-v1.schema.json",
    ]
    bindings = [file_binding(root, path, not path.is_relative_to(root / "Data/Exports"))
                for path in input_paths]
    report = {
        "schema_version": 1,
        "evidence_revision": "P2-20A.4",
        "captured_utc": captured,
        "source_build": "qy-3.0.0.413",
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "diagnostic_scope_complete": True,
        "g2_06_satisfied": False,
        "p3_authorized": False,
        "input_bindings": bindings,
        "scope": {
            "selection": "all coarse-equivalent, divergent, zero-valid, and unique SKEM production-binding obligations",
            "targets": aggregate["targets"],
            "candidate_edges": aggregate["candidate_edges"],
            "candidate_identity_exact": True,
            "production_binder_used": True,
            "first_candidate_selection_used": False,
        },
        "measured": {
            "descriptor_parsed_candidates": aggregate["descriptor_parsed"],
            "descriptor_rejected_candidates": aggregate["descriptor_rejected"],
            "binding_pass_candidates": aggregate["binding_pass"],
            "binding_rejected_candidates": aggregate["binding_rejected"],
            "resolved_targets": aggregate["resolved"],
            "ambiguous_targets": aggregate["ambiguous"],
            "unresolved_targets": aggregate["unresolved"],
            "by_resolution_basis_targets": dict(sorted(basis_targets.items())),
            "by_resolution_basis_edges": dict(sorted(basis_edges.items())),
            "by_prior_resolution_basis": {
                key: dict(sorted(value.items())) for key, value in sorted(prior_basis.items())
            },
            "by_family": {key: dict(sorted(value.items()))
                          for key, value in sorted(family_targets.items())},
            "reconciled_full_workset": {
                "targets": sum(reconciled_targets.values()),
                "candidate_edges": sum(reconciled_edges.values()),
                "resolved_targets": reconciled_targets["resolved"],
                "ambiguous_targets": reconciled_targets["ambiguous"],
                "unresolved_targets": reconciled_targets["unresolved"],
                "unknown_targets": reconciled_targets["unknown"],
                "resolved_edges": reconciled_edges["resolved"],
                "ambiguous_edges": reconciled_edges["ambiguous"],
                "unresolved_edges": reconciled_edges["unresolved"],
                "unknown_edges": reconciled_edges["unknown"],
            },
        },
        "completion": {
            "required_ambiguous_targets": 0,
            "required_unresolved_targets": 0,
            "observed_ambiguous_targets": aggregate["ambiguous"],
            "observed_unresolved_targets": aggregate["unresolved"],
            "satisfied": aggregate["ambiguous"] == 0 and aggregate["unresolved"] == 0,
            "g2_remains_blocked_by_other_open_criteria": True,
        },
        "detail_export": file_binding(
            root, detail_path, False,
            "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl"),
        "disclosure": {
            "anonymous_identities_only": True,
            "private_source_paths": False,
            "exact_primary_keys": False,
            "raw_table_rows": False,
            "decoded_confidential_payloads": False,
            "legacy_source_lines": False,
        },
    }
    report_path = Path(args.json_output)
    write_text(report_path, json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    markdown = [
        "# P2-20A.4 Full-semantic descriptor diagnostics",
        "",
        f"- Review execution: **{report['review_execution_result']}**",
        f"- G2-06 status: **{report['result']}**",
        f"- Diagnostic scope: {aggregate['targets']:,} targets / {aggregate['candidate_edges']:,} candidate edges",
        f"- Production-compatible candidates: {aggregate['binding_pass']:,}",
        f"- Production-rejected candidates: {aggregate['binding_rejected']:,}",
        f"- Resolved targets: {aggregate['resolved']:,}",
        f"- Ambiguous targets: {aggregate['ambiguous']:,}",
        f"- Unresolved targets: {aggregate['unresolved']:,}",
        f"- Former divergent targets now resolved: {prior_basis['DIVERGENT_DESCRIPTOR_SET']['resolved']:,}",
        f"- Former coarse-equivalent targets now ambiguous: {prior_basis['EQUIVALENT_VALID_DESCRIPTOR_SET']['ambiguous']:,}",
        "",
        "This evidence revalidates candidate identity and full semantic descriptors through production binders. "
        "It does not select a representative candidate and does not authorize G2, P3, playability, deletion, or release.",
        "",
    ]
    write_text(Path(args.markdown_output), "\n".join(markdown))
    return {
        "result": report["result"],
        "review_execution_result": report["review_execution_result"],
        "targets": aggregate["targets"],
        "candidate_edges": aggregate["candidate_edges"],
        "resolved": aggregate["resolved"],
        "ambiguous": aggregate["ambiguous"],
        "unresolved": aggregate["unresolved"],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    prep = sub.add_parser("prepare")
    prep.add_argument("--root", required=True)
    prep.add_argument("--asset-tsv", required=True)
    prep.add_argument("--candidate-tsv", required=True)
    final = sub.add_parser("finalize")
    final.add_argument("--root", required=True)
    final.add_argument("--probe-jsonl", required=True)
    final.add_argument("--detail-output", required=True)
    final.add_argument("--json-output", required=True)
    final.add_argument("--markdown-output", required=True)
    final.add_argument("--captured-utc")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        result = run_self_test(classify_probe, probe_candidate_set_sha256, sha256_lines)
    elif args.command == "prepare":
        result = prepare(args)
    elif args.command == "finalize":
        result = finalize(args)
    else:
        raise ValueError("A command is required")
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
