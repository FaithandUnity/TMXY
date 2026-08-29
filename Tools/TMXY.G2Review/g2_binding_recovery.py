"""P2-20A.8 production-binding recovery cross-proof binding for G2."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable


def bind_binding_recovery(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["binding_recovery"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    report = load_json(path)
    require(report.get("task_id") == spec["task_id"] and
            report.get("criterion_id") == spec["criterion_id"] and
            report.get("evidence_revision") == spec["evidence_revision"],
            "P2-20A.8 recovery cross-proof identity mismatch")
    require(report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            report.get("g2_06_satisfied") is False and
            report.get("p3_authorized") is False,
            "P2-20A.8 recovery cross-proof was falsely promoted")
    require(report.get("frozen_scope") == {"targets": 19, "candidate_edges": 24} and
            report.get("measured") == {
                "attempted": {"targets": 17, "candidate_edges": 21},
                "successful": {"targets": 7, "candidate_edges": 9},
                "effective_resolution": {
                    "resolved": {"targets": 7, "candidate_edges": 9},
                    "ambiguous": {"targets": 0, "candidate_edges": 0},
                    "unresolved": {"targets": 12, "candidate_edges": 15},
                },
            }, "P2-20A.8 recovery measurements drifted")
    authority = report["authority_boundary"]
    require(authority == {
                "a4_is_authoritative": True, "a8_is_cross_proof_only": True,
                "a8_may_change_counts": False, "attempt_is_success": False,
                "machine_can_approve_disposition": False,
            }, "P2-20A.8 authority boundary drifted")
    require(report["preserved_blockers"] == {
                "identity_semantic_ambiguous_targets": 15,
                "identity_semantic_ambiguous_edges": 30,
                "asset_effective_ambiguous_targets": 189,
                "asset_effective_ambiguous_edges": 546,
                "asset_effective_unresolved_targets": 12,
                "asset_effective_unresolved_edges": 15,
                "auxiliary_nonterminal_instances": 212,
                "conditional_required_missing": 29,
                "migration_pending": 1359,
                "g2_satisfied": 7, "g2_blocked": 2,
            }, "P2-20A.8 preserved blockers drifted")
    contracts = report["contracts"]
    for key, relative_contract in (
        ("policy_sha256", "Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json"),
        ("schema_sha256", "Contracts/data-schema/g2-asset-binding-recovery-v1.schema.json"),
        ("detail_schema_sha256",
         "Contracts/data-schema/g2-asset-binding-recovery-detail-v1.schema.json"),
    ):
        contract_path = resolve_inside(root, relative_contract)
        require(contracts.get(key) == sha256(contract_path),
                "P2-20A.8 recovery contract hash drifted")
    require(report["disclosure"]["tracked_aggregate_and_hash_only"] is True and
            report["disclosure"]["anonymous_detail_only"] is True and
            not any(report["disclosure"][name] for name in
                    ("raw_names", "private_source_paths", "exact_primary_keys",
                     "declared_or_observed_values", "decoded_confidential_payloads")),
            "P2-20A.8 disclosure boundary drifted")
    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"], "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"], "path": relative,
        "sha256": digest, "result": report["result"],
        "review_execution_result": report["review_execution_result"],
        "task_status": report["task_status"],
        "completion_criteria_satisfied": report["completion_criteria_satisfied"],
        "g2_06_satisfied": report["g2_06_satisfied"],
    }
    aggregate = (f"BINDING_RECOVERY|{spec['task_id']}|{spec['criterion_id']}|"
                 f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, report, aggregate
