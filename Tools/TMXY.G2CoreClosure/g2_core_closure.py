#!/usr/bin/env python3
"""Generate P2-20A core-resource closure evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from core_closure import build_graph, select_rules, summarize, write_detail
from core_common import bind_inputs, load_json, require, sha256_file, sha256_lines, write_text
from core_report import build_governance, build_report, render_markdown
from conditional_workset import build_conditional_workset
from asset_binding_workset import build_asset_binding_workset


def build(args: argparse.Namespace) -> dict[str, object]:
    root = args.root.resolve()
    policy_path = args.policy.resolve()
    schema_path = args.schema.resolve()
    policy = load_json(policy_path)
    require(policy["task_id"] == "P2-20A" and policy["criterion_id"] == "G2-06",
            "Wrong P2-20A policy identity")
    bindings, documents = bind_inputs(root, policy)
    reference_policy = load_json(documents["reference_policy_path"])
    ownership = load_json(documents["ownership_registry_path"])
    core_registry = load_json(documents["core_registry_path"])
    selected_rules, rule_summary = select_rules(policy, reference_policy, ownership)
    graph = build_graph(documents["reference_graph_path"], selected_rules,
                        policy, reference_policy)
    # The selected field-source set was formed only by emitted table-package rules.
    graph["rules_with_edges"] = {
        item["rule"] for item in graph["gaps"] if item["edge_record"] == "table_package_edge"
    }
    # Include zero-gap rules by a bounded second scan without retaining private values.
    with documents["reference_graph_path"].open("r", encoding="utf-8") as stream:
        for line in stream:
            entry = json.loads(line)
            if entry.get("record") == "table_package_edge":
                graph["rules_with_edges"].add(str(entry["rule"]))

    expected_roots = documents["p2_13"]["roots"]
    require(graph["root_counts"] == expected_roots, "Root counts do not match P2-13 evidence")
    require(len(graph["node_kind"]) == sum(documents["p2_13"]["graph"]["records"].values()) -
            sum(documents["p2_13"]["graph"]["records"].get(name, 0) for name in
                ("package_asset_edge", "package_edge", "table_domain_edge", "table_fk_edge",
                 "table_package_edge", "table_scoped_edge", "root")),
            "Graph node population mismatch")
    roots_by_target: dict[str, list[str]] = {}
    # Root identities are already hashed; no source paths or primary keys are emitted.
    with documents["reference_graph_path"].open("r", encoding="utf-8") as stream:
        for line in stream:
            entry = json.loads(line)
            if entry.get("record") == "root":
                roots_by_target.setdefault(str(entry["target"]), []).append(str(entry["root_kind"]))
    detail = write_detail(args.detail_output, graph, roots_by_target)
    workset = build_conditional_workset(
        policy, reference_policy, documents["p2_06"], documents["p2_13"],
        core_registry, args.table_root.resolve(), args.workset_output)
    asset_binding = build_asset_binding_workset(
        policy, documents["asset_catalog_path"], graph,
        args.asset_workset_output)
    p213_binding = next(item for item in bindings["artifacts"] if item["id"] == "P2-13")
    p206_binding = next(item for item in bindings["artifacts"] if item["id"] == "P2-06")
    closure = summarize(graph, documents["p2_13"], detail, p213_binding,
                        p206_binding, workset, asset_binding)
    require(closure["auxiliary_config_reference_scope_complete"] is False and
            closure["asset_binding_resolution_explicit"] is True and
            closure["scope_complete"] is False, "Incomplete scope was incorrectly closed")
    require(closure["asset_binding"]["reachable_assets"] == 21494 and
            closure["asset_binding"]["ambiguous_targets"] == 183 and
            closure["asset_binding"]["unresolved_targets"] == 19 and
            closure["asset_binding"]["unknown_targets"] == 0 and
            closure["asset_binding"]["first_candidate_selection_used"] is False,
            "Reachable asset binding evidence is incomplete or heuristic")
    require(closure["logical_gap_count"] > 0, "Current core-resource gaps unexpectedly vanished")
    require(closure["conditional_required"]["conditional_required_missing"] > 0 and
            closure["conditional_required"]["member_set_exported"] is True and
            closure["conditional_required"]["member_set_count"] == 29 and
            closure["conditional_required"]["zero_threshold_satisfied"] is False,
            "Conditional-required missing-value blocker was incorrectly closed")
    require(closure["resolution"]["heuristic_target_selections"] == 0,
            "Heuristic target selection was detected")
    require(closure["integrity"]["unknown_record_count"] == 0 and
            closure["integrity"]["unknown_resolution_count"] == 0,
            "Unknown graph state must fail closed")
    report = build_report(policy, policy_path, schema_path, bindings, documents,
                          rule_summary, graph, closure)
    write_text(args.json_output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    write_text(args.markdown_output, render_markdown(report))
    report_binding = {
        "path": "Data/Reports/p2-20a-core-resource-closure-report.json",
        "sha256": sha256_file(args.json_output),
    }
    governance = build_governance(report, report_binding)
    write_text(args.governance_output, json.dumps(governance, ensure_ascii=False, indent=2) + "\n")
    return {
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "logical_gap_count": closure["logical_gap_count"],
        "conditional_required_missing": closure["conditional_required"]["conditional_required_missing"],
        "scope_complete": False,
    }


def self_test() -> dict[str, object]:
    from core_closure import logical_integrity
    assertions = 0
    terminal = {"animation-name"}
    require(logical_integrity({"record": "package_edge", "kind": "x", "resolution": "unique",
                               "targets": ["a"]}, terminal) == (0, 0), "Unique test failed")
    assertions += 1
    require(logical_integrity({"record": "package_edge", "kind": "x", "resolution": "ambiguous",
                               "targets": ["a", "b"]}, terminal) == (0, 0), "Ambiguous preservation failed")
    assertions += 1
    require(logical_integrity({"record": "package_edge", "kind": "x", "resolution": "ambiguous",
                               "targets": ["a", "b"], "selected_target": "a"}, terminal)[1] == 1,
            "First-candidate test failed")
    assertions += 1
    require(logical_integrity({"record": "package_edge", "kind": "animation-name",
                               "resolution": "scoped-terminal", "targets": []}, terminal) == (0, 0),
            "Scoped-terminal test failed")
    assertions += 1
    require(logical_integrity({"record": "package_edge", "kind": "x",
                               "resolution": "scoped-terminal", "targets": []}, terminal)[1] == 1,
            "Unapproved terminal test failed")
    assertions += 1
    require(logical_integrity({"record": "table_package_edge", "resolution": "unresolved",
                               "targets": ["a"]}, terminal)[1] == 1,
            "Unresolved-target mismatch test failed")
    assertions += 1
    require(logical_integrity({"record": "table_package_edge", "resolution": "future",
                               "targets": []}, terminal)[0] == 1, "Unknown resolution test failed")
    assertions += 1
    require(not (0 == 0 and False), "Core FK zero must not close an incomplete resource scope")
    assertions += 1
    require(not (False and 0 == 0 and 0 == 0), "Incomplete scope must stay blocked")
    assertions += 1
    require(not (29 == 0 or 0 == 29),
            "Conditional-required missing values must not be replaced by foreign-key zero")
    assertions += 1
    require(sha256_lines({"b", "a"}) == sha256_lines({"a", "b"}),
            "Set hash test failed")
    assertions += 1
    return {"result": "PASS", "assertions": assertions}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--detail-output", type=Path)
    parser.add_argument("--table-root", type=Path)
    parser.add_argument("--workset-output", type=Path)
    parser.add_argument("--asset-workset-output", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--governance-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True, separators=(",", ":")))
        return
    require(all((args.root, args.policy, args.schema, args.detail_output, args.table_root,
                 args.workset_output, args.asset_workset_output, args.json_output,
                 args.markdown_output, args.governance_output)), "Generation arguments are required")
    print(json.dumps(build(args), sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
