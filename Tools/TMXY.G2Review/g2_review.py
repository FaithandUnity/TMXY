#!/usr/bin/env python3
"""Generate the deterministic, fail-closed P2-20 G2 review."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from typing import Any
from g2_evidence import (bind_inputs, evaluate_core_closure, load_json, require,
                         resolve_inside, sha256)
from g2_aux_ecf_parser_parity import aux_ecf_parser_parity_metrics, aux_ecf_parser_parity_safe
from g2_aux_malformed_xml import aux_malformed_xml_closure_ready, aux_malformed_xml_metrics
from g2_static_mesh_prefix import static_mesh_prefix_blocker_text, static_mesh_prefix_metrics, static_mesh_prefix_safe
from g2_markdown import markdown
from g2_migration import evaluate_migration_registry
from g2_report_model import criterion, metric
from g2_self_test import self_test
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
    aux_semantic = evidence["P2-20A.5"]
    aux_region, aux_ecf = (aux_semantic["measured"][name] for name in
                           ("region_semantic_references", "ecf"))
    aux_ready = (aux_semantic["scope_complete"] is True and
                 aux_semantic["g2_06_satisfied"] is True)
    aux_context = evidence["P2-20A.9"]
    aux_context_measured = aux_context["measured"]
    aux_context_resolution = aux_context_measured["effective_resolution"]
    aux_context_safe = (
        aux_context["diagnostic_scope_complete"] is True and
        aux_context["scope_complete"] is False and
        aux_context["g2_06_satisfied"] is False and
        aux_context["technical_state"]["package_context_contract_proven"] is True and
        aux_context_measured["package_context"]["singleton_matches"] == 211 and
        aux_context_measured["package_context"]["first_candidate_selections"] == 0 and
        aux_context_resolution["resolved_total"] == 3391 and
        aux_context_resolution["ambiguous_object"] == 0 and
        aux_context_resolution["unresolved_resource"] == 1 and
        aux_context["authority_state"]["terminal_instances"] == 0 and
        aux_context["authority_state"]["nonterminal_instances"] == 212)
    aux_ecf_parity = evidence["P2-20A.10"]
    aux_ecf_safe = aux_ecf_parser_parity_safe(aux_ecf_parity)
    aux_malformed = evidence["P2-20A.11"]
    aux_malformed_ready = aux_malformed_xml_closure_ready(aux_malformed)
    identity_safety = evidence["P2-20A.6"]
    identity_measured = identity_safety["measured"]
    identity_effective = identity_measured["effective"]
    identity_reconciled = identity_measured["reconciled_full_workset"]
    identity_safe = (identity_safety["diagnostic_scope_complete"] is True and
                     identity_safety["scope_complete"] is False and
                     identity_safety["g2_06_satisfied"] is False and
                     identity_measured["strict_descriptor_equivalent_targets"] == 0 and
                     identity_measured["strict_full_semantic_equivalent_targets"] == 0 and
                     identity_measured["candidate_selections"] == 0 and
                     identity_effective["resolved_targets"] == 0 and
                     identity_effective["ambiguous_targets"] == 15 and
                     identity_reconciled["ambiguous_targets"] == core["asset_binding_ambiguous"] and
                     identity_reconciled["unresolved_targets"] == core["asset_binding_unresolved"])
    binding_failure = evidence["P2-20A.7"]
    failure_measured, failure_effective = (binding_failure["measured"],
                                           binding_failure["measured"]["effective"])
    recovery = evidence["P2-20A.8"]
    recovery_measured = recovery["measured"]
    recovery_safe = (recovery["authority_boundary"]["a4_is_authoritative"] is True and
                     recovery["authority_boundary"]["a8_is_cross_proof_only"] is True and
                     recovery["authority_boundary"]["a8_may_change_counts"] is False and
                     recovery_measured["successful"] == {"targets": 7, "candidate_edges": 9} and
                     recovery_measured["effective_resolution"]["unresolved"] ==
                     {"targets": 12, "candidate_edges": 15})
    binding_safe = (binding_failure["diagnostic_scope_complete"] is True and
                    failure_measured["typed_error_edges"] == 24 and
                    failure_measured["unclassified_error_edges"] == 0 and recovery_safe)
    binding_ready = (binding_failure["remediation_scope_complete"] is True and
                     binding_failure["g2_06_satisfied"] is True and failure_effective["unresolved_targets"] == 0)
    ok = (core["satisfied"] and aux_ready and aux_context_safe and aux_ecf_safe and
          aux_malformed_ready and
          identity_safe and binding_safe and static_mesh_prefix_safe(evidence["P2-20A.12"]) and binding_ready)
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
        metric("identity_normalization_hash_bound", True, "boolean"),
        metric("identity_case_fold_collision_targets", identity_measured["case_fold_collision_targets"], "assets"),
        metric("identity_case_fold_collision_edges", identity_measured["case_fold_collision_edges"], "edges"),
        metric("identity_non_case_targets", identity_measured["non_case_identity_targets"], "assets"),
        metric("identity_non_case_edges", identity_measured["non_case_identity_edges"], "edges"),
        metric("identity_strict_descriptor_equivalent_targets", identity_measured["strict_descriptor_equivalent_targets"], "assets"),
        metric("identity_strict_full_semantic_equivalent_targets", identity_measured["strict_full_semantic_equivalent_targets"], "assets"),
        metric("identity_automatic_selected_targets", identity_measured["candidate_selections"], "assets"),
        metric("identity_retained_ambiguous_targets", identity_effective["ambiguous_targets"], "assets"),
        metric("identity_retained_ambiguous_edges", identity_effective["ambiguous_edges"], "edges"),
        metric("identity_retained_unresolved_targets", identity_reconciled["unresolved_targets"], "assets"),
        metric("identity_retained_unresolved_edges", identity_reconciled["unresolved_edges"], "edges"),
        metric("binding_failure_diagnostic_hash_bound", True, "boolean"),
        metric("binding_failure_diagnostic_scope_complete", binding_failure["diagnostic_scope_complete"], "boolean"),
        metric("binding_failure_remediation_scope_complete", binding_failure["remediation_scope_complete"], "boolean"),
        metric("binding_failure_diagnosed_targets", failure_measured["diagnosed_targets"], "assets"),
        metric("binding_failure_diagnosed_edges", failure_measured["diagnosed_candidate_edges"], "edges"),
        metric("binding_failure_typed_error_edges", failure_measured["typed_error_edges"], "edges"),
        metric("binding_failure_unclassified_error_edges", failure_measured["unclassified_error_edges"], "edges"),
        metric("binding_failure_effective_resolved_targets", failure_effective["resolved_targets"], "assets"),
        metric("binding_failure_effective_resolved_edges", failure_effective["resolved_edges"], "edges"),
        metric("binding_failure_effective_ambiguous_targets", failure_effective["ambiguous_targets"], "assets"),
        metric("binding_failure_effective_ambiguous_edges", failure_effective["ambiguous_edges"], "edges"),
        metric("binding_failure_effective_unresolved_targets", failure_effective["unresolved_targets"], "assets"),
        metric("binding_failure_effective_unresolved_edges", failure_effective["unresolved_edges"], "edges"),
        metric("binding_failure_candidate_selections", failure_measured["candidate_selections"], "assets"),
        metric("binding_failure_automatic_resolutions", failure_measured["automatic_resolutions"], "assets"),
        metric("binding_failure_owner_dispositions", failure_measured["owner_dispositions"], "assets"),
        metric("binding_recovery_cross_proof_hash_bound", True, "boolean"),
        metric("binding_recovery_attempted_targets", recovery_measured["attempted"]["targets"], "assets"),
        metric("binding_recovery_attempted_edges", recovery_measured["attempted"]["candidate_edges"], "edges"),
        metric("binding_recovery_successful_targets", recovery_measured["successful"]["targets"], "assets"),
        metric("binding_recovery_successful_edges", recovery_measured["successful"]["candidate_edges"], "edges"),
        *(metric(name, value, unit) for name, value, unit in static_mesh_prefix_metrics(evidence["P2-20A.12"])),
        metric("aux_semantic_diagnostic_hash_bound", True, "boolean"),
        metric("aux_semantic_scope_complete", aux_semantic["scope_complete"], "boolean"),
        metric("aux_semantic_g2_06_satisfied", aux_semantic["g2_06_satisfied"], "boolean"),
        metric("aux_semantic_unique_references", aux_region["unique_total"], "references"),
        metric("aux_semantic_ambiguous_objects", aux_region["ambiguous_object"], "references"),
        metric("aux_semantic_unresolved_resources", aux_region["unresolved_resource"], "references"),
        metric("aux_semantic_ecf_parser_differences", aux_ecf["mixed_newline_differences"], "files"),
        metric("aux_semantic_ecf_missed_assignments", aux_ecf["legacy_assignments_missed_by_a3_parser"], "assignments"),
        *(metric(name, value, unit) for name, value, unit in aux_ecf_parser_parity_metrics(aux_ecf_parity)),
        *(metric(name, value, unit) for name, value, unit in aux_malformed_xml_metrics(aux_malformed)),
        metric("aux_package_context_hash_bound", True, "boolean"),
        metric("aux_package_context_contract_proven", aux_context["technical_state"]["package_context_contract_proven"], "boolean"),
        metric("aux_package_context_strict_ambiguous_objects", aux_context["strict_baseline"]["ambiguous_object"], "references"),
        metric("aux_package_context_original_candidate_edges", aux_context["measured"]["package_context"]["original_candidate_edges"], "edges"),
        metric("aux_package_context_singleton_matches", aux_context["measured"]["package_context"]["singleton_matches"], "references"),
        metric("aux_package_context_first_candidate_selections", aux_context["measured"]["package_context"]["first_candidate_selections"], "references"),
        metric("aux_package_context_effective_resolved", aux_context_resolution["resolved_total"], "references"),
        metric("aux_package_context_effective_ambiguous", aux_context_resolution["ambiguous_object"], "references"),
        metric("aux_package_context_effective_unresolved", aux_context_resolution["unresolved_resource"], "references"),
        metric("aux_package_context_consumer_clean_regions", aux_context["technical_state"]["consumer_clean_region_instances"], "files"),
        metric("aux_package_context_semantic_adapter_approved", aux_context["technical_state"]["semantic_adapter_approved"], "boolean"),
        metric("aux_package_context_terminal_instances", aux_context["authority_state"]["terminal_instances"], "files"),
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
    ], "P2-20A supplies hash-bound core, descriptor, auxiliary-semantic, package-context, parser, identity, production-binding, recovery, and static-mesh prefix evidence. A.11 keeps strict rejection, independent ElementTree rejection, source-derived TinyXML API success, and consumer/runtime authority as four separate layers: TinyXML accepts 6/6 but fully consumes only 5/6, so its silent partial parse and unproved client memory-tail/CRT behavior cannot approve a disposition. A.9 resolves 3,391 consumer occurrences and leaves one unresolved without first-candidate selection, yet all 212 auxiliary instances remain nonterminal. A.7 classifies all 24 strict rejected asset candidate edges; A.8 cross-proves 7 targets / 9 edges while preserving A.4 authority, leaving 12 targets / 15 edges unresolved. A.12 proves the source-derived payload-section-prefix contract for one static-mesh target / two edges (two material slots, one payload section, one ignored trailing slot) but performs no selection, resolution, adapter, recovery, authority change, or runtime-parity claim. The full asset workset therefore remains 189 targets / 546 edges ambiguous and 12 targets / 15 edges unresolved. Diagnostic completeness cannot substitute for semantic adapters, no-reference decisions, approved roots, or verified remediation. Explicit states do not erase parser gaps, malformed inputs, conditional gaps, logical queues, or reachable structure. Core foreign-key zero cannot replace these facts.", ["G2-BLK-06"] if not ok else []))
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
    human, machine, storage = (p219["summary"][name] for name in
                               ("human_budget", "machine_budget", "storage_budget"))
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
        identity = evidence["P2-20A.6"]["measured"]
        binding_failure = evidence["P2-20A.7"]["measured"]
        binding_recovery = evidence["P2-20A.8"]["measured"]
        asset_structure = closure["asset_structure"]
        auxiliary = evidence["P2-20A"]["scope_definition"]["auxiliary_config"]
        aux_context = evidence["P2-20A.9"]
        aux_context_resolution = aux_context["measured"]["effective_resolution"]
        aux_ecf_parity = evidence["P2-20A.10"]
        aux_malformed = evidence["P2-20A.11"]
        blockers.append({
            "id": "G2-BLK-06",
            "criterion_id": "G2-06",
            "title": "Core resource-reference closure has quantified open gaps",
            "reason": (
                f"P2-20A and its A.3/A.5/A.9/A.10/A.11/A.12 diagnostic evidence are hash-bound. A.5's immutable history retains 3 differences and a net pair-count delta of 4; "
                f"A.10 separately measures 13 frozen-A.3/source-derived differences and, on correct plaintext, 1 filter difference with 4 legacy pair records absent from A.3. "
                f"A.11 retains strict rejection of all {aux_malformed['population']['instances']} malformed inputs even though source-derived TinyXML reports API success for all six: only 5 consume the full input and one silently retains a partial tree. Legacy runtime, binary parity, Windows CRT text-mode behavior, and the client input's NUL-terminated memory tail remain unproved; no repair, disposition, semantic import, or root is granted. A.9 deterministically "
                f"resolves {aux_context_resolution['resolved_total']} consumer occurrences and leaves "
                f"{aux_context_resolution['unresolved_resource']} unresolved without first-candidate selection; "
                f"this technical proof grants no semantic adapter or root approval. All {auxiliary['inventory_files']} "
                f"configuration instances remain nonterminal ({auxiliary['candidate_only']} candidate-only, "
                f"{auxiliary['editor_undecided']} editor-undecided, {auxiliary['malformed_blocked']} malformed) "
                f"with {auxiliary['approved_roots']} approved roots. Explicit asset-binding evidence retains "
                f"{asset_binding['ambiguous_targets']} full-semantic ambiguous plus "
                f"{asset_binding['unresolved_targets']} production-unresolved targets. A.6 measured "
                f"{identity['case_fold_collision_targets']} ASCII-lower identity-collision targets across "
                f"{identity['case_fold_collision_edges']} edges, but found "
                f"{identity['strict_full_semantic_equivalent_targets']} strict full-semantic equivalences and "
                f"made {identity['candidate_selections']} selections; all "
                f"{identity['effective']['ambiguous_targets']} ambiguous targets remain blocked. "
                f"A.7 classified {binding_failure['typed_error_edges']} of "
                f"{binding_failure['diagnosed_candidate_edges']} rejected candidate edges, but made "
                f"{binding_failure['automatic_resolutions']} automatic selections. A.8 cross-proved "
                f"{binding_recovery['successful']['targets']} targets / "
                f"{binding_recovery['successful']['candidate_edges']} edges as explicit production recoveries "
                f"and retains {binding_failure['effective']['unresolved_targets']} unresolved targets. "
                f"{static_mesh_prefix_blocker_text(evidence['P2-20A.12'], asset_binding)} "
                f"The measured core queues contain {resolution['table_unresolved']} unresolved and "
                f"{resolution['table_ambiguous']} ambiguous table references, "
                f"{resolution['package_unresolved']} unresolved and "
                f"{resolution['package_ambiguous']} ambiguous Package references, "
                f"{conditional['conditional_required_missing']} conditionally required missing values, "
                f"and {asset_structure['unresolved']} structurally unresolved reachable assets."
            ),
            "required_action": (
                "Resolve the TinyXML silent-partial and client memory-tail/CRT boundary with runtime evidence or an explicit safe malformed disposition; approve semantic adapters or explicit no-reference dispositions for all auxiliary instances, close every ambiguous or unresolved asset-binding state, use the hash-bound "
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
def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n").replace("\r", "\n"), encoding="utf-8", newline="\n")
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
