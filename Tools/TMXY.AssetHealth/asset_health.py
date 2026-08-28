#!/usr/bin/env python3
"""Build deterministic P2-14 duplicate and root-reachability classifications."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def stable_id(namespace: str, *parts: str) -> str:
    return sha256_bytes((namespace + "\0" + "\0".join(parts)).encode("utf-8"))


def iter_json_lines(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        for line in stream:
            if line.strip():
                yield json.loads(line)


class ReportWriter:
    def __init__(self, path: Path) -> None:
        self.stream = path.open("wb")
        self.digest = hashlib.sha256()
        self.bytes = 0
        self.lines = 0
        self.records: collections.Counter[str] = collections.Counter()

    def emit(self, value: dict[str, Any]) -> None:
        data = (canonical_json(value) + "\n").encode("utf-8")
        self.stream.write(data)
        self.digest.update(data)
        self.bytes += len(data)
        self.lines += 1
        self.records[str(value["record"])] += 1

    def close(self) -> dict[str, Any]:
        self.stream.close()
        return {
            "bytes": self.bytes,
            "lines": self.lines,
            "sha256": self.digest.hexdigest(),
            "records": dict(sorted(self.records.items())),
        }


def load_assets(path: Path) -> list[dict[str, Any]]:
    assets: list[dict[str, Any]] = []
    for entry in iter_json_lines(path):
        asset_path = str(entry["path"])
        source_hash = str(entry["sha256"])
        assets.append(
            {
                "id": stable_id("asset", asset_path, source_hash),
                "path": asset_path,
                "source_sha256": source_hash,
                "bytes": int(entry["bytes"]),
                "family": str(entry["family"]),
                "format_contract": str(entry["format_contract"]),
                "structure": str(entry["structure"]),
                "metrics": entry["metrics"],
            }
        )
    assets.sort(key=lambda item: item["path"])
    return assets


def load_reachability(path: Path) -> tuple[set[str], dict[str, set[str]], dict[str, set[str]]]:
    roots: set[str] = set()
    adjacency: dict[str, set[str]] = collections.defaultdict(set)
    asset_sources: dict[str, set[str]] = collections.defaultdict(set)
    traversable = {
        "table_domain_edge",
        "table_fk_edge",
        "table_package_edge",
        "package_edge",
        "package_asset_edge",
    }
    for entry in iter_json_lines(path):
        record = str(entry["record"])
        if record == "root":
            roots.add(str(entry["target"]))
            continue
        if record not in traversable:
            continue
        source = str(entry["source"])
        targets = (
            [str(item) for item in entry["targets"]]
            if "targets" in entry
            else [str(entry["target"])]
        )
        for target in targets:
            adjacency[source].add(target)
            if record == "package_asset_edge":
                asset_sources[target].add(source)
    return roots, adjacency, asset_sources


def reachable_from(roots: set[str], adjacency: dict[str, set[str]]) -> set[str]:
    visited = set(roots)
    frontier = list(sorted(roots))
    while frontier:
        source = frontier.pop()
        for target in adjacency.get(source, ()):
            if target not in visited:
                visited.add(target)
                frontier.append(target)
    return visited


def group_duplicates(
    assets: list[dict[str, Any]],
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, list[dict[str, Any]]]]:
    by_source_hash: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    by_signature: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for asset in assets:
        by_source_hash[asset["source_sha256"]].append(asset)
        if asset["structure"] != "PASS":
            continue
        signature = sha256_bytes(
            canonical_json(
                {
                    "bytes": asset["bytes"],
                    "family": asset["family"],
                    "format_contract": asset["format_contract"],
                    "metrics": asset["metrics"],
                }
            ).encode("utf-8")
        )
        by_signature[signature].append(asset)
    exact = {key: value for key, value in by_source_hash.items() if len(value) > 1}
    structural = {
        key: value
        for key, value in by_signature.items()
        if len(value) > 1 and len({item["source_sha256"] for item in value}) > 1
    }
    return exact, structural


def summarize_duplicates(
    exact: dict[str, list[dict[str, Any]]],
    structural: dict[str, list[dict[str, Any]]],
) -> dict[str, Any]:
    exact_files = sum(len(group) for group in exact.values())
    redundant_files = sum(len(group) - 1 for group in exact.values())
    redundant_bytes = sum(group[0]["bytes"] * (len(group) - 1) for group in exact.values())
    structural_files = len({item["id"] for group in structural.values() for item in group})
    families = sorted(
        {item["family"] for group in exact.values() for item in group}
        | {item["family"] for group in structural.values() for item in group}
    )
    by_family: dict[str, dict[str, int]] = {}
    for family in families:
        exact_family_groups = [
            [item for item in group if item["family"] == family]
            for group in exact.values()
            if any(item["family"] == family for item in group)
        ]
        structural_family_groups = [
            group for group in structural.values() if group[0]["family"] == family
        ]
        by_family[family] = {
            "exact_groups": len(exact_family_groups),
            "exact_files": sum(len(group) for group in exact_family_groups),
            "redundant_files_within_family": sum(
                max(0, len(group) - 1) for group in exact_family_groups
            ),
            "redundant_bytes_within_family": sum(
                group[0]["bytes"] * max(0, len(group) - 1)
                for group in exact_family_groups
            ),
            "structural_review_groups": len(structural_family_groups),
            "structural_review_files": len(
                {item["id"] for group in structural_family_groups for item in group}
            ),
        }
    return {
        "exact_groups": len(exact),
        "exact_files": exact_files,
        "redundant_files": redundant_files,
        "redundant_bytes": redundant_bytes,
        "cross_family_exact_groups": sum(
            1 for group in exact.values() if len({item["family"] for item in group}) > 1
        ),
        "structural_review_groups": len(structural),
        "structural_review_files": structural_files,
        "semantic_equivalence_proven_groups": 0,
        "by_family": by_family,
    }


def build(args: argparse.Namespace) -> dict[str, Any]:
    reference_policy = json.loads(args.reference_policy.read_text(encoding="utf-8"))
    health_policy = json.loads(args.health_policy.read_text(encoding="utf-8"))
    identity_families = {str(item["family"]) for item in reference_policy["asset_link_rules"]}
    assets = load_assets(args.catalog)
    roots, adjacency, asset_sources = load_reachability(args.closure)
    reachable = reachable_from(roots, adjacency)
    exact, structural = group_duplicates(assets)
    exact_ids = {
        item["id"]: stable_id("exact-duplicate", source_hash)
        for source_hash, group in exact.items()
        for item in group
    }
    structural_ids = {
        item["id"]: stable_id("structural-review", signature)
        for signature, group in structural.items()
        for item in group
    }
    reference_counts: collections.Counter[str] = collections.Counter()
    family_counts: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    writer = ReportWriter(args.output)
    try:
        for asset in assets:
            link_count = len(asset_sources.get(asset["id"], ()))
            if asset["id"] in reachable:
                state = "root_reachable"
            elif link_count:
                state = "linked_outside_declared_roots"
            elif asset["family"] in identity_families:
                state = "unlinked_identity_rule_no_match"
            else:
                state = "unlinked_no_identity_rule"
            reference_counts[state] += 1
            family_counts[asset["family"]][state] += 1
            writer.emit(
                {
                    "bytes": asset["bytes"],
                    "delete_eligible": False,
                    "exact_duplicate_group": exact_ids.get(asset["id"], ""),
                    "family": asset["family"],
                    "id": asset["id"],
                    "package_link_candidates": link_count,
                    "path": asset["path"],
                    "record": "asset_health",
                    "reference_state": state,
                    "source_sha256": asset["source_sha256"],
                    "structural_review_group": structural_ids.get(asset["id"], ""),
                    "structure": asset["structure"],
                }
            )
        for source_hash, group in sorted(exact.items()):
            writer.emit(
                {
                    "bytes_each": group[0]["bytes"],
                    "delete_eligible": False,
                    "distinct_families": len({item["family"] for item in group}),
                    "id": stable_id("exact-duplicate", source_hash),
                    "members": sorted(item["id"] for item in group),
                    "record": "exact_duplicate_group",
                    "redundant_bytes": group[0]["bytes"] * (len(group) - 1),
                    "source_sha256": source_hash,
                }
            )
        for signature, group in sorted(structural.items()):
            writer.emit(
                {
                    "delete_eligible": False,
                    "distinct_source_hashes": len({item["source_sha256"] for item in group}),
                    "family": group[0]["family"],
                    "id": stable_id("structural-review", signature),
                    "members": sorted(item["id"] for item in group),
                    "record": "structural_review_group",
                    "semantic_equivalence_proven": False,
                    "signature_sha256": signature,
                }
            )
        report = writer.close()
    except Exception:
        writer.stream.close()
        raise
    return {
        "result": "PASS",
        "report": report,
        "assets": {
            "files": len(assets),
            "bytes": sum(item["bytes"] for item in assets),
            "reference_states": dict(sorted(reference_counts.items())),
            "by_family": {
                key: dict(sorted(value.items())) for key, value in sorted(family_counts.items())
            },
            "root_count": len(roots),
            "root_reachable_graph_nodes": len(reachable),
        },
        "duplicates": summarize_duplicates(exact, structural),
        "identity_rule_families": sorted(identity_families),
        "deletion_recommendations": 0,
        "semantic_equivalence_claims_without_digest": 0,
        "policy_reference_states": list(health_policy["reference_states"]),
    }


def self_test() -> int:
    assertions = 0
    assertions += int(stable_id("x", "a") == stable_id("x", "a"))
    assertions += int(stable_id("x", "a") != stable_id("x", "b"))
    assertions += int(canonical_json({"b": 1, "a": 2}) == '{"a":2,"b":1}')
    sample = [
        {"id": "a", "source_sha256": "h", "bytes": 1, "family": "qtx", "format_contract": "x", "structure": "PASS", "metrics": {"w": 1}},
        {"id": "b", "source_sha256": "h", "bytes": 1, "family": "qtx", "format_contract": "x", "structure": "PASS", "metrics": {"w": 1}},
        {"id": "c", "source_sha256": "i", "bytes": 1, "family": "qtx", "format_contract": "x", "structure": "PASS", "metrics": {"w": 1}},
    ]
    exact, structural = group_duplicates(sample)
    assertions += int(len(exact) == 1)
    assertions += int(len(structural) == 1)
    assertions += int(summarize_duplicates(exact, structural)["redundant_files"] == 1)
    assertions += int(reachable_from({"a"}, {"a": {"b"}, "b": {"c"}}) == {"a", "b", "c"})
    assertions += int(summarize_duplicates(exact, structural)["semantic_equivalence_proven_groups"] == 0)
    expected = 8
    print(canonical_json({"assertions": assertions, "result": "PASS" if assertions == expected else "FAIL"}))
    return 0 if assertions == expected else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--closure", type=Path)
    parser.add_argument("--reference-policy", type=Path)
    parser.add_argument("--health-policy", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if any(value is None for value in (args.catalog, args.closure, args.reference_policy, args.health_policy, args.output)):
        parser.error("all input and output arguments are required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(canonical_json(build(args)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
