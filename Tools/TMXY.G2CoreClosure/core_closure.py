"""Monotonic A-union-B core-resource closure for P2-20A."""

from __future__ import annotations

import collections
import hashlib
import json
from pathlib import Path
from typing import Any

from core_common import canonical_json, require, sha256_lines, write_text


def select_rules(policy: dict[str, Any], reference: dict[str, Any],
                 ownership: dict[str, Any]) -> tuple[set[str], dict[str, Any]]:
    core = {(item["table"], item["column_id"]): item for item in ownership["core_columns"]}
    selected: list[dict[str, Any]] = []
    for rule in reference["table_object_references"]:
        column = core.get((rule["table"], rule["column_id"]))
        require(column is not None and column["result"] == "PASS",
                f"Resource rule is not a PASS core column: {rule['id']}")
        selected.append({
            "rule_id": rule["id"],
            "table": rule["table"],
            "column_id": rule["column_id"],
            "owner": column["owner"],
            "runtime_authority": column["runtime_authority"],
            "role": column["role"],
        })
    selected.sort(key=lambda item: item["rule_id"])
    required_count = policy["core_table_resource_scope"]["required_rule_count"]
    require(len(selected) == required_count, "Core resource rule count was narrowed")
    allowed_authorities = set(policy["core_table_resource_scope"]["include_runtime_authorities"])
    observed_authorities = {item["runtime_authority"] for item in selected}
    require(observed_authorities == allowed_authorities, "Runtime authority was filtered")
    digest = hashlib.sha256(canonical_json(selected).encode("utf-8")).hexdigest()
    return {item["rule_id"] for item in selected}, {
        "selection": "all-matching-core-resource-rules",
        "declared_rules": len(reference["table_object_references"]),
        "selected_rules": len(selected),
        "client_presentation_rules": sum(
            item["runtime_authority"] == "client-presentation" for item in selected),
        "server_authoritative_rules": sum(
            item["runtime_authority"] == "server-authoritative" for item in selected),
        "owner_filtering": "forbidden",
        "selection_sha256": digest,
    }


def edge_targets(entry: dict[str, Any]) -> list[str]:
    if "targets" in entry:
        return [str(item) for item in entry["targets"]]
    if "target" in entry:
        return [str(entry["target"])]
    return []


def logical_integrity(entry: dict[str, Any], terminal_kinds: set[str]) -> tuple[int, int]:
    resolution = str(entry.get("resolution", ""))
    targets = edge_targets(entry)
    unknown = int(resolution not in {"unique", "ambiguous", "unresolved", "scoped-terminal"})
    heuristic = int(any(key in entry for key in ("selected_target", "chosen_target")))
    if resolution == "unique" and len(targets) != 1:
        heuristic += 1
    elif resolution == "ambiguous" and len(targets) < 2:
        heuristic += 1
    elif resolution == "unresolved" and targets:
        heuristic += 1
    elif resolution == "scoped-terminal":
        if entry["record"] != "package_edge" or entry.get("kind") not in terminal_kinds or targets:
            heuristic += 1
    return unknown, heuristic


def build_graph(graph_path: Path, selected_rules: set[str], policy: dict[str, Any],
                reference_policy: dict[str, Any]) -> dict[str, Any]:
    traversable = set(policy["traversal"]["edge_records"])
    known_records = traversable | set(policy["traversal"]["known_nontraversed_records"])
    logical_records = set(policy["traversal"]["logical_resolution_records"])
    terminal_kinds = set(reference_policy["terminal_package_edge_kinds"])
    roots_by_kind: dict[str, set[str]] = collections.defaultdict(set)
    field_sources: set[str] = set()
    node_kind: dict[str, str] = {}
    asset_structure: dict[str, str] = {}
    adjacency: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    scoped_edges: list[tuple[str, str]] = []
    unknown_records = 0
    unknown_resolutions = 0
    heuristic_selections = 0
    asset_binding_edges = 0
    asset_binding_with_resolution = 0

    with graph_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            entry = json.loads(line)
            record = str(entry["record"])
            if record not in known_records:
                unknown_records += 1
                continue
            if record == "root":
                roots_by_kind[str(entry["root_kind"])].add(str(entry["target"]))
            elif record.endswith("_node"):
                node_kind[str(entry["id"])] = record
                if record == "asset_node":
                    asset_structure[str(entry["id"])] = str(entry["structure"])
            elif record == "table_scoped_edge":
                scoped_edges.append((str(entry["source"]), str(entry["rule"])))
            elif record in traversable:
                if record == "table_package_edge":
                    require(str(entry["rule"]) in selected_rules,
                            "Graph contains a table resource rule outside the selected authority set")
                    field_sources.add(str(entry["source"]))
                if record in logical_records:
                    unknown, heuristic = logical_integrity(entry, terminal_kinds)
                    unknown_resolutions += unknown
                    heuristic_selections += heuristic
                if record == "package_asset_edge":
                    asset_binding_edges += 1
                    asset_binding_with_resolution += int("resolution" in entry)
                adjacency[str(entry["source"])].append({
                    "record": record,
                    "rule": str(entry.get("rule", entry.get("kind", entry.get("family", "")))),
                    "resolution": str(entry.get("resolution", "resolved")),
                    "targets": edge_targets(entry),
                })

    expected_kinds = set(policy["declared_root_scope"]["root_kinds"])
    require(set(roots_by_kind) == expected_kinds, "Declared root kinds were narrowed or expanded")
    declared_roots = set().union(*(roots_by_kind[kind] for kind in sorted(expected_kinds)))
    starts = declared_roots | field_sources
    reachable = set(starts)
    frontier = list(sorted(starts))
    while frontier:
        source = frontier.pop()
        for edge in adjacency.get(source, []):
            for target in edge["targets"]:
                if target and target not in reachable:
                    reachable.add(target)
                    frontier.append(target)

    node_counts: collections.Counter[str] = collections.Counter()
    edge_counts: collections.Counter[str] = collections.Counter()
    resolutions: collections.Counter[str] = collections.Counter()
    gaps: list[dict[str, Any]] = []
    asset_counts: collections.Counter[str] = collections.Counter()
    for identity in reachable:
        kind = node_kind.get(identity, "terminal")
        node_counts[kind] += 1
        if kind == "asset_node":
            asset_counts[asset_structure[identity].lower()] += 1
        for edge in adjacency.get(identity, []):
            edge_counts[edge["record"]] += 1
            if edge["record"] in logical_records:
                resolutions[f"{edge['record']}:{edge['resolution']}"] += 1
                if edge["resolution"] in {"unresolved", "ambiguous"}:
                    gaps.append({
                        "record": "logical_gap",
                        "edge_record": edge["record"],
                        "rule": edge["rule"],
                        "resolution": edge["resolution"],
                        "source": identity,
                        "targets": edge["targets"],
                    })

    gap_lines = [canonical_json(item) for item in gaps]
    root_counts = {kind: len(roots_by_kind[kind]) for kind in sorted(expected_kinds)}
    require(len(declared_roots) == sum(root_counts.values()), "Declared roots overlap unexpectedly")
    asset_binding_explicit = asset_binding_edges > 0 and asset_binding_edges == asset_binding_with_resolution
    return {
        "roots": declared_roots,
        "root_counts": root_counts,
        "field_sources": field_sources,
        "starts": starts,
        "reachable": reachable,
        "node_kind": node_kind,
        "asset_structure": asset_structure,
        "node_counts": dict(sorted(node_counts.items())),
        "edge_counts": dict(sorted(edge_counts.items())),
        "resolutions": resolutions,
        "gaps": gaps,
        "gap_lines": gap_lines,
        "scoped_context_edges": sum(source in reachable for source, _ in scoped_edges),
        "unknown_records": unknown_records,
        "unknown_resolutions": unknown_resolutions,
        "heuristic_selections": heuristic_selections,
        "asset_binding_explicit": asset_binding_explicit,
        "asset_counts": asset_counts,
    }


def write_detail(path: Path, graph: dict[str, Any], roots_by_target: dict[str, list[str]]) -> dict[str, Any]:
    records: list[str] = []
    field_sources = graph["field_sources"]
    for identity in sorted(graph["starts"]):
        authorities: list[str] = []
        authorities.extend(f"declared-root:{kind}" for kind in roots_by_target.get(identity, []))
        if identity in field_sources:
            authorities.append("core-table-resource-row")
        records.append(canonical_json({
            "record": "scope_start", "id": identity, "authorities": sorted(authorities),
        }))
    for identity in sorted(graph["reachable"]):
        records.append(canonical_json({
            "record": "reachable_node", "id": identity,
            "node_kind": graph["node_kind"].get(identity, "terminal"),
        }))
    records.extend(sorted(graph["gap_lines"]))
    for identity in sorted(graph["reachable"]):
        structure = graph["asset_structure"].get(identity)
        if structure in {"UNRESOLVED", "FAIL"}:
            records.append(canonical_json({
                "record": "asset_structure_gap", "id": identity, "structure": structure,
            }))
    write_text(path, "\n".join(records) + "\n")
    payload = path.read_bytes()
    return {
        "path": "Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl",
        "tracked": False,
        "bytes": len(payload),
        "lines": len(records),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def summarize(graph: dict[str, Any], p213: dict[str, Any], detail: dict[str, Any],
              p213_binding: dict[str, Any], p206_binding: dict[str, Any],
              workset: dict[str, Any]) -> dict[str, Any]:
    resolution = graph["resolutions"]
    table_unresolved = resolution["table_package_edge:unresolved"]
    table_ambiguous = resolution["table_package_edge:ambiguous"]
    package_unresolved = resolution["package_edge:unresolved"]
    package_ambiguous = resolution["package_edge:ambiguous"]
    logical_gaps = table_unresolved + table_ambiguous + package_unresolved + package_ambiguous
    runtime = p213["table_closure"]["object_references"]
    health = p213["health"]
    require(runtime["runtime_assert_rows"] == health["legacy_runtime_assert_rows"],
            "P2-13 conditional-required row aggregates disagree")
    require(runtime["runtime_assert_missing_values"] ==
            health["legacy_runtime_assert_missing_values"],
            "P2-13 conditional-required missing aggregates disagree")
    require(runtime["runtime_assert_unresolved_values"] ==
            health["legacy_runtime_assert_unresolved_values"],
            "P2-13 conditional-required unresolved aggregates disagree")
    require(p213_binding["id"] == "P2-13", "Conditional-required source is not P2-13")
    require(p206_binding["id"] == "P2-06", "Conditional member source is not P2-06")
    require(workset["runtime_assert_rows"] == runtime["runtime_assert_rows"] and
            workset["conditional_required_missing"] == runtime["runtime_assert_missing_values"],
            "Conditional-required workset does not reproduce P2-13 aggregates")
    return {
        "scope_complete": False,
        "auxiliary_config_reference_scope_complete": False,
        "asset_binding_resolution_explicit": graph["asset_binding_explicit"],
        "start_nodes": len(graph["starts"]),
        "start_set_sha256": sha256_lines(graph["starts"]),
        "reachable_nodes": len(graph["reachable"]),
        "reachable_set_sha256": sha256_lines(graph["reachable"]),
        "reachable_nodes_by_kind": graph["node_counts"],
        "traversed_edges_by_kind": graph["edge_counts"],
        "resolution": {
            "table_unique": resolution["table_package_edge:unique"],
            "table_unresolved": table_unresolved,
            "table_ambiguous": table_ambiguous,
            "package_unique": resolution["package_edge:unique"],
            "package_unresolved": package_unresolved,
            "package_ambiguous": package_ambiguous,
            "package_scoped_terminal": resolution["package_edge:scoped-terminal"],
            "heuristic_target_selections": graph["heuristic_selections"],
        },
        "conditional_required": {
            "runtime_assert_rows": runtime["runtime_assert_rows"],
            "conditional_required_missing": runtime["runtime_assert_missing_values"],
            "conditional_required_unresolved": runtime["runtime_assert_unresolved_values"],
            "source_inventory_id": "P2-13",
            "source_inventory_sha256": p213_binding["sha256"],
            "member_source_inventory_id": "P2-06",
            "member_source_inventory_sha256": p206_binding["sha256"],
            "member_source_file_count": workset["member_source_file_count"],
            "member_source_file_set_sha256": workset["member_source_file_set_sha256"],
            "member_set_exported": True,
            "member_set_count": workset["member_set_count"],
            "member_set_sha256": workset["member_set_sha256"],
            "zero_threshold_satisfied": runtime["runtime_assert_missing_values"] == 0,
        },
        "asset_structure": {
            "pass": graph["asset_counts"]["pass"],
            "unresolved": graph["asset_counts"]["unresolved"],
            "fail": graph["asset_counts"]["fail"],
        },
        "integrity": {
            "unknown_record_count": graph["unknown_records"],
            "unknown_resolution_count": graph["unknown_resolutions"],
            "recorded_resolution_mismatches": p213["package_closure"]["recorded_resolution_mismatches"],
            "catalog_candidate_mismatches": p213["asset_closure"]["catalog_candidate_mismatches"],
            "core_foreign_key_dangling": p213["health"]["core_dangling_references"],
        },
        "logical_gap_count": logical_gaps,
        "gap_set_sha256": sha256_lines(graph["gap_lines"]),
        "detail_export": detail,
    }
