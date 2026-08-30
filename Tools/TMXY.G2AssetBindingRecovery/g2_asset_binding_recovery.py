"""Deterministic P2-20A.8 attempt-plan and A.4 recovery cross-proof generator."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import tempfile
from pathlib import Path
from typing import Any

from recovery_common import (
    ATTEMPT_RULES, binding, binding_set, build_attempt_rows, load_frozen_a7,
    load_json, output_binding, read_plan, require, sha256_file, source_hashes,
    write_plan, write_text,
)


BASE_PLAN_CONTRACT = (
    "Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def read_bound_base_plan(live_path: Path, contract_path: Path) -> list[tuple[str, ...]]:
    require(live_path.read_bytes() == contract_path.read_bytes(),
            "Live A.7-derived attempt plan differs byte-for-byte from the frozen contract")
    return read_plan(live_path)


def validate_base_plan_contract_metadata(root: Path, contract_path: Path) -> None:
    policy = load_json(
        root / "Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json")
    require(policy["base_plan_contract"] == {
        "path": BASE_PLAN_CONTRACT, "tracked": True, "rows": 21, "bytes": 6504,
        "sha256": "4f256efc82fadda9528d502ed77dce890c8cf914e827f089422fc5c38d10fb99",
        "live_attempt_must_byte_equal": True,
    } and contract_path.stat().st_size == 6504 and
            sha256_file(contract_path) == policy["base_plan_contract"]["sha256"],
            "Frozen base-plan contract metadata drifted")


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    report, evidence, details, catalog_path = load_frozen_a7(root)
    rows = build_attempt_rows(details, source_hashes(details, catalog_path))
    require(len(rows) == 21 and len({x[0] for x in rows}) == 17,
            "A.7 eligible-attempt upper bound drifted from 17 targets / 21 edges")
    by_rule = collections.Counter((x[4], x[6]) for x in rows)
    require(by_rule == {("qtx", "payload_size_mismatch"): 16,
                        ("anim", "frame_count_mismatch"): 5},
            "A.7 eligible-attempt error distribution drifted")
    attempt_path = Path(args.attempt_tsv)
    write_plan(attempt_path, rows)
    contract_path = Path(args.base_plan_contract).resolve()
    require(contract_path.is_relative_to(root), "Base-plan contract escaped repository root")
    validate_base_plan_contract_metadata(root, contract_path)
    require(read_bound_base_plan(attempt_path, contract_path) == rows,
            "Frozen base-plan contract differs from deterministic A.7 regeneration")
    manifest = {
        "schema_version": 1,
        "evidence_revision": "P2-20A.8-prepare",
        "meaning": "UPPER_BOUND_ATTEMPT_ONLY",
        "a7_report_sha256": sha256_file(
            root / "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json"),
        "a7_inventory_sha256": sha256_file(
            root / "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json"),
        "a7_detail_sha256": report["detail_export"]["sha256"],
        "p2_12_catalog_sha256": sha256_file(catalog_path),
        "attempt_tsv_sha256": sha256_file(attempt_path),
        "base_plan_contract_path": BASE_PLAN_CONTRACT,
        "base_plan_contract_sha256": sha256_file(contract_path),
        "base_plan_contract_tracked": True,
        "attempt_matches_base_plan_contract": True,
        "frozen": {"targets": 19, "candidate_edges": 24},
        "attempted": {"targets": 17, "candidate_edges": 21},
        "by_rule": [
            {"family": "anim", "strict_error_code": "frame_count_mismatch",
             "recovery_kind": "anim_payload_frame_counts", "candidate_edges": 5},
            {"family": "qtx", "strict_error_code": "payload_size_mismatch",
             "recovery_kind": "qtx_complete_mip_chain", "candidate_edges": 16},
        ],
        "successful_recoveries": None,
        "a4_authoritative": True,
        "attempt_is_success": False,
        "g2_06_satisfied": False,
        "p3_authorized": False,
    }
    if args.prepare_manifest:
        write_text(Path(args.prepare_manifest), json_text(manifest))
    return {"result": "PASS", "meaning": "UPPER_BOUND_ATTEMPT_ONLY",
            "targets": 17, "candidate_edges": 21,
            "attempt_tsv_sha256": manifest["attempt_tsv_sha256"],
            "base_plan_contract_sha256": manifest["base_plan_contract_sha256"],
            "attempt_matches_base_plan_contract": True}


def validate_effective_plan(base: list[tuple[str, ...]], effective: list[tuple[str, ...]],
                            policy: dict[str, Any]) -> None:
    require(len(base) == len(effective), "Effective recovery plan row count drifted")
    selected = {(str(x["asset_id"]), str(x["candidate_id"])): x
                for x in policy["selected_targets"]}
    require(len(selected) == 6 and policy["scope"]["recovery_kind"] ==
            "qtx_declared_mip_payload_prefix",
            "A.13 selected recovery policy drifted")
    changes = 0
    for prior, current in zip(base, effective, strict=True):
        require(prior[:5] == current[:5] and prior[6] == current[6],
                "Effective recovery plan changed identity or strict-error fields")
        key = (prior[0], prior[1])
        if key in selected:
            expected = selected[key]
            require(prior[4:] == ("qtx", "qtx_complete_mip_chain",
                                  "payload_size_mismatch") and
                    current[5] == "qtx_declared_mip_payload_prefix" and
                    prior[2] == expected["body_sha256"] and
                    prior[3] == expected["source_sha256"],
                    "A.13 selected recovery row identity or kind drifted")
            changes += int(prior != current)
        else:
            require(prior == current, "Effective recovery plan changed an unselected row")
    require(changes == 6, "Effective recovery plan must change exactly six recovery-kind cells")


def cross_proof(a7_details: list[dict[str, Any]], attempts: list[tuple[str, ...]],
                a4_items: list[dict[str, Any]]) -> tuple[list[tuple[str, ...]], list[dict[str, Any]], dict[str, Any]]:
    attempt_map = {(x[0], x[1]): x for x in attempts}
    a7_map = {str(x["asset_id"]): x for x in a7_details}
    a4_map = {str(x["asset_id"]): x for x in a4_items if str(x.get("asset_id")) in a7_map}
    require(set(a4_map) == set(a7_map), "A.4 effective detail does not cover frozen A.7 targets")
    expected_attempts = set()
    for item in a7_details:
        for candidate in item["candidates"]:
            key = (str(item["family"]), str(candidate["error_code"]))
            if key in ATTEMPT_RULES:
                expected_attempts.add((str(item["asset_id"]), str(candidate["candidate_id"])))
    require(set(attempt_map) == expected_attempts, "Attempt plan differs from the A.7 upper bound")

    successes: list[tuple[str, ...]] = []
    detail_output: list[dict[str, Any]] = []
    resolution = collections.Counter()
    resolution_edges = collections.Counter()
    for asset_id in sorted(a7_map):
        prior, effective = a7_map[asset_id], a4_map[asset_id]
        require(effective.get("family") == prior["family"], "A.4 family drifted")
        final_resolution = str(effective.get("resolution"))
        require(final_resolution in {"RESOLVED", "AMBIGUOUS", "UNRESOLVED"},
                "A.4 effective resolution is invalid")
        candidates = {str(x["candidate_id"]): x for x in effective["candidates"]}
        require(set(candidates) == {str(x["candidate_id"]) for x in prior["candidates"]},
                "A.4 effective candidate set drifted from A.7")
        proof_candidates: list[dict[str, Any]] = []
        successful_count = 0
        attempted_count = 0
        for frozen in sorted(prior["candidates"], key=lambda x: str(x["candidate_id"])):
            candidate_id = str(frozen["candidate_id"])
            observed = candidates[candidate_id]
            require(observed.get("body_sha256") == frozen["body_sha256"] and
                    observed.get("descriptor_semantic_sha256") ==
                    frozen["descriptor_semantic_sha256"] and
                    observed.get("binding") == "REJECTED",
                    "A.4 strict candidate identity, descriptor semantic, or rejection drifted")
            attempted = (asset_id, candidate_id) in attempt_map
            applied = observed.get("recovery_applied") is True
            effective_binding = observed.get("effective_binding")
            effective_semantic = observed.get("effective_semantic_sha256")
            recovery_kind = observed.get("recovery_kind")
            require(effective_binding in {"PASS", "REJECTED"},
                    "A.4 effective binding is invalid")
            require(not applied or attempted, "A.4 applied recovery outside the attempt plan")
            require((effective_binding == "PASS") == applied,
                    "A.4 effective pass and applied recovery disagree")
            if applied:
                plan = attempt_map[(asset_id, candidate_id)]
                require(recovery_kind == plan[5] and isinstance(effective_semantic, str) and
                        len(effective_semantic) == 64,
                        "A.4 successful recovery lacks kind or semantic proof")
                successes.append(plan)
                successful_count += 1
            else:
                require(effective_semantic is None,
                        "Rejected A.4 effective binding exposes a semantic identity")
            attempted_count += int(attempted)
            proof_candidates.append({
                "candidate_id": candidate_id,
                "body_sha256": str(frozen["body_sha256"]),
                "descriptor_semantic_sha256": str(frozen["descriptor_semantic_sha256"]),
                "attempted": attempted,
                "recovery_kind": recovery_kind if applied else None,
                "strict_error_code": str(frozen["error_code"]),
                "effective_binding": effective_binding,
                "recovery_applied": applied,
                "effective_semantic_sha256": effective_semantic,
                "qtx_recovery_contract": ({
                    "stored_explicit": True,
                    "stored_equals_declared": True,
                    "effective_less_than_declared":
                        recovery_kind == "qtx_complete_mip_chain",
                    "unique_complete_prefix": True,
                    "declared_payload_prefix":
                        recovery_kind == "qtx_declared_mip_payload_prefix",
                } if applied and prior["family"] == "qtx" else None),
            })
        resolution[final_resolution] += 1
        resolution_edges[final_resolution] += int(prior["candidate_count"])
        detail_output.append({
            "asset_id": asset_id,
            "family": str(prior["family"]),
            "attempted_edges": attempted_count,
            "successful_edges": successful_count,
            "effective_resolution": final_resolution,
            "candidates": proof_candidates,
        })
    successes.sort(key=lambda x: (x[0], x[1]))
    measured = {
        "attempted": {"targets": len({x[0] for x in attempts}), "candidate_edges": len(attempts)},
        "successful": {"targets": len({x[0] for x in successes}), "candidate_edges": len(successes)},
        "effective_resolution": {
            key.lower(): {"targets": resolution[key], "candidate_edges": resolution_edges[key]}
            for key in ("RESOLVED", "AMBIGUOUS", "UNRESOLVED")
        },
    }
    require(sum(x["targets"] for x in measured["effective_resolution"].values()) == 19 and
            sum(x["candidate_edges"] for x in measured["effective_resolution"].values()) == 24,
            "A.4 effective resolution totals do not reconcile")
    return successes, detail_output, measured


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    a7_report, _, a7_details, catalog_path = load_frozen_a7(root)
    attempt_path = Path(args.attempt_tsv)
    contract_path = Path(args.base_plan_contract).resolve()
    require(contract_path.is_relative_to(root), "Base-plan contract escaped repository root")
    validate_base_plan_contract_metadata(root, contract_path)
    base_attempts = read_bound_base_plan(attempt_path, contract_path)
    require(base_attempts == build_attempt_rows(
        a7_details, source_hashes(a7_details, catalog_path)),
            "Attempt plan is not a deterministic A.7 regeneration")
    qtx_policy_path = root / (
        "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json")
    qtx_policy = load_json(qtx_policy_path)
    effective_plan_path = Path(args.effective_plan_tsv)
    attempts = read_plan(effective_plan_path)
    validate_effective_plan(base_attempts, attempts, qtx_policy)
    a4_path = Path(args.a4_effective_detail)
    a4_report_path = root / "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json"
    a4_inventory_path = root / "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json"
    a4_report, a4_inventory = load_json(a4_report_path), load_json(a4_inventory_path)
    require(a4_report["evidence_revision"] == "P2-20A.4" and
            a4_report["detail_export"]["sha256"] == sha256_file(a4_path),
            "A.4 report does not bind the effective detail")
    require(a4_inventory["outputs"]["report_json"]["sha256"] == sha256_file(a4_report_path) and
            a4_inventory["outputs"]["detail_export"]["sha256"] == sha256_file(a4_path),
            "A.4 inventory does not bind the report and effective detail")
    with a4_path.open("r", encoding="utf-8") as stream:
        a4_items = [json.loads(line) for line in stream]
    successes, details, measured = cross_proof(a7_details, attempts, a4_items)
    success_path, detail_path = Path(args.success_tsv), Path(args.detail_output)
    write_plan(success_path, successes)
    write_text(detail_path, "".join(json.dumps(x, sort_keys=True, separators=(",", ":")) + "\n"
                                    for x in details))

    policy_path = root / "Contracts/data-schema/g2-asset-binding-recovery-policy-v1.json"
    schema_path = root / "Contracts/data-schema/g2-asset-binding-recovery-v1.schema.json"
    detail_schema_path = root / "Contracts/data-schema/g2-asset-binding-recovery-detail-v1.schema.json"
    captured = args.captured_utc or utc_now()
    policy = load_json(policy_path)
    entries = [
        binding(root, "a7_report", root / "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True),
        binding(root, "a7_inventory", root / "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
        binding(root, "a7_detail", root / a7_report["detail_export"]["path"], False),
        binding(root, "p2_12_catalog", catalog_path, False),
        binding(root, "base_plan_contract", contract_path, True),
        binding(root, "attempt_tsv", attempt_path, False),
        binding(root, "effective_plan_tsv", effective_plan_path, False),
        binding(root, "qtx_prefix_policy", qtx_policy_path, True),
        binding(root, "a4_report", a4_report_path, True),
        binding(root, "a4_inventory", a4_inventory_path, True),
        binding(root, "a4_effective_detail", a4_path, False),
        binding(root, "policy", policy_path, True),
        binding(root, "schema", schema_path, True),
        binding(root, "detail_schema", detail_schema_path, True),
    ]
    report = {
        "schema_version": 1, "evidence_revision": "P2-20A.8", "captured_utc": captured,
        "task_id": "P2-20A", "criterion_id": "G2-06", "result": "BLOCKED",
        "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "g2_06_satisfied": False,
        "p3_authorized": False, "input_bindings": binding_set(entries),
        "outputs": {
            "attempt_tsv": output_binding(root, Path(args.attempt_tsv), args.attempt_advertised),
            "effective_plan_tsv": output_binding(
                root, effective_plan_path, args.effective_plan_advertised),
            "success_tsv": output_binding(root, success_path, args.success_advertised),
            "detail_export": output_binding(root, detail_path, args.detail_advertised),
        },
        "frozen_scope": {"targets": 19, "candidate_edges": 24}, "measured": measured,
        "authority_boundary": {
            "a4_is_authoritative": True, "a8_is_cross_proof_only": True,
            "a8_may_change_counts": False, "attempt_is_success": False,
            "machine_can_approve_disposition": False,
        },
        "preserved_blockers": policy["preserved_blockers"],
        "contracts": {"policy_sha256": sha256_file(policy_path),
            "schema_sha256": sha256_file(schema_path),
            "detail_schema_sha256": sha256_file(detail_schema_path),
            "base_plan_contract_sha256": sha256_file(contract_path)},
        "disclosure": {"tracked_aggregate_hash_and_anonymous_contract_only": True,
            "tracked_anonymous_base_plan_contract": True,
            "anonymous_detail_only": True, "raw_names": False,
            "private_source_paths": False, "exact_primary_keys": False,
            "declared_or_observed_values": False, "decoded_confidential_payloads": False},
    }
    report_path, markdown_path = Path(args.json_output), Path(args.markdown_output)
    write_text(report_path, json_text(report))
    markdown = (
        "# P2-20A.8 Asset Binding Recovery Cross-Proof\n\n"
        f"- Result: `BLOCKED` (cross-proof execution `PASS`)\n"
        f"- Frozen A.7 scope: 19 targets / 24 candidate edges\n"
        f"- Tracked anonymous base-plan contract: 21 rows, byte-equal to live A.7 derivation\n"
        f"- Eligible-attempt upper bound: {measured['attempted']['targets']} targets / {measured['attempted']['candidate_edges']} edges\n"
        f"- Effective recovery plan: 21 edges with exactly six A.13 recovery-kind substitutions\n"
        f"- Production recovery successes: {measured['successful']['targets']} targets / {measured['successful']['candidate_edges']} edges\n"
        f"- A.4 effective resolved: {measured['effective_resolution']['resolved']['targets']} targets / {measured['effective_resolution']['resolved']['candidate_edges']} edges\n"
        f"- A.4 effective ambiguous: {measured['effective_resolution']['ambiguous']['targets']} targets / {measured['effective_resolution']['ambiguous']['candidate_edges']} edges\n"
        f"- A.4 effective unresolved: {measured['effective_resolution']['unresolved']['targets']} targets / {measured['effective_resolution']['unresolved']['candidate_edges']} edges\n\n"
        "A.4 remains the sole authority for effective resolution counts. A.8 only proves that every "
        "successful recovery belonged to the frozen A.7 attempt scope. G2-06 and P3 remain blocked.\n"
    )
    write_text(markdown_path, markdown)
    evidence = {"schema_version": 1, "evidence_revision": "P2-20A.8",
                "captured_utc": captured, "result": "BLOCKED", "measured": measured,
                "report": output_binding(root, report_path, args.json_advertised),
                "report_markdown": output_binding(root, markdown_path, args.markdown_advertised),
                "outputs": report["outputs"], "contracts": report["contracts"],
                "authority_boundary": report["authority_boundary"],
                "disclosure": report["disclosure"]}
    write_text(Path(args.evidence_output), json_text(evidence))
    return {"result": "PASS", "task_status": "BLOCKED", **measured,
            "report_sha256": sha256_file(report_path)}


def self_test() -> dict[str, Any]:
    assertions = 0
    sha = lambda value: f"{value:064x}"
    details: list[dict[str, Any]] = []
    cursor = 100
    for index in range(19):
        family = "qtx" if index < 12 else "anim" if index < 18 else "sm"
        count = 2 if index < 4 or index == 18 else 1
        candidates = []
        for edge in range(count):
            error = ("payload_size_mismatch" if family == "qtx" else
                     "frame_count_mismatch" if family == "anim" and index < 17 else
                     "invalid_track_count" if family == "anim" else "material_slot_mismatch")
            candidates.append({"candidate_id": sha(cursor), "body_sha256": sha(cursor + 1000),
                "error_code": error})
            cursor += 1
        details.append({"asset_id": sha(index + 1), "family": family,
                        "candidate_count": count, "candidates": candidates})
    sources = {x["asset_id"]: sha(2000 + index) for index, x in enumerate(details)}
    attempts = build_attempt_rows(details, sources)
    require(len(attempts) == 21 and len({x[0] for x in attempts}) == 17,
            "self-test attempt scope failed"); assertions += 2
    with tempfile.TemporaryDirectory() as temp:
        plan = Path(temp) / "plan.tsv"
        contract = Path(temp) / "contract.tsv"
        write_plan(plan, attempts)
        write_plan(contract, attempts)
        require(read_bound_base_plan(plan, contract) == attempts,
                "self-test plan contract round trip failed"); assertions += 4
        contract.write_bytes(contract.read_bytes().replace(b"\n", b"\r\n", 1))
        try:
            read_bound_base_plan(plan, contract)
            raise AssertionError("byte-different plan contract was accepted")
        except ValueError:
            assertions += 1
    a4 = []
    effective_attempts = list(attempts)
    selected_indexes = [index for index, row in enumerate(attempts)
                        if row[4] == "qtx"][:6]
    selected_policy = []
    for index in selected_indexes:
        row = attempts[index]
        effective_attempts[index] = row[:5] + ("qtx_declared_mip_payload_prefix",) + row[6:]
        selected_policy.append({"asset_id": row[0], "candidate_id": row[1],
                                "body_sha256": row[2], "source_sha256": row[3]})
    validate_effective_plan(attempts, effective_attempts, {
        "scope": {"recovery_kind": "qtx_declared_mip_payload_prefix"},
        "selected_targets": selected_policy,
    }); assertions += 4
    selected_keys = {(effective_attempts[index][0], effective_attempts[index][1])
                     for index in selected_indexes}
    additional = [(row[0], row[1]) for row in effective_attempts
                  if (row[0], row[1]) not in selected_keys][:9]
    recoverable = selected_keys | set(additional)
    for item in details:
        candidates = []
        for frozen in item["candidates"]:
            key = (item["asset_id"], frozen["candidate_id"])
            applied = key in recoverable
            candidates.append({"candidate_id": frozen["candidate_id"],
                "body_sha256": frozen["body_sha256"], "binding": "REJECTED",
                "descriptor_semantic_sha256": sha(cursor + 5000),
                "effective_binding": "PASS" if applied else "REJECTED",
                "recovery_applied": applied,
                "recovery_kind": next((x[5] for x in effective_attempts
                                       if (x[0], x[1]) == key), None),
                "effective_semantic_sha256": sha(9000) if applied else None})
            frozen["descriptor_semantic_sha256"] = sha(cursor + 5000)
        a4.append({"asset_id": item["asset_id"], "family": item["family"],
                   "resolution": "RESOLVED" if any(x["recovery_applied"] for x in candidates) else "UNRESOLVED",
                   "candidates": candidates})
    successes, proof, measured = cross_proof(details, effective_attempts, a4)
    require(len(successes) == 15 and len(proof) == 19, "self-test cross proof failed"); assertions += 3
    require(measured["attempted"]["candidate_edges"] == 21 and
            measured["successful"]["candidate_edges"] == 15,
            "self-test measured counts failed"); assertions += 3
    tampered = effective_attempts[:-1]
    try:
        cross_proof(details, tampered, a4)
        raise AssertionError("tampered attempt plan was accepted")
    except ValueError:
        assertions += 2
    return {"result": "PASS", "assertions": assertions}


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser()
    sub = value.add_subparsers(dest="command", required=True)
    prepare_parser = sub.add_parser("prepare")
    prepare_parser.add_argument("--root", required=True)
    prepare_parser.add_argument("--attempt-tsv", required=True)
    prepare_parser.add_argument("--base-plan-contract", required=True)
    prepare_parser.add_argument("--prepare-manifest")
    finalize_parser = sub.add_parser("finalize")
    finalize_parser.add_argument("--root", required=True)
    finalize_parser.add_argument("--attempt-tsv", required=True)
    finalize_parser.add_argument("--base-plan-contract", required=True)
    finalize_parser.add_argument("--effective-plan-tsv", required=True)
    finalize_parser.add_argument("--a4-effective-detail", required=True)
    finalize_parser.add_argument("--success-tsv", required=True)
    finalize_parser.add_argument("--detail-output", required=True)
    finalize_parser.add_argument("--json-output", required=True)
    finalize_parser.add_argument("--markdown-output", required=True)
    finalize_parser.add_argument("--evidence-output", required=True)
    finalize_parser.add_argument("--captured-utc")
    finalize_parser.add_argument("--attempt-advertised", default="Data/Exports/P2-20/p2-20a-asset-binding-recovery-eligible-attempts.tsv")
    finalize_parser.add_argument("--effective-plan-advertised", default="Data/Exports/P2-20/p2-20a-qtx-declared-mip-payload-prefix-effective-recovery-plan.tsv")
    finalize_parser.add_argument("--success-advertised", default="Data/Exports/P2-20/p2-20a-asset-binding-recovery-successes.tsv")
    finalize_parser.add_argument("--detail-advertised", default="Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl")
    finalize_parser.add_argument("--json-advertised", default="Data/Reports/p2-20a-asset-binding-recovery-report.json")
    finalize_parser.add_argument("--markdown-advertised", default="Data/Reports/p2-20a-asset-binding-recovery-report.md")
    value.add_argument("--self-test", action="store_true")
    return value


def main() -> None:
    import sys
    if "--self-test" in sys.argv:
        print(json.dumps(self_test(), sort_keys=True))
        return
    args = parser().parse_args()
    result = prepare(args) if args.command == "prepare" else finalize(args)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
