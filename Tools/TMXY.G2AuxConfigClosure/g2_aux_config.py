#!/usr/bin/env python3
"""Generate deterministic P2-20A.3 auxiliary-config reference evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

from aux_common import (
    EvidenceError,
    canonical_identity_text,
    canonical_json_line,
    domain_hash,
    string_set_sha256,
)
from aux_extract import extract_repository, run_self_test as run_extractor_self_test
from aux_report import build_governance, build_report, render_markdown, sha256_file


INPUT_PATHS = {
    "auxiliary_config_inventory": "Data/Inventory/p2-05-auxiliary-config-inventory.json",
    "full_asset_inventory": "Data/Inventory/p2-12-full-asset-inventory.json",
    "reference_closure": "Data/Inventory/p2-13-reference-closure.json",
    "asset_health": "Data/Inventory/p2-14-asset-health.json",
    "conversion_routing": "Data/Inventory/p2-15-conversion-routing.json",
    "content_health": "Data/Inventory/p2-18-content-health.json",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def resolve_inside(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve(strict=True)
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise EvidenceError("input path escaped the repository") from error
    return candidate


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError("required evidence is not readable JSON") from error
    require(isinstance(value, dict), "required evidence is not a JSON object")
    return value


def bind_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    roles = list(policy["required_input_roles"])
    require(roles == list(INPUT_PATHS), "input role order differs from the closed contract")
    entries: list[dict[str, str]] = []
    documents: dict[str, Any] = {}
    aggregate = hashlib.sha256()
    for role in roles:
        path = resolve_inside(root, INPUT_PATHS[role])
        document = load_json(path)
        require(document.get("completion_criteria_satisfied") is True,
                "a required prerequisite is not complete")
        digest = sha256_file(path)
        entries.append({"role": role, "sha256": digest})
        documents[role] = document
        aggregate.update(f"{role}\t{digest}\n".encode("ascii"))
    return {"aggregate_sha256": aggregate.hexdigest(), "entries": entries}, documents


def _file_instance_records(
    inventory: dict[str, Any], extractor_records: Iterable[dict[str, Any]]
) -> list[dict[str, Any]]:
    scopes = {
        str(item["source_file_id"]): item
        for item in extractor_records
        if item.get("record") == "auxiliary_config_file_scope"
    }
    occurrences: dict[str, list[dict[str, Any]]] = {}
    for item in extractor_records:
        if item.get("record") == "auxiliary_config_reference_candidate":
            occurrences.setdefault(str(item["source_file_id"]), []).append(item)

    result: list[dict[str, Any]] = []
    for entry in inventory["files"]:
        instance_id = domain_hash(
            "g2-aux-source-file-v1",
            canonical_identity_text(str(entry["path"])),
            str(entry["sha256"]),
        )
        require(instance_id in scopes, "extractor omitted a file instance")
        scope = scopes[instance_id]
        members = sorted(occurrences.get(instance_id, []), key=lambda item: str(item["member_id"]))
        target_counts = {"asset": 0, "package": 0, "config": 0}
        candidate_edges = 0
        for member in members:
            target = str(member["target_kind"])
            require(target in target_counts, "extractor emitted an unknown candidate kind")
            target_counts[target] += 1
            candidate_edges += int(member["candidate_count"])
        raw_state = str(scope["adapter_status"])
        state = {
            "candidate-only": "candidate-only",
            "malformed-blocked": "malformed-blocked",
            "editor-undecided": "editor-undecided",
            "no-ref-unapproved": "editor-undecided",
        }.get(raw_state)
        require(state is not None, "extractor emitted an unauthorized adapter state")
        reason = {
            "candidate-only": "LEXICAL_CANDIDATES_NOT_SEMANTICALLY_APPROVED",
            "malformed-blocked": "MALFORMED_INPUT_REQUIRES_DISPOSITION",
            "editor-undecided": "NO_MATCH_DOES_NOT_PROVE_NO_REFERENCE",
        }[state]
        result.append({
            "instance_sha256": instance_id,
            "content_sha256": str(entry["sha256"]),
            "parser_state": "parsed" if bool(scope["parsed"]) else "malformed",
            "adapter_state": state,
            "lexical_counts": {
                "asset_exact": target_counts["asset"],
                "package_exact": target_counts["package"],
                "config_exact": target_counts["config"],
                "candidate_edges": candidate_edges,
            },
            "occurrence_set_sha256": (
                string_set_sha256(str(member["member_id"]) for member in members)
                if members else None
            ),
            "adapter_contract_sha256": None,
            "authority_record_sha256": None,
            "approved_root_count": 0,
            "approved_root_set_sha256": None,
            "reason_code": reason,
        })
    result.sort(key=lambda item: str(item["instance_sha256"]))
    require(len(result) == 212 and len({item["instance_sha256"] for item in result}) == 212,
            "file-instance set is not complete and unique")
    return result


def _flat_measured(summary: dict[str, Any], records: Iterable[dict[str, Any]]) -> dict[str, Any]:
    coverage = summary["coverage"]
    scalars = summary["scalars"]
    candidates = summary["candidates"]
    binding = summary["input_binding"]
    occurrence_ids = [
        str(item["member_id"])
        for item in records
        if item.get("record") == "auxiliary_config_reference_candidate"
    ]
    return {
        "measurement_authority": "LEXICAL_ONLY",
        "file_instances": int(coverage["source_files"]),
        "unique_content_bodies": int(coverage["source_unique_blobs"]),
        "parsed_file_instances": int(coverage["parseable_files"]),
        "malformed_file_instances": int(coverage["malformed_files"]),
        "scalar_positions": int(scalars["locations"]),
        "nonempty_scalar_positions": int(scalars["nonempty"]),
        "asset_exact_occurrences": int(candidates["asset_identity_occurrences"]),
        "package_exact_occurrences": int(candidates["package_identity_occurrences"]),
        "package_unique_occurrences": int(candidates["package_unique_occurrences"]),
        "package_ambiguous_occurrences": int(candidates["package_ambiguous_occurrences"]),
        "package_ambiguous_candidate_edges": int(candidates["package_candidate_edges"]),
        "config_exact_edges": int(candidates["config_identity_occurrences"]),
        "file_instance_set_sha256": str(binding["source_file_instance_set_sha256"]),
        "lexical_occurrence_set_sha256": string_set_sha256(occurrence_ids),
    }


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")


def build(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve(strict=True)
    policy_path = args.policy.resolve(strict=True)
    schema_path = args.schema.resolve(strict=True)
    policy = load_json(policy_path)
    require(policy.get("evidence_revision") == "P2-20A.3", "wrong policy revision")
    bindings, documents = bind_inputs(root, policy)
    extraction = extract_repository(root, enforce_expected_baseline=True)
    records = list(extraction.records)
    measured = _flat_measured(dict(extraction.summary), records)
    expected = policy["measured_lexical_candidates"]
    for name, value in expected.items():
        require(measured.get(name) == value, "measured lexical baseline differs from policy")
    file_instances = _file_instance_records(documents["auxiliary_config_inventory"], records)
    report_extraction = {"measured": measured, "file_instances": file_instances}
    report = build_report(
        policy, policy_path, schema_path, bindings, report_extraction,
        str(documents["content_health"]["captured_utc"]),
    )

    args.detail_output.parent.mkdir(parents=True, exist_ok=True)
    with args.detail_output.open("wb") as stream:
        detail_count, _, detail_sha = extraction.write_detail_jsonl(stream)
    report_text = json.dumps(report, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    write_text(args.json_output, report_text)
    write_text(args.markdown_output, render_markdown(report))
    governance = build_governance(report, sha256_file(args.json_output), detail_count, detail_sha)
    write_text(args.governance_output,
               json.dumps(governance, ensure_ascii=True, allow_nan=False, indent=2) + "\n")
    return {
        "result": "BLOCKED",
        "review_execution_result": "PASS",
        "task_status": "BLOCKED",
        "completion_criteria_satisfied": False,
        "scope_complete": False,
        "file_instances": len(file_instances),
        "detail_records": detail_count,
        "detail_sha256": detail_sha,
        "nonempty_scalar_positions": measured["nonempty_scalar_positions"],
    }


def self_test(root: Path) -> dict[str, Any]:
    extractor = run_extractor_self_test(root)
    require(extractor["result"] == "PASS", "extractor self-test failed")
    require(extractor["source_files"] == 212, "self-test file coverage failed")
    require(extractor["resource_identity_occurrences"] == 3681,
            "self-test resource population failed")
    require(extractor["config_identity_occurrences"] == 8,
            "self-test config population failed")
    return {"result": "PASS", "assertions": int(extractor["assertions"]) + 4}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--detail-output", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--governance-output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    require(args.root is not None, "repository root is required")
    if args.self_test:
        print(json.dumps(self_test(args.root.resolve(strict=True)), sort_keys=True,
                         separators=(",", ":")))
        return
    require(all((args.policy, args.schema, args.detail_output, args.json_output,
                 args.markdown_output, args.governance_output)),
            "generation arguments are required")
    print(json.dumps(build(args), sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
