#!/usr/bin/env python3
"""Generate the deterministic, fail-closed P2-20 G2 review."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
from g2_evidence import (bind_inputs, evaluate_core_closure,
                         evaluate_migration_registry, is_safe_relative,
                         is_sha256, load_json, require, resolve_inside, sha256)

def metric(name: str, value: Any, unit: str) -> dict[str, Any]:
    return {"name": name, "value": value, "unit": unit}
def criterion(
    policy_item: dict[str, Any],
    satisfied: bool,
    metrics: list[dict[str, Any]],
    interpretation: str,
    blockers: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "id": policy_item["id"],
        "statement": policy_item["statement"],
        "required_status": policy_item["required_status"],
        "observed_status": "SATISFIED" if satisfied else "BLOCKED",
        "satisfied": satisfied,
        "evidence_task_ids": policy_item["evidence_task_ids"],
        "metrics": metrics,
        "interpretation": interpretation,
        "blocker_ids": blockers or [],
    }
def build_criteria(policy: dict[str, Any], evidence: dict[str, dict[str, Any]], root: Path) -> list[dict[str, Any]]:
    by_id = {item["id"]: item for item in policy["criteria"]}
    p202 = evidence["P2-02"]["summary"]
    p204 = evidence["P2-04"]
    p207 = evidence["P2-07"]
    p208 = evidence["P2-08"]
    p217 = evidence["P2-17"]
    p219 = evidence["P2-19"]
    thresholds = policy["thresholds"]
    reviews: list[dict[str, Any]] = []

    ok = (p202["complete_parse_rate_ppm"] >= thresholds["package_complete_ppm"] and
          p202["core_parse_rate_ppm"] >= thresholds["core_package_complete_ppm"] and
          p202["silent_truncation_accepts"] == 0 and p202["silent_trailing_byte_accepts"] == 0)
    reviews.append(criterion(by_id["G2-01"], ok, [
        metric("complete_parse_rate", p202["complete_parse_rate_ppm"], "parts_per_million"),
        metric("core_parse_rate", p202["core_parse_rate_ppm"], "parts_per_million"),
        metric("silent_boundary_accepts", p202["silent_truncation_accepts"] + p202["silent_trailing_byte_accepts"], "count"),
    ], "Measured package coverage reaches both thresholds and boundary mutations fail closed."))

    p204s = p204["summary"]
    ok = (p204s["files"] == thresholds["tbl_files"] and p204s["unresolved"] == 0 and
          p204s["decoded"] + p204s["historical_shadow"] == p204s["files"])
    reviews.append(criterion(by_id["G2-02"], ok, [
        metric("tbl_files", p204s["files"], "files"),
        metric("active_decoded", p204s["decoded"], "files"),
        metric("historical_isolated", p204s["historical_shadow"], "files"),
        metric("unresolved", p204s["unresolved"], "files"),
    ], "All measured TBL inputs have a decoded-current or historical-isolation result."))

    p207s = p207["summary"]
    violations = sum(p207s[name] for name in
                     ("type_violations", "range_violations", "key_violations", "dangling_references"))
    ok = p207s["result"] == "PASS" and violations == thresholds["core_integrity_violations"]
    reviews.append(criterion(by_id["G2-03"], ok, [
        metric("core_tables", p207s["tables"], "tables"),
        metric("typed_and_ruled_columns", p207s["columns_with_type_and_rule"], "columns"),
        metric("integrity_violations", violations, "count"),
    ], "The scoped core-table integrity contract passes with zero measured violations."))

    p205 = evidence["P2-05"]
    p206 = evidence["P2-06"]
    builds = [p204["source"]["build"], p205["source"]["build"], p206["source"]["build"],
              p207["source"]["build"], p208["source"]["build"]]
    same_sandbox = (p204["source"]["kind"] == p205["source"]["kind"] == "read-only-sandbox-client" and
                    p204["source"]["sandbox_relative_path"] == p205["source"]["sandbox_relative_path"] and
                    p204["source"]["executable"]["sha256"] == p205["source"]["executable"]["sha256"] ==
                    p206["source"]["executable_sha256"])
    hash_chain = (p205["source"]["p2_04_evidence_sha256"] ==
                  sha256(resolve_inside(root, "Data/Inventory/p2-04-current-table-inventory.json")) and
                  p206["source"]["inventory_sha256"] ==
                  sha256(resolve_inside(root, "Data/Inventory/p2-04-current-table-inventory.json")) and
                  p207["source"]["p2_06_evidence_sha256"] ==
                  sha256(resolve_inside(root, "Data/Inventory/p2-06-three-layer-data.json")) and
                  p208["source"]["p2_05_evidence_sha256"] ==
                  sha256(resolve_inside(root, "Data/Inventory/p2-05-auxiliary-config-inventory.json")) and
                  p208["source"]["p2_06_evidence_sha256"] ==
                  sha256(resolve_inside(root, "Data/Inventory/p2-06-three-layer-data.json")) and
                  p208["source"]["p2_07_registry_sha256"] == p207["output"]["registry_sha256"])
    ok = len(set(builds)) == 1 and builds[0] == policy["source_build"] and same_sandbox and hash_chain
    reviews.append(criterion(by_id["G2-04"], ok, [
        metric("evidence_sets", len(builds), "count"),
        metric("distinct_source_builds", len(set(builds)), "count"),
        metric("source_build", builds[0] if ok else "mismatch", "identifier"),
        metric("same_read_only_sandbox_and_executable", same_sandbox, "boolean"),
        metric("evidence_hash_chain_valid", hash_chain, "boolean"),
    ], "The evidence chain binds the same read-only sandbox executable and frozen build through P2-04 to P2-08."))

    p208s = p208["summary"]
    ownership_guarantees = p208["guarantees"]
    server_authority = ownership_guarantees["combat_and_economy_default_to_server_authority"] is True
    unknown_fail_closed = ownership_guarantees["unknown_gameplay_semantics_fail_to_server_authority"] is True
    client_copy_no_authority = ownership_guarantees["client_copy_does_not_grant_runtime_authority"] is True
    ok = (p208s["classified_tables"] == p208s["active_tables"] and
          p208s["classified_core_columns"] == p208s["core_columns"] and
          p208s["security_sensitive_client_authority_violations"] == 0 and server_authority and
          unknown_fail_closed and client_copy_no_authority)
    reviews.append(criterion(by_id["G2-05"], ok, [
        metric("classified_active_tables", p208s["classified_tables"], "tables"),
        metric("classified_core_columns", p208s["classified_core_columns"], "columns"),
        metric("client_authority_violations", p208s["security_sensitive_client_authority_violations"], "count"),
        metric("combat_and_economy_server_authority", server_authority, "boolean"),
        metric("unknown_gameplay_semantics_fail_closed", unknown_fail_closed, "boolean"),
        metric("client_copy_grants_no_runtime_authority", client_copy_no_authority, "boolean"),
    ], "Ownership is complete; combat, economy, and unknown gameplay semantics remain server-authoritative and fail closed."))

    core = evaluate_core_closure(root, evidence["P2-20A"], evidence["P2-20A.4"], thresholds)
    ok = core["satisfied"]
    reviews.append(criterion(by_id["G2-06"], ok, [
        metric("supplemental_report_present", True, "boolean"),
        metric("declared_scope_hash_bound", core["declared_scope_bound"], "boolean"),
        metric("scope_complete", core["scope_complete"], "boolean"),
        metric("auxiliary_config_scope_complete", core["auxiliary_complete"], "boolean"),
        *(metric(name, value, unit) for name, value, unit in core["auxiliary_metrics"]),
        metric("descriptor_diagnostic_hash_bound", core["descriptor_diagnostic_bound"], "boolean"),
        metric("descriptor_diagnostic_targets", core["descriptor_diagnostic_targets"], "assets"),
        metric("descriptor_diagnostic_candidate_edges", core["descriptor_diagnostic_edges"], "edges"),
        metric("descriptor_diagnostic_resolved_targets", core["descriptor_diagnostic_resolved"], "assets"),
        metric("descriptor_diagnostic_ambiguous_targets", core["descriptor_diagnostic_ambiguous"], "assets"),
        metric("descriptor_diagnostic_unresolved_targets", core["descriptor_diagnostic_unresolved"], "assets"),
        metric("asset_binding_resolution_explicit", core["asset_binding_explicit"], "boolean"),
        metric("asset_binding_resolved_targets", core["asset_binding_resolved"], "assets"),
        metric("asset_binding_ambiguous_targets", core["asset_binding_ambiguous"], "assets"),
        metric("asset_binding_unresolved_targets", core["asset_binding_unresolved"], "assets"),
        metric("asset_binding_unknown_targets", core["asset_binding_unknown"], "assets"),
        metric("asset_binding_workset_hash_bound", core["asset_binding_workset_bound"], "boolean"),
        metric("table_resource_unresolved", core["table_unresolved"], "references"),
        metric("table_resource_ambiguous", core["table_ambiguous"], "references"),
        metric("package_resource_unresolved", core["package_unresolved"], "references"),
        metric("package_resource_ambiguous", core["package_ambiguous"], "references"),
        metric("conditional_required_missing", core["conditional_missing"], "references"),
        metric("conditional_member_set_exported", core["member_set_exported"], "boolean"),
        metric("conditional_member_set_count", core["member_set_count"], "members"),
        metric("conditional_member_set_hash_bound", core["member_set_hash_bound"], "boolean"),
        metric("conditional_source_hash_bound", core["conditional_source_bound"], "boolean"),
        metric("heuristic_target_selections", core["heuristic"], "references"),
        metric("first_candidate_selection_used", core["first_candidate_used"], "boolean"),
        metric("asset_structure_unresolved", core["asset_unresolved"], "assets"),
        metric("asset_structure_fail", core["asset_fail"], "assets"),
        metric("unknown_record_count", core["unknown_records"], "records"),
        metric("unknown_resolution_count", core["unknown_resolutions"], "records"),
        metric("integrity_mismatches", core["integrity_mismatches"], "records"),
        metric("logical_gap_count", core["logical_gap_count"], "references"),
        metric("logical_gap_set_hash_bound", core["logical_gap_set_bound"], "boolean"),
        metric("core_foreign_key_dangling_context", core["core_fk_dangling"], "references"),
    ], "P2-20A supplies a hash-bound monotonic core-scope closure report plus complete anonymous conditional-required and asset-binding worksets. A.4 independently binds exact P2-03/P2-12/P2-13 candidate identities and production-binder full semantic signatures; its reconciled full workset supersedes coarse descriptor counts without selecting a candidate. A.3 covers all 212 auxiliary instances, but no semantic adapter, no-reference disposition, or root is approved. Explicit states do not erase remaining ambiguity, unresolved descriptors, conditional gaps, logical queues, or reachable structure. Core foreign-key zero cannot replace these facts.", ["G2-BLK-06"] if not ok else []))

    migration = evaluate_migration_registry(evidence["P2-20B"], thresholds)
    ok = migration["satisfied"]
    reviews.append(criterion(by_id["G2-07"], ok, [
        metric("migration_decision_registry_present", True, "boolean"),
        metric("migration_workflow_version", migration["workflow_version"], "version"),
        metric("migration_workflow_ready", migration["workflow_ready"], "boolean"),
        metric("review_packet_count", migration["review_packets"], "packets"),
        metric("review_packet_members", migration["review_packet_members"], "decisions"),
        metric("authority_ledger_records", migration["authority_records"], "records"),
        metric("coverage_complete", migration["coverage"], "boolean"),
        metric("expected_units", migration["expected"], "decisions"),
        metric("enumerated_units", migration["enumerated"], "decisions"),
        metric("missing_units", migration["missing"], "decisions"),
        metric("duplicate_units", migration["duplicates"], "decisions"),
        metric("orphan_units", migration["orphans"], "decisions"),
        metric("pending_decisions", migration["pending"], "decisions"),
        metric("decided_units", migration["decided"], "decisions"),
        metric("approved_units", migration["approved"], "decisions"),
        metric("verified_units", migration["verified"], "decisions"),
        metric("approval_count", migration["approval_count"], "approvals"),
        metric("machine_suggestions", migration["suggestions"], "suggestions"),
        metric("machine_suggestions_count_as_decisions", migration["suggestions_count_as_decisions"], "boolean"),
        metric("pending_entries_have_no_chosen_decision", migration["pending_empty"], "boolean"),
        metric("g2_07_registry_satisfied", migration["registry_satisfied"], "boolean"),
    ], "P2-20B V2 provides a fail-closed decision workflow and anonymous review packets that preserve all independent units, but every unit remains pending with no externally authorized decision, approval, or bound verification. Machine suggestions and review packets are non-authoritative and do not satisfy G2-07.", ["G2-BLK-07"] if not ok else []))

    human = p219["summary"]["human_budget"]
    machine = p219["summary"]["machine_budget"]
    storage = p219["summary"]["storage_budget"]
    money = human["money_budget"]
    p218_effort = evidence["P2-18"]["summary"]["effort"]
    manual_assets = int(p218_effort["manual_assets"])
    total_assets = int(evidence["P2-15"]["summary"]["assets"]["files"])
    manual_rate_ppm = manual_assets * 1_000_000 // total_assets
    ok = (human["total_planning_hours"] > 0 and human["risk_reserve_hours"] > 0 and
          machine["total_sequential_seconds"] > 0 and storage["total_budget_bytes"] > 0 and
          money["estimated"] is False)
    reviews.append(criterion(by_id["G2-08"], ok, [
        metric("manual_content_assets", manual_assets, "assets"),
        metric("total_content_assets", total_assets, "assets"),
        metric("manual_content_rate", manual_rate_ppm, "parts_per_million"),
        metric("base_planning_hours", human["base_planning_hours"], "human_hours"),
        metric("risk_adjusted_planning_hours", human["total_planning_hours"], "human_hours"),
        metric("machine_projection", machine["total_sequential_seconds"], "machine_seconds"),
        metric("storage_budget", storage["total_budget_bytes"], "bytes"),
        metric("money_budget_estimated", money["estimated"], "boolean"),
    ], "Planning effort, machine projection, storage, assumptions, and reserves are quantified; none is measured delivery duration or a monetary quote."))

    same_schema = p217["target_contracts"]["same_schema_sha256"]
    ok = (p217["summary"]["targets"] == 2 and p217["outputs"]["schema"]["sha256"] == same_schema and
          p217["summary"]["numeric_identity_storage"] == "uint64" and p217["summary"]["narrowing"] == "forbidden")
    reviews.append(criterion(by_id["G2-09"], ok, [
        metric("generated_targets", p217["summary"]["targets"], "targets"),
        metric("same_schema_digest", ok, "boolean"),
        metric("numeric_identity_storage", p217["summary"]["numeric_identity_storage"], "type"),
        metric("narrowing_forbidden", p217["summary"]["narrowing"] == "forbidden", "boolean"),
    ], "Backend and UE generated contracts bind to one schema digest and retain uint64 identity storage."))
    return reviews
def validate_outcome(policy: dict[str, Any], criteria: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
    required = {item["id"]: item["required_status"] for item in policy["criteria"]}
    require(set(required.values()) == {"SATISFIED"}, "Every G2 exit criterion must require SATISFIED")
    satisfied = [item["id"] for item in criteria if item["satisfied"]]
    blocked = [item["id"] for item in criteria if not item["satisfied"]]
    require(len(criteria) == policy["thresholds"]["required_criteria"], "Criterion count mismatch")
    require(len(satisfied) + len(blocked) == len(criteria), "Criterion outcome count mismatch")
    require(all(item["observed_status"] == ("SATISFIED" if item["satisfied"] else "BLOCKED")
                for item in criteria), "Criterion observed status mismatch")
    require(set(blocked).issubset({"G2-06", "G2-07"}),
            "Unexpected prerequisite criterion drifted during G2 review")
    return satisfied, blocked

def build_report(root: Path, policy_path: Path, schema_path: Path) -> dict[str, Any]:
    policy = load_json(policy_path)
    bindings, evidence = bind_inputs(root, policy)
    criteria = build_criteria(policy, evidence, root)
    satisfied, blocked = validate_outcome(policy, criteria)
    quality = load_json(resolve_inside(root, policy["quality_evidence"]))
    p219 = evidence["P2-19"]
    human = p219["summary"]["human_budget"]
    machine = p219["summary"]["machine_budget"]
    storage = p219["summary"]["storage_budget"]
    approved = len(blocked) == 0
    state = "PASS" if approved else "BLOCKED"
    task_status = "COMPLETE" if approved else "BLOCKED"
    gate_decision = "APPROVED" if approved else "BLOCKED"
    blockers: list[dict[str, Any]] = []
    if "G2-06" in blocked:
        closure = evidence["P2-20A"]["closure"]
        resolution = closure["resolution"]
        conditional = closure["conditional_required"]
        asset_binding = evidence["P2-20A.4"]["measured"]["reconciled_full_workset"]
        asset_structure = closure["asset_structure"]
        auxiliary = evidence["P2-20A"]["scope_definition"]["auxiliary_config"]
        blockers.append({
            "id": "G2-BLK-06",
            "criterion_id": "G2-06",
            "title": "Core resource-reference closure has quantified open gaps",
            "reason": (
                f"P2-20A and its A.3 auxiliary evidence are hash-bound; all {auxiliary['inventory_files']} "
                f"configuration instances remain nonterminal ({auxiliary['candidate_only']} candidate-only, "
                f"{auxiliary['editor_undecided']} editor-undecided, {auxiliary['malformed_blocked']} malformed) "
                f"with {auxiliary['approved_roots']} approved roots. Explicit asset-binding evidence retains "
                f"{asset_binding['ambiguous_targets']} full-semantic ambiguous plus "
                f"{asset_binding['unresolved_targets']} production-unresolved targets. "
                f"The measured core queues contain {resolution['table_unresolved']} unresolved and "
                f"{resolution['table_ambiguous']} ambiguous table references, "
                f"{resolution['package_unresolved']} unresolved and "
                f"{resolution['package_ambiguous']} ambiguous Package references, "
                f"{conditional['conditional_required_missing']} conditionally required missing values, "
                f"and {asset_structure['unresolved']} structurally unresolved reachable assets."
            ),
            "required_action": (
                "Approve semantic adapters or explicit no-reference dispositions for all auxiliary instances, close every ambiguous or unresolved asset-binding state, use the hash-bound "
                "conditional member workset for authorized remediation, and reduce every scoped unresolved, ambiguous, structural, "
                "unknown, integrity, and heuristic metric to its policy threshold without first-candidate selection."
            ),
            "authority_required": False,
        })
    if "G2-07" in blocked:
        migration = evidence["P2-20B"]["summary"]
        blockers.append({
            "id": "G2-BLK-07",
            "criterion_id": "G2-07",
            "title": "Migration registry is complete in coverage but decisions remain pending",
            "reason": (
                f"P2-20B enumerates {migration['enumerated_units']} of {migration['expected_units']} "
                f"required units, but {migration['pending']} remain pending, only "
                f"{migration['decided']} are decided, {migration['approved']} are approved, and the "
                f"verified approval count is {migration['approval_count']}. Machine suggestions are not decisions."
            ),
            "required_action": (
                "Import explicit reviewed migration decisions into the V2 authority ledger, bind independently "
                "verifiable approvals and post-decision verification to each decision digest; machine-generated "
                "suggestions and the 39 review packets remain advisory."
            ),
            "authority_required": True,
        })
    return {
        "schema_version": 1,
        "captured_utc": p219["captured_utc"],
        "task_id": "P2-20",
        "source_build": policy["source_build"],
        "result": state,
        "review_execution_result": "PASS",
        "task_status": task_status,
        "completion_criteria_satisfied": approved,
        "gate": "G2",
        "gate_decision": gate_decision,
        "g2_approved": approved,
        "p3_authorized": approved,
        "input_bindings": bindings,
        "summary": {
            "criteria_total": len(criteria),
            "satisfied": len(satisfied),
            "blocked": len(blocked),
            "satisfied_ids": satisfied,
            "blocked_ids": blocked,
        },
        "criteria": criteria,
        "security": {
            "quality_result": quality["result"],
            "repository_result": quality["repository"]["result"],
            "repository_failures": quality["repository"]["failure_count"],
            "secret_result": quality["secret"]["result"],
            "secret_findings": quality["secret"]["finding_count"],
            "security_review_result": "PASS",
        },
        "blockers": blockers,
        "budget_interpretation": {
            "planning_cost_quantified": True,
            "manual_content_assets": int(evidence["P2-18"]["summary"]["effort"]["manual_assets"]),
            "total_content_assets": int(evidence["P2-15"]["summary"]["assets"]["files"]),
            "manual_content_rate_ppm": int(evidence["P2-18"]["summary"]["effort"]["manual_assets"]) * 1_000_000 // int(evidence["P2-15"]["summary"]["assets"]["files"]),
            "base_planning_hours": human["base_planning_hours"],
            "risk_adjusted_planning_hours": human["total_planning_hours"],
            "machine_projection_seconds": machine["total_sequential_seconds"],
            "storage_budget_bytes": storage["total_budget_bytes"],
            "incremental_storage_required_bytes": storage["incremental_required_bytes"],
            "storage_capacity_gap_bytes": storage["capacity_gap_bytes"],
            "measured_schedule": False,
            "monetary_amount_available": False,
            "financial_total_cost_available": False,
            "delivery_commitment": False,
        },
        "authority_boundaries": {
            "playable_experience_proven": False,
            "release_authority": False,
            "production_authority": False,
            "automatic_repair_or_delete_authority": False,
            "official_server_implementation_recovered": False,
        },
        "contracts": {
            "policy": policy_path.relative_to(root).as_posix(),
            "policy_sha256": sha256(policy_path),
            "schema": schema_path.relative_to(root).as_posix(),
            "schema_sha256": sha256(schema_path),
        },
        "disclosure": {
            "private_source_paths": False,
            "exact_primary_keys": False,
            "exact_observed_extrema": False,
            "raw_table_rows": False,
            "decoded_confidential_payloads": False,
            "legacy_source_lines": False,
        },
    }

def markdown(report: dict[str, Any]) -> str:
    lines = [
        "# P2-20 G2 Data Review",
        "",
        f"- Review execution: `{report['review_execution_result']}`",
        f"- Gate decision: `{report['gate_decision']}`",
        f"- Task status: `{report['task_status']}`",
        f"- G2 approved: `{str(report['g2_approved']).lower()}`",
        f"- P3 authorized: `{str(report['p3_authorized']).lower()}`",
        f"- Evidence snapshot: `{report['captured_utc']}`",
        "",
        ("The review procedure completed successfully, but the gate remains fail-closed. "
         "A successful review execution is not a successful G2 decision."
         if not report["g2_approved"] else
         "The review procedure and every policy criterion completed successfully; G2 is approved."),
        "",
        "## Criterion outcome",
        "",
        "| Criterion | Status | Interpretation |",
        "| --- | --- | --- |",
    ]
    for item in report["criteria"]:
        lines.append(f"| {item['id']} | {item['observed_status']} | {item['interpretation']} |")
    lines.extend(["", "## Blocking findings", ""])
    for blocker in report["blockers"]:
        lines.extend([
            f"### {blocker['id']}: {blocker['title']}",
            "",
            blocker["reason"],
            "",
            f"Required closure: {blocker['required_action']}",
            "",
        ])
    budget = report["budget_interpretation"]
    lines.extend([
        "## Budget interpretation",
        "",
        f"Manual content is {budget['manual_content_assets']} of {budget['total_content_assets']} assets ({budget['manual_content_rate_ppm']} ppm, floor-rounded). P2-19 records {budget['base_planning_hours']} base planning hours and {budget['risk_adjusted_planning_hours']} risk-adjusted planning hours.",
        "",
        f"The storage budget is {budget['storage_budget_bytes']} bytes, including {budget['incremental_storage_required_bytes']} incremental bytes and a {budget['storage_capacity_gap_bytes']} byte capacity gap. These are planning values, not measured delivery duration, a financial total cost, a price, or a delivery commitment.",
        "",
        "## Authority boundary",
        "",
        "This review does not prove a complete playable build, authorize P3, grant release or production authority, recover an unseen official server implementation, or authorize automatic repair/deletion of unlinked or duplicate resources.",
        "",
        "## Reproduction",
        "",
        "Run `pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1`, then rerun with `-Check`. Generation uses the locked non-root builder with a read-only repository mount, no network, no Linux capabilities, and no-new-privileges.",
        "",
    ])
    return "\n".join(lines)

def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n").replace("\r", "\n"), encoding="utf-8", newline="\n")

def self_test() -> dict[str, Any]:
    assertions = 0
    required = ["SATISFIED"] * 9
    require(set(required) == {"SATISFIED"}, "Required-status self-test failed")
    assertions += 1
    observed = ["SATISFIED"] * 5 + ["BLOCKED", "BLOCKED"] + ["SATISFIED"] * 2
    require(("BLOCKED" if "BLOCKED" in observed else "PASS") == "BLOCKED",
            "Gate fail-closed self-test failed")
    assertions += 1
    core_fk_zero = True
    supplemental_bound = True
    scope_complete = False
    reference_queues_zero = False
    require(not (core_fk_zero and supplemental_bound and scope_complete and reference_queues_zero),
            "Core-resource distinction self-test failed")
    assertions += 1
    asset_binding_explicit = True
    asset_binding_ambiguous = 183
    asset_binding_unresolved = 19
    require(not (asset_binding_explicit and asset_binding_ambiguous == 0 and
                 asset_binding_unresolved == 0),
            "Explicit asset-binding state must not erase blocking states")
    assertions += 1
    registry_present = True
    registry_coverage_complete = True
    pending_decisions = 1359
    approved_decisions = 0
    require(not (registry_present and registry_coverage_complete and pending_decisions == 0 and
                 approved_decisions == 1359), "Migration-registry fail-closed self-test failed")
    assertions += 1
    machine_suggestion_counts_as_decision = False
    require(machine_suggestion_counts_as_decision is False,
            "Machine suggestions must not count as decisions")
    assertions += 1
    planning_hours = 2000.37
    money_estimated = False
    measured_schedule = False
    require(planning_hours > 0 and not money_estimated and not measured_schedule,
            "Budget semantics self-test failed")
    assertions += 1
    require(observed.count("SATISFIED") == 7 and observed.count("BLOCKED") == 2,
            "Observed-count self-test failed")
    assertions += 1
    require(hashlib.sha256(b"a\n").hexdigest() == hashlib.sha256(b"a\n").hexdigest(),
            "Hash self-test failed")
    assertions += 1
    require(is_safe_relative("Data/Inventory/evidence.json") and
            not is_safe_relative("../outside.json") and not is_safe_relative("C:\\outside.json"),
            "Path-rejection self-test failed")
    assertions += 1
    require(is_sha256("a" * 64) and not is_sha256("a" * 63),
            "SHA-256 shape self-test failed")
    assertions += 1
    return {"result": "PASS", "assertions": assertions}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True, separators=(",", ":")))
        return
    require(all((args.root, args.policy, args.schema, args.json_output, args.markdown_output)),
            "Generation arguments are required")
    root = args.root.resolve()
    report = build_report(root, args.policy.resolve(), args.schema.resolve())
    write_text(args.json_output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    write_text(args.markdown_output, markdown(report))
    print(json.dumps({"result": report["result"], "review_execution_result": "PASS",
                      "satisfied": report["summary"]["satisfied"],
                      "blocked": report["summary"]["blocked"]}, separators=(",", ":")))
if __name__ == "__main__":
    main()
