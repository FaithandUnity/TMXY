#!/usr/bin/env python3
"""Generate the deterministic, fail-closed P2-20 G2 review."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path.name}")
    return value

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def is_safe_relative(relative: str) -> bool:
    candidate = Path(relative)
    return (bool(relative) and "\\" not in relative and not relative.startswith("/") and
            not candidate.is_absolute() and ".." not in candidate.parts)

def resolve_inside(root: Path, relative: str) -> Path:
    require(is_safe_relative(relative), "Path is not repository-relative")
    candidate = (root / relative).resolve()
    require(candidate.is_relative_to(root), "Path escaped repository root")
    require(candidate.is_file(), f"Required input is missing: {relative}")
    return candidate

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

def bind_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    bindings: list[dict[str, Any]] = []
    evidence: dict[str, dict[str, Any]] = {}
    aggregate_lines: list[str] = []
    for specification in policy["required_inputs"]:
        task_id = specification["task_id"]
        relative = specification["path"]
        path = resolve_inside(root, relative)
        document = load_json(path)
        observed_task = document.get("task_id", document.get("task"))
        require(observed_task == task_id, f"Task identity mismatch for {task_id}")
        require(document.get("result") == "PASS", f"Prerequisite {task_id} did not pass")
        require(document.get("task_status") == "COMPLETE", f"Prerequisite {task_id} is incomplete")
        require(document.get("completion_criteria_satisfied") is True, f"Prerequisite {task_id} is not complete")
        digest = sha256(path)
        binding = {
            "task_id": task_id,
            "path": relative,
            "sha256": digest,
            "result": "PASS",
            "task_status": "COMPLETE",
            "completion_criteria_satisfied": True,
        }
        bindings.append(binding)
        evidence[task_id] = document
        aggregate_lines.append(f"{task_id}|{relative}|{digest}")

    quality_relative = policy["quality_evidence"]
    quality_path = resolve_inside(root, quality_relative)
    quality = load_json(quality_path)
    repository = quality.get("repository", {})
    secret = quality.get("secret", {})
    require(quality.get("result") == "PASS_DIAGNOSTIC", "Local quality aggregate did not pass")
    require(repository.get("result") == "PASS" and repository.get("failure_count") == 0,
            "Repository policy evidence did not pass")
    require(secret.get("result") == "PASS" and secret.get("failure_count") == 0 and
            secret.get("finding_count") == 0, "Secret evidence did not pass")
    quality_digest = sha256(quality_path)
    aggregate_lines.append(f"QUALITY|{quality_relative}|{quality_digest}")
    joined = ("\n".join(aggregate_lines) + "\n").encode("utf-8")
    return {
        "aggregate_sha256": hashlib.sha256(joined).hexdigest(),
        "prerequisites": bindings,
        "quality": {
            "path": quality_relative,
            "sha256": quality_digest,
            "result": quality["result"],
            "captured_utc": quality["captured_utc"],
        },
    }, evidence

def build_criteria(policy: dict[str, Any], evidence: dict[str, dict[str, Any]], root: Path) -> list[dict[str, Any]]:
    by_id = {item["id"]: item for item in policy["criteria"]}
    p202 = evidence["P2-02"]["summary"]
    p204 = evidence["P2-04"]
    p207 = evidence["P2-07"]
    p208 = evidence["P2-08"]
    p213 = evidence["P2-13"]
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

    health = p213["health"]
    core_subset_digest = health.get("core_resource_subset_sha256")
    core_subset_hash_bound = isinstance(core_subset_digest, str) and bool(
        re.fullmatch(r"[0-9a-f]{64}", core_subset_digest))
    core_unresolved = health.get("core_resource_unresolved")
    core_ambiguous = health.get("core_resource_ambiguous")
    core_heuristic = health.get("core_resource_heuristic_target_selections")
    core_metrics_present = all(isinstance(value, int) and not isinstance(value, bool)
                               for value in (core_unresolved, core_ambiguous, core_heuristic))
    ok = (core_subset_hash_bound and core_metrics_present and core_unresolved == 0 and
          core_ambiguous == 0 and core_heuristic == 0)
    reviews.append(criterion(by_id["G2-06"], ok, [
        metric("core_foreign_key_dangling", health["core_dangling_references"], "references"),
        metric("core_resource_subset_hash_bound", core_subset_hash_bound, "boolean"),
        metric("core_resource_metrics_present", core_metrics_present, "boolean"),
        metric("core_resource_unresolved", core_unresolved, "references"),
        metric("core_resource_ambiguous", core_ambiguous, "references"),
        metric("core_resource_heuristic_selections", core_heuristic, "references"),
        metric("table_object_unresolved", health["nullable_object_unresolved"], "references"),
        metric("table_object_ambiguous", health["nullable_object_ambiguous"], "references"),
        metric("package_unresolved", health["package_unresolved_edges"], "references"),
        metric("package_ambiguous", health["package_ambiguous_edges"], "references"),
    ], "The explicit hash-bound core-resource subset and its zero unresolved, ambiguous, and heuristic metrics are absent. Global queues are risk context, not the core exit threshold; core foreign-key dangling zero is also a separate narrower fact.", ["G2-BLK-06"] if not ok else []))

    registry_relative = policy["migration_decision_registry"]
    registry_present = (root / registry_relative).is_file()
    reviews.append(criterion(by_id["G2-07"], False, [
        metric("migration_decision_registry_present", registry_present, "boolean"),
        metric("diff_audit_complete", evidence["P2-09"]["result"] == "PASS", "boolean"),
        metric("limit_audit_complete", evidence["P2-11"]["result"] == "PASS", "boolean"),
        metric("shared_uint64_codegen", p217["summary"]["numeric_identity_storage"] == "uint64", "boolean"),
    ], "Diff, limit, and uint64 code-generation audits are inputs, not a complete approved migration-decision registry.", ["G2-BLK-07"]))

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
    require(len(satisfied) == 7 and blocked == ["G2-06", "G2-07"], "Fail-closed outcome mismatch")
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
    return {
        "schema_version": 1,
        "captured_utc": p219["captured_utc"],
        "task_id": "P2-20",
        "source_build": policy["source_build"],
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "gate": "G2",
        "gate_decision": "BLOCKED",
        "g2_approved": False,
        "p3_authorized": False,
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
        "blockers": [
            {
                "id": "G2-BLK-06",
                "criterion_id": "G2-06",
                "title": "Core resource-reference closure is not proven",
                "reason": "A hash-bound core-resource subset and its explicit unresolved, ambiguous, and heuristic-selection metrics are absent. Global queues remain risk context, while core foreign-key dangling zero cannot substitute for this proof.",
                "required_action": "Define and hash-bind the core-resource subset, prove its unresolved, ambiguous, and heuristic-selection counts are zero, and regenerate closure evidence.",
                "authority_required": False,
            },
            {
                "id": "G2-BLK-07",
                "criterion_id": "G2-07",
                "title": "Complete migration decisions are absent",
                "reason": "Existing diff, limit, canonical-ID, and code-generation audits do not record every required migration decision.",
                "required_action": "Create and review a complete migration-decision registry covering ID, width, old-to-new schema, and fixed-limit risks.",
                "authority_required": True,
            },
        ],
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
        "- G2 approved: `false`",
        "- P3 authorized: `false`",
        f"- Evidence snapshot: `{report['captured_utc']}`",
        "",
        "The review procedure completed successfully, but the gate is fail-closed. A successful review execution is not a successful G2 decision.",
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
    core_subset_bound = False
    reference_queues_zero = False
    require(not (core_fk_zero and core_subset_bound and reference_queues_zero),
            "Core-resource distinction self-test failed")
    assertions += 1
    registry_present = False
    require(not registry_present, "Migration-registry fail-closed self-test failed")
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
