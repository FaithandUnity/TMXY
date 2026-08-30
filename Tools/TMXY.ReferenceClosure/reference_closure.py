#!/usr/bin/env python3
"""Build the deterministic, value-redacted P2-13 cross-domain reference closure."""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path, PurePosixPath
from typing import Any

from reference_closure_core import (
    GraphWriter,
    ascii_lower,
    candidate_ascii_lower_hashes,
    canonical_json,
    condition_matches,
    is_inactive,
    iter_json_lines,
    load_package_nodes,
    load_table_indexes,
    row_id,
    sha256_bytes,
    stable_id,
    table_export_path,
    typed_key,
)


def emit_assets(
    catalog_path: Path,
    policy: dict[str, Any],
    package_by_lower: dict[str, list[dict[str, Any]]],
    package_by_basename: dict[str, list[dict[str, Any]]],
    writer: GraphWriter,
) -> dict[str, Any]:
    rules = {str(item["family"]): item for item in policy["asset_link_rules"]}
    family_stats: dict[str, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    link_edges = 0
    catalog_candidate_mismatches = 0
    for asset in iter_json_lines(catalog_path):
        family = str(asset["family"])
        path = str(asset["path"])
        asset_id = stable_id("asset", path, str(asset["sha256"]))
        writer.emit(
            {
                "family": family,
                "id": asset_id,
                "path": path,
                "record": "asset_node",
                "sha256": str(asset["sha256"]),
                "structure": str(asset["structure"]),
            }
        )
        stats = family_stats[family]
        stats["files"] += 1
        stats[f"structure_{str(asset['structure']).lower()}"] += 1
        candidates: list[dict[str, Any]] = []
        rule = rules.get(family)
        if rule is not None and rule["method"] == "logical-name-ascii-lower":
            source = PurePosixPath(path)
            logical_name = f"{source.parent.name}.{source.stem}"
            logical_hash = candidate_ascii_lower_hashes(logical_name)[0]
            allowed = set(str(item) for item in rule["expected_classes"])
            candidates = [
                item for item in package_by_lower.get(logical_hash, []) if item["class"] in allowed
            ]
            if (
                family in {"qtx", "sm", "skem", "anim"}
                and str(asset["structure"]) != "FAIL"
                and len(candidates) != int(asset["package_candidates"])
            ):
                catalog_candidate_mismatches += 1
        elif rule is not None and rule["method"] == "path-segment-package-basename":
            segments = path.split("/")
            segment_index = int(rule["path_segment"])
            if segment_index < len(segments):
                basename = PurePosixPath(segments[segment_index]).stem.lower()
                allowed = set(str(item) for item in rule["expected_classes"])
                prefix = str(rule["package_prefix"])
                candidates = [
                    item
                    for item in package_by_basename.get(basename, [])
                    if item["class"] in allowed and item["package"].startswith(prefix)
                ]
        candidates = sorted({item["id"]: item for item in candidates}.values(), key=lambda x: x["id"])
        if not candidates:
            stats["unlinked"] += 1
        elif len(candidates) == 1:
            stats["linked_unique"] += 1
        else:
            stats["linked_ambiguous"] += 1
        for candidate in candidates:
            link_edges += 1
            writer.emit(
                {
                    "family": family,
                    "record": "package_asset_edge",
                    "source": candidate["id"],
                    "target": asset_id,
                }
            )
    return {
        "files": sum(value["files"] for value in family_stats.values()),
        "link_edges": link_edges,
        "catalog_candidate_mismatches": catalog_candidate_mismatches,
        "families": {
            key: dict(sorted(value.items())) for key, value in sorted(family_stats.items())
        },
    }


def emit_package_edges(
    graph_path: Path,
    package_by_lower: dict[str, list[dict[str, Any]]],
    policy: dict[str, Any],
    writer: GraphWriter,
) -> dict[str, Any]:
    terminal_kinds = set(str(item) for item in policy["terminal_package_edge_kinds"])
    resolutions: collections.Counter[str] = collections.Counter()
    recorded_resolution_mismatches = 0
    for entry in iter_json_lines(graph_path):
        if entry["record"] != "edge":
            continue
        kind = str(entry["kind"])
        if kind in terminal_kinds:
            resolution = "scoped-terminal"
            targets: list[str] = []
            expected_recorded = "logical"
        else:
            target_hash = str(entry["target_logical_name_ascii_lower_sha256"])
            targets = sorted(item["id"] for item in package_by_lower.get(target_hash, []))
            resolution = "unresolved" if not targets else "unique" if len(targets) == 1 else "ambiguous"
            expected_recorded = resolution
        if str(entry["resolution"]) != expected_recorded:
            recorded_resolution_mismatches += 1
        resolutions[resolution] += 1
        writer.emit(
            {
                "kind": kind,
                "property": str(entry["property"]),
                "record": "package_edge",
                "resolution": resolution,
                "source": str(entry["source"]),
                "target_logical_name_ascii_lower_sha256": str(
                    entry["target_logical_name_ascii_lower_sha256"]
                ),
                "targets": targets,
            }
        )
    return {
        "edges": sum(resolutions.values()),
        "resolution": dict(sorted(resolutions.items())),
        "recorded_resolution_mismatches": recorded_resolution_mismatches,
    }


def emit_table_foreign_keys(
    registry: dict[str, Any], table_root: Path, state: dict[str, Any], writer: GraphWriter
) -> dict[str, Any]:
    emitted: set[str] = set()
    physical_active = 0
    physical_inactive = 0
    dangling = 0
    for table in registry["tables"]:
        source_path = str(table["source_path"])
        source_primary = [str(item) for item in table["primary_key"]["column_ids"]]
        path = table_export_path(table_root, source_path)
        for foreign_key in table["foreign_keys"]:
            source_columns = [str(item) for item in foreign_key["source_column_ids"]]
            target_table = str(foreign_key["target_table"])
            target_columns = tuple(str(item) for item in foreign_key["target_column_ids"])
            sentinels = list(foreign_key["sentinel_values"])
            target_index = state["indexes"][(target_table, target_columns)]
            for row in iter_json_lines(path):
                values = [row.get(column) for column in source_columns]
                if is_inactive(values, sentinels):
                    physical_inactive += 1
                    continue
                physical_active += 1
                source = row_id(source_path, row, source_primary)
                target = target_index.get(typed_key(values))
                if target is None:
                    dangling += 1
                    continue
                edge_id = stable_id("table-fk", str(foreign_key["id"]), source, target)
                if edge_id in emitted:
                    continue
                emitted.add(edge_id)
                writer.emit(
                    {
                        "id": edge_id,
                        "record": "table_fk_edge",
                        "rule": str(foreign_key["id"]),
                        "source": source,
                        "target": target,
                    }
                )
    return {
        "rules": sum(len(item["foreign_keys"]) for item in registry["tables"]),
        "physical_active_references": physical_active,
        "physical_inactive_references": physical_inactive,
        "canonical_edges": len(emitted),
        "dangling": dangling,
    }


def emit_table_object_references(
    registry: dict[str, Any],
    table_root: Path,
    policy: dict[str, Any],
    package_by_lower: dict[str, list[dict[str, Any]]],
    writer: GraphWriter,
) -> dict[str, Any]:
    table_records = {str(item["source_path"]): item for item in registry["tables"]}
    policies: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for item in policy["table_object_references"]:
        policies[str(item["table"])].append(item)
    scoped: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for item in policy["table_scoped_references"]:
        scoped[str(item["table"])].append(item)
    resolution: collections.Counter[str] = collections.Counter()
    emitted: set[str] = set()
    scoped_emitted: set[str] = set()
    physical_nonempty = 0
    runtime_assert_rows = 0
    runtime_assert_missing = 0
    runtime_assert_unresolved = 0
    wrong_class_candidate_values = 0
    by_rule: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)

    for source_path in sorted(set(policies) | set(scoped)):
        table = table_records[source_path]
        primary = [str(item) for item in table["primary_key"]["column_ids"]]
        path = table_export_path(table_root, source_path)
        for row in iter_json_lines(path):
            source = row_id(source_path, row, primary)
            for reference in policies[source_path]:
                rule_id = str(reference["id"])
                value = row.get(str(reference["column_id"]))
                text = "" if value is None else str(value).strip()
                asserting = condition_matches(row, reference.get("runtime_assert_when"))
                if asserting:
                    runtime_assert_rows += 1
                if not text or text in {str(item) for item in reference["sentinel_values"]}:
                    if asserting:
                        runtime_assert_missing += 1
                    continue
                physical_nonempty += 1
                hashes = candidate_ascii_lower_hashes(text)
                all_candidates = {
                    item["id"]: item
                    for item_hash in hashes
                    for item in package_by_lower.get(item_hash, [])
                }
                expected_classes = set(str(item) for item in reference["expected_classes"])
                candidates = sorted(
                    (
                        item
                        for item in all_candidates.values()
                        if item["class"] in expected_classes
                    ),
                    key=lambda item: item["id"],
                )
                if all_candidates and not candidates:
                    wrong_class_candidate_values += 1
                result = "unresolved" if not candidates else "unique" if len(candidates) == 1 else "ambiguous"
                resolution[result] += 1
                by_rule[rule_id][result] += 1
                if asserting and result == "unresolved":
                    runtime_assert_unresolved += 1
                edge_id = stable_id("table-object", rule_id, source, ",".join(hashes))
                if edge_id in emitted:
                    continue
                emitted.add(edge_id)
                writer.emit(
                    {
                        "id": edge_id,
                        "record": "table_package_edge",
                        "resolution": result,
                        "rule": rule_id,
                        "source": source,
                        "target_logical_name_ascii_lower_sha256": hashes,
                        "targets": [item["id"] for item in candidates],
                    }
                )
            for reference in scoped[source_path]:
                value = row.get(str(reference["column_id"]))
                text = "" if value is None else str(value).strip()
                if not text:
                    continue
                hashes = candidate_ascii_lower_hashes(text)
                edge_id = stable_id(
                    "table-scoped", str(reference["id"]), source, ",".join(hashes)
                )
                if edge_id in scoped_emitted:
                    continue
                scoped_emitted.add(edge_id)
                writer.emit(
                    {
                        "id": edge_id,
                        "record": "table_scoped_edge",
                        "rule": str(reference["id"]),
                        "scope": str(reference["scope"]),
                        "source": source,
                        "target_token_ascii_lower_sha256": hashes,
                    }
                )
    return {
        "rules": len(policy["table_object_references"]),
        "physical_nonempty_references": physical_nonempty,
        "canonical_edges": len(emitted),
        "resolution": dict(sorted(resolution.items())),
        "wrong_class_candidate_values": wrong_class_candidate_values,
        "runtime_assert_rows": runtime_assert_rows,
        "runtime_assert_missing_values": runtime_assert_missing,
        "runtime_assert_unresolved_values": runtime_assert_unresolved,
        "scoped_rules": len(policy["table_scoped_references"]),
        "scoped_edges": len(scoped_emitted),
        "by_rule": {key: dict(sorted(value.items())) for key, value in sorted(by_rule.items())},
    }


def emit_roots(
    nodes: list[dict[str, Any]],
    ids_by_role: dict[str, list[str]],
    policy: dict[str, Any],
    writer: GraphWriter,
) -> dict[str, int]:
    result: dict[str, int] = {}
    for root_name in ("character", "scene"):
        classes = set(str(item) for item in policy["root_sets"][root_name]["package_classes"])
        ids = sorted(item["id"] for item in nodes if item["class"] in classes)
        result[root_name] = len(ids)
        for target in ids:
            writer.emit({"record": "root", "root_kind": root_name, "target": target})
    skill_role = str(policy["root_sets"]["skill"]["table_role"])
    skill_ids = ids_by_role[skill_role]
    result["skill"] = len(skill_ids)
    for target in skill_ids:
        writer.emit({"record": "root", "root_kind": "skill", "target": target})
    return result


def build(args: argparse.Namespace) -> dict[str, Any]:
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    registry = json.loads(args.registry.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    writer = GraphWriter(args.output)
    try:
        package_nodes, package_by_lower, package_by_basename = load_package_nodes(
            args.package_graph, writer
        )
        table_state, ids_by_role, table_counts = load_table_indexes(
            registry, args.table_root, writer
        )
        assets = emit_assets(
            args.asset_catalog,
            policy,
            package_by_lower,
            package_by_basename,
            writer,
        )
        package_edges = emit_package_edges(
            args.package_graph, package_by_lower, policy, writer
        )
        foreign_keys = emit_table_foreign_keys(
            registry, args.table_root, table_state, writer
        )
        object_references = emit_table_object_references(
            registry, args.table_root, policy, package_by_lower, writer
        )
        roots = emit_roots(package_nodes, ids_by_role, policy, writer)
        graph = writer.close()
    except Exception:
        writer.stream.close()
        raise
    return {
        "result": "PASS",
        "graph": graph,
        "roots": roots,
        "tables": {
            **table_counts,
            "table_count": len(registry["tables"]),
            "normalized_hashes_verified": len(table_state["normalized_hashes"]),
            "foreign_keys": foreign_keys,
            "object_references": object_references,
        },
        "packages": {
            "nodes": len(package_nodes),
            **package_edges,
        },
        "assets": assets,
        "raw_table_values_emitted": False,
        "raw_primary_keys_emitted": False,
        "raw_package_object_names_emitted": False,
        "heuristic_target_selections": 0,
    }


def self_test() -> int:
    assertions = 0
    assertions += int(ascii_lower(b"AbC.01") == b"abc.01")
    assertions += int(candidate_ascii_lower_hashes("Icon.Sample")[0] == sha256_bytes(b"icon.sample"))
    assertions += int(typed_key([1, "2", None]) == '[1,"2",null]')
    assertions += int(stable_id("x", "a") == stable_id("x", "a"))
    assertions += int(stable_id("x", "a") != stable_id("x", "b"))
    assertions += int(is_inactive([None, 0], [0, -1]))
    assertions += int(not is_inactive([1], [0, -1]))
    assertions += int(condition_matches({"c": 2}, {"column_id": "c", "operator": "greater-than", "value": 1}))
    assertions += int("secret" not in canonical_json({"id": stable_id("x", "secret")}))
    expected = 9
    print(canonical_json({"assertions": assertions, "result": "PASS" if assertions == expected else "FAIL"}))
    return 0 if assertions == expected else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-graph", type=Path)
    parser.add_argument("--asset-catalog", type=Path)
    parser.add_argument("--table-root", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    required = (
        args.package_graph,
        args.asset_catalog,
        args.table_root,
        args.registry,
        args.policy,
        args.output,
    )
    if any(value is None for value in required):
        parser.error("all input and output arguments are required")
    summary = build(args)
    print(canonical_json(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
