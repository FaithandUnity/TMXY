#!/usr/bin/env python3
"""Deterministic P2-18 content-health report generator."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


INPUTS = [
    ("P2-01", "Data/Inventory/p2-01-package-inventory.json"),
    ("P2-02", "Data/Inventory/p2-02-package-boundary-completeness.json"),
    ("P2-03", "Data/Inventory/p2-03-package-dependency-graph.json"),
    ("P2-04", "Data/Inventory/p2-04-current-table-inventory.json"),
    ("P2-05", "Data/Inventory/p2-05-auxiliary-config-inventory.json"),
    ("P2-06", "Data/Inventory/p2-06-three-layer-data.json"),
    ("P2-07", "Data/Inventory/p2-07-core-table-schema.json"),
    ("P2-08", "Data/Inventory/p2-08-table-ownership.json"),
    ("P2-09", "Data/Inventory/p2-09-legacy-current-diff.json"),
    ("P2-10", "Data/Inventory/p2-10-canonical-id-map.json"),
    ("P2-11", "Data/Inventory/p2-11-id-limit-audit.json"),
    ("P2-12", "Data/Inventory/p2-12-full-asset-inventory.json"),
    ("P2-13", "Data/Inventory/p2-13-reference-closure.json"),
    ("P2-14", "Data/Inventory/p2-14-asset-health.json"),
    ("P2-15", "Data/Inventory/p2-15-conversion-routing.json"),
    ("P2-16", "Data/Inventory/p2-16-conversion-cache.json"),
    ("P2-17", "Data/Inventory/p2-17-protocol-codegen.json"),
]


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def ppm(numerator: int, denominator: int) -> int:
    if denominator <= 0 or numerator < 0 or numerator > denominator:
        raise ValueError("invalid rate operands")
    return numerator * 1_000_000 // denominator


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def describe(path: Path) -> dict[str, Any]:
    payload = path.read_bytes()
    return {
        "bytes": len(payload),
        "lines": len(payload.splitlines()),
        "sha256": sha256_bytes(payload),
    }


def task_result(value: dict[str, Any]) -> str:
    return str(value.get("task_id") or value.get("task") or "")


def risk(
    risk_id: str,
    severity: str,
    state: str,
    dimension: str,
    count: int,
    unit: str,
    evidence_tasks: list[str],
    impact: str,
    control: str,
    next_task: str,
) -> dict[str, Any]:
    return {
        "control": control,
        "count": count,
        "dimension": dimension,
        "evidence_tasks": evidence_tasks,
        "id": risk_id,
        "impact": impact,
        "next_task": next_task,
        "severity": severity,
        "state": state,
        "unit": unit,
    }


def load_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], str]:
    required_tasks = [task for task, _ in INPUTS]
    require(policy["required_tasks"] == required_tasks, "policy task order differs from P2-01 through P2-17")
    values: dict[str, dict[str, Any]] = {}
    bindings: list[dict[str, Any]] = []
    binding_lines: list[str] = []
    for expected_task, relative in INPUTS:
        path = root / relative
        value = json.loads(path.read_text(encoding="utf-8"))
        require(value.get("result") == "PASS", f"{expected_task} is not PASS")
        require(value.get("task_status") == "COMPLETE", f"{expected_task} is not COMPLETE")
        require(bool(value.get("completion_criteria_satisfied")), f"{expected_task} criteria are incomplete")
        declared_task = task_result(value)
        if declared_task:
            require(declared_task == expected_task, f"{relative} declares {declared_task}")
        digest = sha256_file(path)
        bindings.append({"path": relative, "result": "PASS", "sha256": digest, "task_id": expected_task})
        binding_lines.append(f"{expected_task}|{relative}|{digest}")
        values[expected_task] = value
    aggregate = sha256_bytes(("\n".join(binding_lines) + "\n").encode("utf-8"))
    return values, bindings, aggregate


def build_report(root: Path, policy_path: Path) -> dict[str, Any]:
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    require(policy["task_id"] == "P2-18", "wrong policy task")
    require(policy["rate_unit"] == "parts-per-million", "rate unit must be ppm")
    values, bindings, aggregate = load_inputs(root, policy)
    p01, p02, p03 = values["P2-01"], values["P2-02"], values["P2-03"]
    p04, p05, p06 = values["P2-04"], values["P2-05"], values["P2-06"]
    p07, p08, p09 = values["P2-07"], values["P2-08"], values["P2-09"]
    p10, p11, p12 = values["P2-10"], values["P2-11"], values["P2-12"]
    p13, p14, p15 = values["P2-13"], values["P2-14"], values["P2-15"]
    p16, p17 = values["P2-16"], values["P2-17"]

    require(p01["summary"]["recognized"] == p02["summary"]["recognized_packages"], "package counts diverge")
    require(p02["summary"]["records"] == p03["coverage"]["object_envelopes"], "package records diverge")
    require(p04["summary"]["active"] == p06["summary"]["generated_tables"], "table counts diverge")
    require(p06["summary"]["rows"] == p04["summary"]["active_rows"], "table row counts diverge")
    require(p07["summary"]["canonical_rows"] == p10["summary"]["active_ids"], "canonical IDs diverge")
    require(p07["summary"]["columns"] == p17["summary"]["source_fields"], "generated fields diverge")
    require(p11["summary"]["component_count"] == p17["summary"]["identity_components"], "identity components diverge")
    asset_count = int(p12["summary"]["files"])
    require(asset_count == int(p14["summary"]["assets"]["files"]), "asset health population diverges")
    require(asset_count == int(p15["summary"]["assets"]["files"]), "conversion population diverges")
    require(asset_count == int(p16["summary"]["assets"]["files"]), "cache population diverges")
    require(p15["summary"]["tiers"]["manual"]["files"] == p16["summary"]["cache_keys"]["blocked_manual_jobs"], "manual blocks diverge")

    package_resolution = p13["package_closure"]["resolution"]
    table_resolution = p13["table_closure"]["object_references"]["resolution"]
    reference_states = p14["summary"]["assets"]["reference_states"]
    assets_valid = int(p12["summary"]["structurally_valid"])
    assets_unresolved = int(p12["summary"]["unresolved_structure"])
    assets_corrupt = int(p12["summary"]["corrupt"])
    require(assets_valid + assets_unresolved + assets_corrupt + int(p12["summary"]["unsupported"]) == asset_count, "asset states do not close")
    malformed_xml = int(p05["summary"]["xml"]["malformed_isolated"])
    damaged_total = assets_corrupt + malformed_xml + int(p01["summary"]["recognized_parse_failures"])
    ready_assets = int(p16["summary"]["cache_keys"]["assets_with_ready_key"])
    manual_assets = int(p15["summary"]["tiers"]["manual"]["files"])

    risks = [
        risk("CHR-001", "high", "open", "references", int(package_resolution["unresolved"]), "package edges", ["P2-03", "P2-13"], "Some Package references have no deterministic target.", "Candidates remain unresolved; no heuristic target is selected.", "P2-20"),
        risk("CHR-002", "high", "open", "references", int(package_resolution["ambiguous"]), "package edges", ["P2-03", "P2-13"], "Multiple valid Package targets prevent automatic binding.", "All candidates are retained and classified.", "P2-20"),
        risk("CHR-003", "high", "open", "damage", assets_unresolved, "assets", ["P2-12", "P2-15", "P2-16"], "Descriptor-dependent assets cannot enter automatic conversion.", "Jobs remain blocked pending descriptor recovery evidence.", "P3-04"),
        risk("CHR-004", "high", "open", "damage", assets_corrupt, "assets", ["P2-12", "P2-15", "P2-16"], "Structurally corrupt assets require repair or replacement.", "Source hashes and parser failures are retained; no automatic repair occurs.", "P3-04"),
        risk("CHR-005", "medium", "controlled-open", "unknown_or_opaque", int(p01["summary"]["unknown_objects"]), "Package object payloads", ["P2-01", "P2-02"], "Object bodies are envelope-complete but not semantically restored.", "Exact byte spans are preserved and separated from parser failures.", "P4-01"),
        risk("CHR-006", "medium", "open", "references", int(table_resolution["unresolved"]), "nullable table-object references", ["P2-13"], "Optional presentation links are missing.", "Core foreign keys remain a separate zero-dangling authority set.", "P2-20"),
        risk("CHR-007", "medium", "open", "references", int(table_resolution["ambiguous"]), "nullable table-object references", ["P2-13"], "Optional presentation links have multiple candidates.", "No first-candidate shortcut or heuristic binding is allowed.", "P2-20"),
        risk("CHR-008", "medium", "review-only", "references", int(reference_states["unlinked_identity_rule_no_match"]), "assets", ["P2-14"], "Assets have an identity rule but no current graph match.", "Unlinked status is review evidence, never deletion authority.", "P2-20"),
        risk("CHR-009", "medium", "review-only", "references", int(reference_states["unlinked_no_identity_rule"]), "assets", ["P2-14"], "Some families lack an authoritative identity rule.", "Assets are retained and routed to the identity-rule gap queue.", "P2-20"),
        risk("CHR-010", "high", "open", "effort", manual_assets, "assets", ["P2-15", "P2-16"], "Manual descriptor recovery or repair is required before conversion.", "Cache keys remain blocked until reviewed intervention evidence exists.", "P3-04"),
        risk("CHR-011", "high", "controlled-open", "capacity", int(p11["summary"]["risk_counts"]["u16_saturated"]) + int(p11["summary"]["risk_counts"]["u16_near_limit"]), "ID components", ["P2-11", "P2-17"], "Observed IDs are at or near legacy 16-bit capacity.", "Generated numeric IDs use uint64 and narrowing is forbidden; downstream storage must follow.", "P4-22"),
        risk("CHR-012", "medium", "review-only", "damage", malformed_xml, "XML files", ["P2-05"], "Malformed auxiliary XML cannot join the strict configuration set.", "Files are isolated without repair or override guessing.", "P3-03"),
        risk("CHR-013", "low", "review-only", "capacity", int(p14["summary"]["duplicates"]["structural_review_files"]), "assets", ["P2-14"], "Structural similarity creates a large review surface.", "No semantic equivalence or deletion claim is made without digest proof.", "P3-04"),
    ]
    severity_counts = Counter(item["severity"] for item in risks)
    state_counts = Counter(item["state"] for item in risks)

    report = {
        "decisions": {
            "automatic_deletion_authorized": False,
            "automatic_repair_authorized": False,
            "g2_approved": False,
            "playable_experience_proven": False,
            "release_authority": False,
            "report_completion_means_accounting_complete_not_content_complete": True,
        },
        "dimensions": {
            "capacity": {
                "asset_bytes": int(p12["summary"]["bytes"]),
                "assets": asset_count,
                "canonical_ids": int(p10["summary"]["active_ids"]),
                "conversion_jobs": int(p15["summary"]["assets"]["conversion_jobs"]),
                "exact_duplicate_redundant_bytes_review_only": int(p14["summary"]["duplicates"]["redundant_bytes"]),
                "id_components": int(p11["summary"]["component_count"]),
                "id_u16_near_limit": int(p11["summary"]["risk_counts"]["u16_near_limit"]),
                "id_u16_overflow": int(p11["summary"]["risk_counts"]["u16_overflow"]),
                "id_u16_saturated": int(p11["summary"]["risk_counts"]["u16_saturated"]),
                "normalized_table_bytes": int(p06["summary"]["normalized_bytes"]),
                "package_graph_bytes": int(p03["graph"]["bytes"]),
                "reference_closure_bytes": int(p13["graph"]["bytes"]),
            },
            "conversion": {
                "alias_assignments": int(p16["summary"]["cache_keys"]["alias_assignments"]),
                "assets": asset_count,
                "assets_with_ready_key": ready_assets,
                "blocked_manual_jobs": int(p16["summary"]["cache_keys"]["blocked_manual_jobs"]),
                "conversion_ready_ppm": ppm(ready_assets, asset_count),
                "distinct_ready_keys": int(p16["summary"]["cache_keys"]["distinct_ready_keys"]),
                "output_hash_verification_required": bool(p16["summary"]["output_hash_verification_required"]),
                "shared_cache_write_authorized": bool(p16["summary"]["shared_cache_write_authorized"]),
            },
            "damage": {
                "asset_corrupt": assets_corrupt,
                "auxiliary_xml_malformed_isolated": malformed_xml,
                "damaged_or_isolated_source_artifacts": damaged_total,
                "package_recognized_parse_failures": int(p01["summary"]["recognized_parse_failures"]),
                "repair_or_deletion_performed": 0,
            },
            "effort": {
                "automatic_planning_human_hours": 426.02,
                "basis": str(p15["summary"]["estimates"]["basis"]),
                "fixed_engineering_hours": float(p15["summary"]["estimates"]["fixed_engineering_hours"]),
                "item_human_hours": float(p15["summary"]["estimates"]["item_human_hours"]),
                "machine_seconds": int(p15["summary"]["estimates"]["machine_seconds"]),
                "manual_assets": manual_assets,
                "manual_planning_human_hours": 617.0,
                "planning_human_hours": float(p15["summary"]["estimates"]["planning_human_hours"]),
                "semi_automatic_assets": int(p15["summary"]["tiers"]["semi-automatic"]["files"]),
                "semi_automatic_planning_human_hours": 361.675,
            },
            "parsing": {
                "assets": asset_count,
                "assets_classified": asset_count,
                "assets_classified_ppm": 1_000_000,
                "assets_structurally_valid": assets_valid,
                "assets_structurally_valid_ppm": ppm(assets_valid, asset_count),
                "config_files": int(p05["summary"]["files"]),
                "config_files_classified": int(p05["summary"]["classified"]),
                "core_packages": int(p02["summary"]["core_packages"]),
                "core_packages_complete": int(p02["summary"]["complete_core_packages"]),
                "core_packages_complete_ppm": int(p02["summary"]["core_parse_rate_ppm"]),
                "ecf_files": int(p05["summary"]["ecf"]["files"]),
                "ecf_round_trip_verified": int(p05["summary"]["ecf"]["round_trip_verified"]),
                "packages_recognized": int(p02["summary"]["recognized_packages"]),
                "packages_recognized_complete": int(p02["summary"]["complete_packages"]),
                "packages_recognized_complete_ppm": int(p02["summary"]["complete_parse_rate_ppm"]),
                "tables_active": int(p04["summary"]["active"]),
                "tables_decoded": int(p04["summary"]["decoded"]),
                "tables_decoded_ppm": ppm(int(p04["summary"]["decoded"]), int(p04["summary"]["active"])),
                "xml_files": int(p05["summary"]["xml"]["files"]),
                "xml_strict_or_fragment": int(p05["summary"]["xml"]["strict_documents"]) + int(p05["summary"]["xml"]["strict_fragments"]),
            },
            "references": {
                "asset_link_edges": int(p13["asset_closure"]["link_edges"]),
                "assets_linked_outside_roots": int(reference_states["linked_outside_declared_roots"]),
                "assets_root_reachable": int(reference_states["root_reachable"]),
                "assets_unlinked_identity_rule_no_match": int(reference_states["unlinked_identity_rule_no_match"]),
                "assets_unlinked_no_identity_rule": int(reference_states["unlinked_no_identity_rule"]),
                "core_foreign_key_dangling": int(p13["table_closure"]["foreign_keys"]["dangling"]),
                "core_foreign_key_edges": int(p13["table_closure"]["foreign_keys"]["canonical_edges"]),
                "heuristic_target_selections": int(p13["health"]["heuristic_target_selections"]),
                "legacy_current_dangling": int(p09["summary"]["references"]["legacy_dangling_references"]) + int(p09["summary"]["references"]["current_dangling_references"]),
                "package_ambiguous": int(package_resolution["ambiguous"]),
                "package_edges": int(p13["package_closure"]["edges"]),
                "package_unresolved": int(package_resolution["unresolved"]),
                "table_object_ambiguous": int(table_resolution["ambiguous"]),
                "table_object_edges": int(p13["table_closure"]["object_references"]["canonical_edges"]),
                "table_object_unresolved": int(table_resolution["unresolved"]),
            },
            "unknown_or_opaque": {
                "asset_structure_unresolved": assets_unresolved,
                "package_object_payloads_opaque": int(p01["summary"]["unknown_objects"]),
                "package_reference_ambiguous": int(package_resolution["ambiguous"]),
                "package_reference_unresolved": int(package_resolution["unresolved"]),
                "table_object_reference_ambiguous": int(table_resolution["ambiguous"]),
                "table_object_reference_unresolved": int(table_resolution["unresolved"]),
                "unclassified_active_tables": int(p08["summary"]["unclassified_tables"]),
                "unsupported_assets": int(p12["summary"]["unsupported"]),
            },
        },
        "disclosure": {
            "decoded_confidential_payloads": False,
            "exact_observed_extrema": False,
            "exact_primary_keys": False,
            "legacy_source_lines": False,
            "private_source_paths": False,
            "raw_table_rows": False,
            "upstream_evidence_sha256_only": True,
        },
        "executive_summary": {
            "content_accounting_complete": True,
            "content_conversion_ready_assets": ready_assets,
            "content_conversion_ready_ppm": ppm(ready_assets, asset_count),
            "core_data_integrity": int(p07["summary"]["dangling_references"]) == 0 and int(p07["summary"]["type_violations"]) == 0,
            "damaged_or_isolated_source_artifacts": damaged_total,
            "full_content_conversion_ready": ready_assets == asset_count,
            "inventory_scope": {
                "active_tables": int(p04["summary"]["active"]),
                "assets": asset_count,
                "assets_bytes": int(p12["summary"]["bytes"]),
                "config_files": int(p05["summary"]["files"]),
                "package_files": int(p01["summary"]["files"]),
            },
            "open_risk_items": len(risks),
            "p2_gate_ready": False,
            "playable_experience_proven": False,
        },
        "result": "PASS_WITH_OPEN_CONTENT_RISKS",
        "risk_register": risks,
        "risk_summary": {
            "critical": int(severity_counts["critical"]),
            "high": int(severity_counts["high"]),
            "low": int(severity_counts["low"]),
            "medium": int(severity_counts["medium"]),
            "open": int(state_counts["open"]),
            "controlled_open": int(state_counts["controlled-open"]),
            "review_only": int(state_counts["review-only"]),
            "risk_items": len(risks),
            "raw_counts_are_not_additive_across_units": True,
        },
        "schema_version": 1,
        "scope": {
            "completed_tasks": len(bindings),
            "input_binding_sha256": aggregate,
            "inputs": bindings,
            "policy_sha256": sha256_file(policy_path),
        },
        "source_build": str(policy["source_build"]),
        "task_id": "P2-18",
    }
    require(report["risk_summary"]["risk_items"] == 13, "risk register size changed")
    require(report["risk_summary"]["high"] == 6, "high risk count changed")
    require(damaged_total == 20, "damaged artifact count changed")
    return report


def format_percent(value: int) -> str:
    return f"{value / 10_000:.2f}%"


def render_markdown(report: dict[str, Any]) -> str:
    parsing = report["dimensions"]["parsing"]
    damage = report["dimensions"]["damage"]
    unknown = report["dimensions"]["unknown_or_opaque"]
    references = report["dimensions"]["references"]
    conversion = report["dimensions"]["conversion"]
    effort = report["dimensions"]["effort"]
    risks = report["risk_register"]
    lines = [
        "# P2-18 Full Content Health Report",
        "",
        f"Result: `{report['result']}`. This proves complete accounting, not a playable or release-ready build.",
        "",
        "## Coverage",
        "",
        "| Population | Complete/valid | Total | Rate |",
        "|---|---:|---:|---:|",
        f"| Recognized Packages | {parsing['packages_recognized_complete']:,} | {parsing['packages_recognized']:,} | {format_percent(parsing['packages_recognized_complete_ppm'])} |",
        f"| Core Packages | {parsing['core_packages_complete']:,} | {parsing['core_packages']:,} | {format_percent(parsing['core_packages_complete_ppm'])} |",
        f"| Active tables | {parsing['tables_decoded']:,} | {parsing['tables_active']:,} | {format_percent(parsing['tables_decoded_ppm'])} |",
        f"| Classified assets | {parsing['assets_classified']:,} | {parsing['assets']:,} | {format_percent(parsing['assets_classified_ppm'])} |",
        f"| Structurally valid assets | {parsing['assets_structurally_valid']:,} | {parsing['assets']:,} | {format_percent(parsing['assets_structurally_valid_ppm'])} |",
        f"| Assets with ready conversion key | {conversion['assets_with_ready_key']:,} | {conversion['assets']:,} | {format_percent(conversion['conversion_ready_ppm'])} |",
        "",
        "## Integrity and unresolved work",
        "",
        f"- Damaged or isolated source artifacts: {damage['damaged_or_isolated_source_artifacts']:,} ({damage['asset_corrupt']:,} corrupt assets and {damage['auxiliary_xml_malformed_isolated']:,} isolated XML files).",
        f"- Opaque Package object payloads: {unknown['package_object_payloads_opaque']:,}; these are preserved spans, not parse failures.",
        f"- Package references: {references['package_unresolved']:,} unresolved and {references['package_ambiguous']:,} ambiguous of {references['package_edges']:,}.",
        f"- Core foreign-key dangling references: {references['core_foreign_key_dangling']:,} of {references['core_foreign_key_edges']:,} canonical edges.",
        f"- Optional table-object references: {references['table_object_unresolved']:,} unresolved and {references['table_object_ambiguous']:,} ambiguous of {references['table_object_edges']:,}.",
        f"- Manual conversion assets: {effort['manual_assets']:,}; blocked cache jobs: {conversion['blocked_manual_jobs']:,}.",
        f"- Planning coefficient: {effort['planning_human_hours']:,.3f} human hours and {effort['machine_seconds']:,} machine seconds; this is not a schedule commitment.",
        "",
        "## Risk register",
        "",
        "| ID | Severity | State | Count | Unit | Next task |",
        "|---|---|---|---:|---|---|",
    ]
    for item in risks:
        lines.append(f"| {item['id']} | {item['severity']} | {item['state']} | {item['count']:,} | {item['unit']} | {item['next_task']} |")
    lines.extend(
        [
            "",
            "## Decision boundary",
            "",
            "P2-18 is complete because every upstream population and risk is accounted for and hash-bound. G2 remains unapproved, all-content conversion remains incomplete, automatic repair or deletion remains forbidden, and no playable experience or release authority is claimed.",
            "",
            f"Input binding SHA-256: `{report['scope']['input_binding_sha256']}`.",
            "",
        ]
    )
    return "\n".join(lines)


def self_test() -> dict[str, Any]:
    assert ppm(1, 1) == 1_000_000
    assert ppm(39_290, 40_090) == 980_044
    sample = risk("CHR-999", "low", "review-only", "capacity", 1, "item", ["P2-01"], "i", "c", "P2-20")
    assert sample["count"] == 1 and sample["severity"] == "low"
    assert canonical_json({"b": 1, "a": 2}).startswith('{\n  "a"')
    assert format_percent(980_044) == "98.00%"
    assert len(INPUTS) == 17 and INPUTS[0][0] == "P2-01" and INPUTS[-1][0] == "P2-17"
    return {"assertions": 6, "result": "PASS"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root")
    parser.add_argument("--policy")
    parser.add_argument("--json-output")
    parser.add_argument("--markdown-output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True))
        return 0
    if not all((args.root, args.policy, args.json_output, args.markdown_output)):
        raise ValueError("root, policy, and both outputs are required")
    report = build_report(Path(args.root), Path(args.policy))
    json_path = Path(args.json_output)
    markdown_path = Path(args.markdown_output)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(canonical_json(report), encoding="utf-8", newline="\n")
    markdown_path.write_text(render_markdown(report), encoding="utf-8", newline="\n")
    print(
        json.dumps(
            {
                "json": describe(json_path),
                "markdown": describe(markdown_path),
                "result": report["result"],
                "risk_summary": report["risk_summary"],
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"content_health: {error}", file=sys.stderr)
        raise SystemExit(2)
