"""P2-20A.8 production-binding recovery cross-proof binding for G2."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Callable


BASE_PLAN_CONTRACT = (
    "Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv")
LIVE_ATTEMPT_PLAN = (
    "Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts.tsv")
INPUT_BINDINGS = [
    ("a7_report", "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True),
    ("a7_inventory", "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
    ("a7_detail", "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("base_plan_contract", BASE_PLAN_CONTRACT, True),
    ("attempt_tsv", LIVE_ATTEMPT_PLAN, False),
    ("effective_plan_tsv", "Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv", False),
    ("qtx_prefix_policy", "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json", True),
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_inventory", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_effective_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("policy", "Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-asset-binding-recovery-v1.schema.json", True),
    ("detail_schema", "Contracts/data-schema/g2-asset-binding-recovery-detail-v1.schema.json", True),
]


def _line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def _expected_input_bindings(root: Path, resolve_inside: Callable[[Path, str], Path],
                             sha256: Callable[[Path], str]) -> dict[str, Any]:
    entries = []
    for role, relative, tracked in INPUT_BINDINGS:
        path = resolve_inside(root, relative)
        entries.append({"role": role, "path": relative, "tracked": tracked,
                        "bytes": path.stat().st_size, "lines": _line_count(path),
                        "sha256": sha256(path)})
    canonical = "".join(f"{x['role']}\t{x['path']}\t{str(x['tracked']).lower()}\t"
                        f"{x['bytes']}\t{x['lines']}\t{x['sha256']}\n" for x in entries)
    return {"aggregate_sha256": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
            "entries": entries}


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
    contract_path = resolve_inside(root, BASE_PLAN_CONTRACT)
    live_attempt_path = resolve_inside(root, LIVE_ATTEMPT_PLAN)
    require(report.get("task_id") == spec["task_id"] and
            report.get("criterion_id") == spec["criterion_id"] and
            report.get("evidence_revision") == spec["evidence_revision"],
            "P2-20A.8 recovery cross-proof identity mismatch")
    require(report.get("input_bindings") ==
            _expected_input_bindings(root, resolve_inside, sha256) and
            contract_path.read_bytes() == live_attempt_path.read_bytes(),
            "P2-20A.8 input chain is not exactly closed or its plans differ")
    require(report.get("result") == "BLOCKED" and
            report.get("review_execution_result") == "PASS" and
            report.get("task_status") == "BLOCKED" and
            report.get("completion_criteria_satisfied") is False and
            report.get("g2_06_satisfied") is False and
            report.get("p3_authorized") is False,
            "P2-20A.8 recovery cross-proof was falsely promoted")
    failure = load_json(resolve_inside(
        root, "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json"))
    effective = failure["measured"]["effective"]
    expected_resolved = {"targets": effective["resolved_targets"],
                         "candidate_edges": effective["resolved_edges"]}
    expected_unresolved = {"targets": effective["unresolved_targets"],
                           "candidate_edges": effective["unresolved_edges"]}
    require(report.get("frozen_scope") == {"targets": 19, "candidate_edges": 24} and
            report.get("measured") == {
                "attempted": {"targets": 17, "candidate_edges": 21},
                "successful": expected_resolved,
                "effective_resolution": {
                    "resolved": expected_resolved,
                    "ambiguous": {"targets": 0, "candidate_edges": 0},
                    "unresolved": expected_unresolved,
                },
            } and expected_resolved["targets"] + expected_unresolved["targets"] == 19 and
            expected_resolved["candidate_edges"] + expected_unresolved["candidate_edges"] == 24,
            "P2-20A.8 recovery measurements drifted from authoritative A.7")
    authority = report["authority_boundary"]
    require(authority == {
                "a4_is_authoritative": True, "a8_is_cross_proof_only": True,
                "a8_may_change_counts": False, "attempt_is_success": False,
                "machine_can_approve_disposition": False,
            }, "P2-20A.8 authority boundary drifted")
    failure_blockers = failure["preserved_blockers"]
    blocker_keys = ("identity_semantic_ambiguous_targets", "identity_semantic_ambiguous_edges",
                    "asset_effective_ambiguous_targets", "asset_effective_ambiguous_edges",
                    "asset_effective_unresolved_targets", "asset_effective_unresolved_edges",
                    "auxiliary_nonterminal_instances", "conditional_required_missing",
                    "migration_pending", "g2_satisfied", "g2_blocked")
    require(report["preserved_blockers"] ==
            {key: failure_blockers[key] for key in blocker_keys},
            "P2-20A.8 preserved blockers drifted from authoritative A.7")
    contracts = report["contracts"]
    for key, relative_contract in (
        ("policy_sha256", "Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json"),
        ("schema_sha256", "Contracts/data-schema/g2-asset-binding-recovery-v1.schema.json"),
        ("detail_schema_sha256",
         "Contracts/data-schema/g2-asset-binding-recovery-detail-v1.schema.json"),
        ("base_plan_contract_sha256", BASE_PLAN_CONTRACT),
    ):
        contract_path = resolve_inside(root, relative_contract)
        require(contracts.get(key) == sha256(contract_path),
                "P2-20A.8 recovery contract hash drifted")
    require(report["disclosure"]["tracked_aggregate_hash_and_anonymous_contract_only"] is True and
            report["disclosure"]["tracked_anonymous_base_plan_contract"] is True and
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
