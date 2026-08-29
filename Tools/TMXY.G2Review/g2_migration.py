"""Fail-closed migration-registry evaluation for the P2-20 G2 review."""
from __future__ import annotations
import re
from typing import Any


def evaluate_migration_registry(registry: dict[str, Any],
                                thresholds: dict[str, Any]) -> dict[str, Any]:
    summary, completeness = registry["summary"], registry["completeness"]
    decisions = registry["decisions"]
    pending = sum(item["decision"]["status"] == "PENDING" for item in decisions)
    decided = sum(item["decision"]["status"] == "DECIDED" for item in decisions)
    approved = sum(item["approval"]["status"] == "APPROVED" and
                   item["approval"]["external_authority_verified"] is True for item in decisions)
    approval_count = sum(item["approval"]["approval_count"] for item in decisions)
    verified = sum(item["verification"]["status"] == "PASS" for item in decisions)
    suggestions = sum(item.get("machine_suggestion") is not None for item in decisions)
    suggestions_non_authoritative = all(
        item.get("machine_suggestion", {}).get("counts_as_decision") is False for item in decisions)
    pending_empty = all(item["decision"]["status"] != "PENDING" or
                        (item["decision"]["chosen_action"] is None and
                         item["approval"]["approval_count"] == 0) for item in decisions)
    if not (summary["enumerated_units"] == len(decisions) and summary["pending"] == pending and
            summary["decided"] == decided and summary["approved"] == approved and
            summary["approval_count"] == approval_count and summary["verified"] == verified):
        raise ValueError("P2-20B summary does not match the complete decision registry")
    packets = registry["review_packets"]
    is_sha = lambda value: isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None
    workflow_ready = (registry["schema_version"] == thresholds["migration_workflow_version"] and
                      registry["workflow_version"] == thresholds["migration_workflow_version"] and
                      completeness["review_packets_complete"] is True and
                      packets["packet_count"] == thresholds["migration_review_packets"] and
                      packets["member_count"] == thresholds["migration_review_packet_members"] and
                      is_sha(packets["sha256"]) and is_sha(packets["aggregate_membership_sha256"]) and
                      registry["authority_boundaries"]["machine_can_approve"] is False)
    coverage = (summary["expected_units"] == thresholds["migration_expected_units"] and
                summary["enumerated_units"] == thresholds["migration_expected_units"] and
                completeness["coverage_complete"] is True and
                completeness["missing"] == thresholds["migration_missing"] and
                completeness["duplicates"] == thresholds["migration_duplicates"] and
                completeness["orphans"] == thresholds["migration_orphans"] and
                completeness["reference_membership_enumerated"] is True and
                completeness["all_inputs_hash_bound"] is True)
    satisfied = (coverage and workflow_ready and
                 summary["pending"] == thresholds["migration_pending"] and
                 summary["decided"] == thresholds["migration_decided"] and
                 summary["approved"] == thresholds["migration_approved"] and
                 summary["verified"] == thresholds["migration_verified"] and
                 summary["approval_count"] >= thresholds["migration_minimum_approval_count"] and
                 completeness["decisions_complete"] is True and
                 completeness["approvals_complete"] is True and
                 completeness["verification_complete"] is True and suggestions_non_authoritative and
                 pending_empty and registry["authority_boundaries"]["machine_can_approve"] is False and
                 registry["g2_07_satisfied"] is True)
    return {
        "satisfied": satisfied, "coverage": coverage, "workflow_ready": workflow_ready,
        "workflow_version": registry["workflow_version"],
        "review_packets": packets["packet_count"], "review_packet_members": packets["member_count"],
        "authority_records": registry["authority_boundaries"]["authority_ledger_records"],
        "expected": summary["expected_units"], "enumerated": summary["enumerated_units"],
        "missing": completeness["missing"], "duplicates": completeness["duplicates"],
        "orphans": completeness["orphans"], "pending": summary["pending"],
        "decided": summary["decided"], "approved": summary["approved"],
        "verified": summary["verified"], "approval_count": summary["approval_count"],
        "suggestions": suggestions, "suggestions_count_as_decisions": not suggestions_non_authoritative,
        "pending_empty": pending_empty, "registry_satisfied": registry["g2_07_satisfied"],
    }
