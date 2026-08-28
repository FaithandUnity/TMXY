"""Report assembly and rendering for P2-20A."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from core_common import sha256_file, sha256_lines


def build_report(policy: dict[str, Any], policy_path: Path, schema_path: Path,
                 bindings: dict[str, Any], documents: dict[str, Any],
                 rule_summary: dict[str, Any], graph: dict[str, Any],
                 closure: dict[str, Any]) -> dict[str, Any]:
    p205 = documents["p2_05"]
    roots = {
        "selection": "all-declared-roots",
        "root_kinds": sorted(graph["root_counts"]),
        "count": len(graph["roots"]),
        "by_kind": graph["root_counts"],
        "set_sha256": sha256_lines(graph["roots"]),
    }
    rule_summary = dict(rule_summary)
    # A zero-edge declared rule remains selected; emitted coverage is reported separately.
    rule_summary["rules_with_edges"] = len(graph["rules_with_edges"])
    rule_summary["source_rows"] = len(graph["field_sources"])
    auxiliary = {
        "inventory_files": p205["summary"]["files"],
        "malformed_isolated": p205["summary"]["xml"]["malformed_isolated"],
        "reference_adapters": len(policy["auxiliary_config_scope"]["reference_adapters"]),
        "reference_adapter_coverage": policy["auxiliary_config_scope"]["current_coverage"],
        "new_roots_are_union_only": True,
        "scope_complete": False,
    }
    return {
        "schema_version": 1,
        "evidence_revision": "P2-20A.2",
        "captured_utc": documents["p2_18"]["captured_utc"],
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "source_build": policy["source_build"],
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "input_bindings": bindings,
        "scope_definition": {
            "mode": "monotonic-union",
            "outcome_based_exclusion": False,
            "declared_roots": roots,
            "core_table_resource_rules": rule_summary,
            "auxiliary_config": auxiliary,
        },
        "closure": closure,
        "decision": {
            "required_status": "SATISFIED",
            "observed_status": "BLOCKED",
            "satisfied": False,
            "thresholds": {
                "scope_complete": True,
                "unresolved": 0,
                "ambiguous": 0,
                "conditional_required_missing": 0,
                "asset_binding_ambiguous": 0,
                "asset_binding_unresolved": 0,
                "asset_binding_unknown": 0,
                "heuristic": 0,
                "asset_structure_gaps": 0,
                "unknown": 0,
            },
            "g2_approved": False,
            "p3_authorized": False,
        },
        "blockers": [
            {
                "id": "G2-06-CONFIG-SCOPE",
                "reason": "Auxiliary configuration reference adapters are absent, so configuration-derived roots are not proven complete.",
                "required_action": "Define reviewed semantic adapters, including tolerant-parser coverage for isolated malformed XML, and add discovered roots by union.",
            },
            {
                "id": "G2-06-ASSET-BINDING",
                "reason": "All reachable Package-to-asset bindings now have explicit evidence states, but divergent or invalid descriptor sets remain ambiguous or unresolved.",
                "required_action": "Resolve every divergent descriptor set and failed descriptor validation through qualified evidence while preserving all candidates and without first-candidate selection.",
            },
            {
                "id": "G2-06-CONDITIONAL-REQUIRED",
                "reason": "P2-13 reports conditionally required resource fields with missing values; such rows may emit no table-to-Package edge and cannot disappear from review.",
                "required_action": "Use the complete hashed member workset for authorized remediation, resolve every missing required value, retain the P2-06 and P2-13 source bindings, and reach the independent zero threshold.",
            },
            {
                "id": "G2-06-LOGICAL-GAPS",
                "reason": "The monotonic core closure contains unresolved and ambiguous table or Package references.",
                "required_action": "Resolve each hashed work item through reviewed aliases, equivalent-candidate proof, source recovery, or an explicit versioned scope decision.",
            },
            {
                "id": "G2-06-ASSET-STRUCTURE",
                "reason": "Some reachable assets remain structurally unresolved.",
                "required_action": "Recover qualified descriptors or provide reviewed replacements while retaining source hashes and audit history.",
            },
        ],
        "authority_boundaries": {
            "g2_approved": False,
            "p3_authorized": False,
            "playable_experience_proven": False,
            "release_authority": False,
            "automatic_repair_or_delete_authority": False,
        },
        "contracts": {
            "policy": "Contracts/data-schema/g2-core-resource-closure-policy-v1.json",
            "policy_sha256": sha256_file(policy_path),
            "schema": "Contracts/data-schema/g2-core-resource-closure-v1.schema.json",
            "schema_sha256": sha256_file(schema_path),
        },
        "disclosure": policy["disclosure"],
    }


def render_markdown(report: dict[str, Any]) -> str:
    closure = report["closure"]
    resolution = closure["resolution"]
    structure = closure["asset_structure"]
    conditional = closure["conditional_required"]
    binding = closure["asset_binding"]
    roots = report["scope_definition"]["declared_roots"]
    rules = report["scope_definition"]["core_table_resource_rules"]
    lines = [
        "# P2-20A G2-06 Core Resource Closure",
        "",
        "- Review execution: `PASS`",
        "- Criterion decision: `BLOCKED`",
        "- Completion criteria satisfied: `false`",
        "- G2 approved: `false`",
        "- P3 authorized: `false`",
        "",
        "The review computes a monotonic union fixed before observing the result. It does not select a favorable playable sample or filter by client/server ownership.",
        "",
        "## Scope",
        "",
        f"All {roots['count']} declared character, scene, and skill roots are included. All {rules['selected_rules']} resource-bearing core-table rules are included for every emitted non-sentinel canonical-row reference.",
        "",
        "Auxiliary configuration reference adapters are absent, so later configuration roots may only enlarge the union. Package-to-asset bindings are explicitly classified, but ambiguous and unresolved states remain blocking.",
        "",
        "## Measured closure",
        "",
        "| Metric | Value |",
        "| --- | ---: |",
        f"| Start nodes | {closure['start_nodes']} |",
        f"| Reachable nodes | {closure['reachable_nodes']} |",
        f"| Table unresolved | {resolution['table_unresolved']} |",
        f"| Table ambiguous | {resolution['table_ambiguous']} |",
        f"| Package unresolved | {resolution['package_unresolved']} |",
        f"| Package ambiguous | {resolution['package_ambiguous']} |",
        f"| Scoped terminals (not gaps) | {resolution['package_scoped_terminal']} |",
        f"| Heuristic selections | {resolution['heuristic_target_selections']} |",
        f"| Conditional-required rows | {conditional['runtime_assert_rows']} |",
        f"| Conditional-required missing | {conditional['conditional_required_missing']} |",
        f"| Conditional-required unresolved | {conditional['conditional_required_unresolved']} |",
        f"| Asset binding targets resolved | {binding['resolved_targets']} |",
        f"| Asset binding targets ambiguous | {binding['ambiguous_targets']} |",
        f"| Asset binding targets unresolved | {binding['unresolved_targets']} |",
        f"| Asset binding targets unknown | {binding['unknown_targets']} |",
        f"| Reachable asset structure unresolved | {structure['unresolved']} |",
        f"| Reachable asset structure fail | {structure['fail']} |",
        "",
        "Core foreign-key dangling zero remains a distinct table-integrity fact and is not substituted for these resource-reference metrics. The conditional-required missing count is retained even though missing values produce no table-to-Package edge. Ambiguous edges retain every candidate; no first candidate is selected.",
        "",
        f"The {conditional['member_set_count']}-member conditional-required workset is exported only in the ignored evidence area and bound by SHA-256 `{conditional['member_set_sha256']}`. Each record contains only an anonymous member hash, a frozen rule ID, and a closed reason. No value, primary key, source row, or source path is disclosed.",
        "",
        f"The {binding['workset_count']}-member asset binding workset is also ignored and SHA-256 bound as `{binding['workset_sha256']}`. Explicit status does not mean resolved: every ambiguous or unresolved target remains a zero-threshold blocker, and no candidate is selected.",
        "",
        "## Blocking work",
        "",
    ]
    for blocker in report["blockers"]:
        lines.extend([
            f"- `{blocker['id']}`: {blocker['reason']} {blocker['required_action']}",
        ])
    lines.extend([
        "",
        "## Reproduction",
        "",
        "Run `pwsh -NoProfile -File Tools/TMXY.G2CoreClosure/New-G2CoreResourceClosure.ps1`, then rerun with `-Check`. The generator runs as the locked non-root builder with a read-only repository mount, no network, no Linux capabilities, and no-new-privileges.",
        "",
        "The detailed hashed start, reachable, logical-gap, and asset-structure sets remain in the ignored `Data/Exports/P2-20` directory. Tracked evidence contains only aggregate counts and SHA-256 bindings.",
        "",
    ])
    return "\n".join(lines)


def build_governance(report: dict[str, Any], report_binding: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "evidence_revision": "P2-20A.2",
        "task_id": "P2-20A",
        "criterion_id": "G2-06",
        "status": "BLOCKED",
        "scope_definition": "monotonic-union-all-declared-roots-plus-all-core-resource-fields",
        "scope_complete": False,
        "auxiliary_config_reference_scope_complete": False,
        "asset_binding_resolution_explicit": True,
        "asset_binding_resolved_targets": report["closure"]["asset_binding"]["resolved_targets"],
        "asset_binding_ambiguous_targets": report["closure"]["asset_binding"]["ambiguous_targets"],
        "asset_binding_unresolved_targets": report["closure"]["asset_binding"]["unresolved_targets"],
        "asset_binding_unknown_targets": report["closure"]["asset_binding"]["unknown_targets"],
        "asset_binding_workset_sha256": report["closure"]["asset_binding"]["workset_sha256"],
        "conditional_required_missing": report["closure"]["conditional_required"]["conditional_required_missing"],
        "conditional_required_member_set_exported": True,
        "conditional_required_member_set_count": report["closure"]["conditional_required"]["member_set_count"],
        "conditional_required_member_set_sha256": report["closure"]["conditional_required"]["member_set_sha256"],
        "logical_gap_count": report["closure"]["logical_gap_count"],
        "report": report_binding,
        "decisions": {
            "first_candidate_selection_authorized": False,
            "core_foreign_key_zero_substitution_authorized": False,
            "conditional_required_edge_absence_substitution_authorized": False,
            "outcome_based_scope_narrowing_authorized": False,
            "automatic_repair_or_delete_authorized": False,
            "g2_approved": False,
            "p3_authorized": False,
        },
    }
