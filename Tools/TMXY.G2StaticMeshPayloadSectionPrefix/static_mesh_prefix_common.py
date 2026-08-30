"""Shared closed-input helpers for the P2-20A.12 static-mesh prefix proof."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


SHA256_PATTERN_LENGTH = 64
A7_ROOT_FIELDS = {
    "asset_id", "family", "candidate_count", "candidate_set_sha256", "prior_resolution",
    "effective_resolution", "candidate_selected", "automatic_resolution",
    "authority_status", "candidates",
}
A7_CANDIDATE_FIELDS = {
    "automatic_resolution", "bind_result", "body_sha256", "candidate_id", "error_code",
    "error_context_sha256", "error_schema", "failure_id", "read_error_code",
    "descriptor_semantic_sha256",
}
A8_ROOT_FIELDS = {
    "asset_id", "family", "attempted_edges", "successful_edges", "effective_resolution",
    "candidates",
}
A8_CANDIDATE_FIELDS = {
    "candidate_id", "body_sha256", "descriptor_semantic_sha256", "attempted",
    "recovery_kind", "strict_error_code", "effective_binding", "recovery_applied",
    "effective_semantic_sha256", "qtx_recovery_contract",
}
DETAIL_FIELDS = {
    "asset_id", "family", "candidate_count", "candidate_set_sha256", "recovery_kind",
    "basis", "effective_resolution", "candidate_selected", "automatic_resolution",
    "authority_state_changed", "candidates",
}
DETAIL_CANDIDATE_FIELDS = {
    "candidate_id", "package_sha256", "body_sha256", "descriptor_semantic_sha256",
    "strict_semantic_sha256", "strict_binding", "strict_error_code", "prefix_binding",
    "prefix_semantic_sha256", "declared_material_slots", "payload_sections",
    "nonempty_payload_sections", "ignored_trailing_material_slots", "slot_basis",
    "recovery_applied", "adapter_applied", "content_disposition",
}
BLOCKER_FIELDS = {
    "identity_semantic_ambiguous_targets", "identity_semantic_ambiguous_edges",
    "asset_effective_ambiguous_targets", "asset_effective_ambiguous_edges",
    "strict_binding_failure_targets", "strict_binding_failure_edges",
    "asset_effective_unresolved_targets", "asset_effective_unresolved_edges",
    "auxiliary_nonterminal_instances", "conditional_required_missing", "migration_pending",
    "g2_satisfied", "g2_blocked",
}
INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_inventory", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a7_report", "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True),
    ("a7_inventory", "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
    ("a7_detail", "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False),
    ("a8_report", "Data/Reports/p2-20a-asset-binding-recovery-report.json", True),
    ("a8_inventory", "Data/Inventory/p2-20a-asset-binding-recovery.json", True),
    ("a8_detail", "Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl", False),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("policy", "Contracts/data-schema/g2-static-mesh-payload-section-prefix-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-static-mesh-payload-section-prefix-v1.schema.json", True),
    ("detail_schema", "Contracts/data-schema/g2-static-mesh-payload-section-prefix-detail-v1.schema.json", True),
]
FROZEN_CONTRACT_SHA256 = {
    "policy": "94fc2dd11fa9ecc67fde0c8289a5c378fc0ffa9e799f05edaa9feef42fa31c55",
    "schema": "c81da5e9f6e433287efe06cab998f96058a5acced85cd586e2dc7b91c7e64d9a",
    "detail_schema": "6b1f4651870eb599df86eff0d004deb9128b10e09bf2b859e7672a5065c062c8",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root is not an object: {path.name}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL record {number} is not an object")
            yield value


def repo_path(root: Path, relative: str) -> Path:
    require(relative and "\\" not in relative, "Repository path is not portable")
    part = Path(relative)
    require(not part.is_absolute() and ".." not in part.parts, "Repository path escaped root")
    path = (root / part).resolve()
    require(path.is_relative_to(root) and path.is_file(), f"Missing input: {relative}")
    return path


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.replace("\r\n", "\n").replace("\r", "\n"),
                    encoding="utf-8", newline="\n")


def stable_asset_id(relative_path: str, content_sha256: str) -> str:
    return sha256_text("asset\0" + relative_path + "\0" + content_sha256)


def candidate_set_sha256(values: Iterable[str]) -> str:
    return sha256_text("\n".join(sorted(values)) + "\n")


def binding(root: Path, role: str, relative: str, tracked: bool) -> dict[str, Any]:
    path = repo_path(root, relative)
    return {"role": role, "path": relative, "tracked": tracked,
            "bytes": path.stat().st_size, "lines": line_count(path), "sha256": sha256_file(path)}


def binding_set(entries: list[dict[str, Any]]) -> dict[str, Any]:
    canonical = "".join(
        f"{item['role']}\t{item['path']}\t{str(item['tracked']).lower()}\t"
        f"{item['bytes']}\t{item['lines']}\t{item['sha256']}\n" for item in entries)
    return {"aggregate_sha256": sha256_text(canonical), "entries": entries}


def output_binding(path: Path, advertised: str, tracked: bool) -> dict[str, Any]:
    return {"path": advertised, "tracked": tracked, "bytes": path.stat().st_size,
            "lines": line_count(path), "sha256": sha256_file(path)}


def verify_inventory_output(root: Path, inventory: dict[str, Any], key: str,
                            relative: str, tracked: bool) -> None:
    if key in inventory.get("outputs", {}):
        item = inventory["outputs"][key]
    elif key == "report_json" and "report" in inventory:
        item = inventory["report"]
    else:
        raise ValueError(f"Inventory output binding is absent: {key}")
    path = repo_path(root, relative)
    require(item == output_binding(path, relative, tracked),
            f"Inventory output binding drifted: {key}")


def find_target(items: Iterable[dict[str, Any]], asset_id: str) -> dict[str, Any]:
    matches = [item for item in items if item.get("asset_id") == asset_id]
    require(len(matches) == 1, "Frozen target coverage is not exact")
    return matches[0]


def validate_frozen(root: Path) -> dict[str, Any]:
    paths = {role: repo_path(root, relative) for role, relative, _ in INPUTS}
    require(all(sha256_file(paths[role]) == digest
                for role, digest in FROZEN_CONTRACT_SHA256.items()),
            "A.12 frozen policy or schema bytes drifted")
    policy = load_json(paths["policy"])
    require(policy["scope"] == {
        "family": "sm", "strict_error_code": "material_slot_mismatch", "targets": 1,
        "candidate_edges": 2, "recovery_kind": "sm_payload_section_prefix",
        "basis": "payload_section_prefix_contract"}, "A.12 policy scope drifted")

    a4_report, a4_inventory = load_json(paths["a4_report"]), load_json(paths["a4_inventory"])
    a7_report, a7_inventory = load_json(paths["a7_report"]), load_json(paths["a7_inventory"])
    a8_report, a8_inventory = load_json(paths["a8_report"]), load_json(paths["a8_inventory"])
    require(a4_report["evidence_revision"] == "P2-20A.4" and
            a7_report["evidence_revision"] == "P2-20A.7" and
            a8_report["evidence_revision"] == "P2-20A.8", "Upstream revision drifted")
    require(a4_report["result"] == a7_report["result"] == a8_report["result"] == "BLOCKED",
            "Upstream blocked state drifted")
    blockers = a7_report.get("preserved_blockers", {})
    require(set(blockers) == BLOCKER_FIELDS and
            all(isinstance(value, int) and value >= 0 for value in blockers.values()),
            "A.7 dynamic preserved blockers drifted")
    a4_measured = a4_report["measured"]
    a4_effective = a4_measured["reconciled_full_workset"]
    a7_effective = a7_report["measured"]["effective"]
    a8_measured = a8_report["measured"]
    a8_effective = a8_measured["effective_resolution"]
    require((blockers["asset_effective_ambiguous_targets"],
             blockers["asset_effective_ambiguous_edges"],
             blockers["asset_effective_unresolved_targets"],
             blockers["asset_effective_unresolved_edges"]) ==
            (a4_effective["ambiguous_targets"], a4_effective["ambiguous_edges"],
             a4_effective["unresolved_targets"], a4_effective["unresolved_edges"]),
            "A.4 full-workset blockers differ from A.7")
    require((a7_effective["unresolved_targets"], a7_effective["unresolved_edges"]) ==
            (a4_effective["unresolved_targets"], a4_effective["unresolved_edges"]) and
            a8_effective == {
                "resolved": {"targets": a7_effective["resolved_targets"],
                             "candidate_edges": a7_effective["resolved_edges"]},
                "ambiguous": {"targets": a7_effective["ambiguous_targets"],
                              "candidate_edges": a7_effective["ambiguous_edges"]},
                "unresolved": {"targets": a7_effective["unresolved_targets"],
                               "candidate_edges": a7_effective["unresolved_edges"]}},
            "A.4/A.7/A.8 effective states do not reconcile")
    strict = a4_measured["by_prior_resolution_basis"]["DESCRIPTOR_VALIDATION_FAILED"]
    require((blockers["strict_binding_failure_targets"],
             blockers["strict_binding_failure_edges"]) ==
            (a7_report["measured"]["diagnosed_targets"],
             a7_report["measured"]["diagnosed_candidate_edges"]) ==
            (strict["targets"], strict["candidate_edges"]) and
            (a7_effective["resolved_targets"], a7_effective["unresolved_targets"]) ==
            (strict["resolved"], strict["unresolved"]) and
            a4_measured["recovery_applied_candidates"] ==
            a8_measured["successful"]["candidate_edges"],
            "Strict failure and effective recovery counts do not reconcile")
    require(a4_report["detail_export"] == output_binding(
                paths["a4_detail"], "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False) and
            a7_report["detail_export"] == output_binding(
                paths["a7_detail"], "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False) and
            a8_report["outputs"]["detail_export"] == output_binding(
                paths["a8_detail"], "Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl", False),
            "Upstream report-to-detail binding drifted")
    for inventory, report_role, detail_role, report_tracked in (
            (a4_inventory, "a4_report", "a4_detail", True),
            (a7_inventory, "a7_report", "a7_detail", True),
            (a8_inventory, "a8_report", "a8_detail", False)):
        verify_inventory_output(root, inventory, "report_json", next(
            relative for role, relative, _ in INPUTS if role == report_role), report_tracked)
        verify_inventory_output(root, inventory, "detail_export", next(
            relative for role, relative, _ in INPUTS if role == detail_role), False)

    a7_sm = [item for item in iter_jsonl(paths["a7_detail"]) if item.get("family") == "sm"]
    require(len(a7_sm) == 1 and set(a7_sm[0]) == A7_ROOT_FIELDS, "A.7 SM root scope drifted")
    frozen = a7_sm[0]
    require(frozen["candidate_count"] == 2 and frozen["prior_resolution"] == "UNRESOLVED" and
            frozen["effective_resolution"] == "UNRESOLVED" and
            frozen["candidate_selected"] is False and frozen["automatic_resolution"] is False,
            "A.7 SM authority state drifted")
    require(all(set(candidate) == A7_CANDIDATE_FIELDS and
                candidate["bind_result"] == "REJECTED" and
                candidate["error_code"] == "material_slot_mismatch" and
                candidate["automatic_resolution"] is False
                for candidate in frozen["candidates"]), "A.7 SM candidate state drifted")
    ids = [str(candidate["candidate_id"]) for candidate in frozen["candidates"]]
    require(len(ids) == len(set(ids)) == 2 and
            candidate_set_sha256(ids) == frozen["candidate_set_sha256"],
            "A.7 SM candidate set drifted")

    a8 = find_target(iter_jsonl(paths["a8_detail"]), str(frozen["asset_id"]))
    a8_candidates = a8.get("candidates", [])
    require(set(a8) == A8_ROOT_FIELDS and a8["family"] == "sm" and
            a8["attempted_edges"] == 0 and a8["successful_edges"] == 0 and
            a8["effective_resolution"] == "UNRESOLVED" and
            isinstance(a8_candidates, list) and len(a8_candidates) == 2 and
            {str(candidate.get("candidate_id")) for candidate in a8_candidates} == set(ids) and
            all(set(candidate) == A8_CANDIDATE_FIELDS and
                 candidate["candidate_id"] in ids and candidate["attempted"] is False and
                 candidate["strict_error_code"] == "material_slot_mismatch" and
                 candidate["effective_binding"] == "REJECTED" and
                 candidate["recovery_applied"] is False for candidate in a8_candidates),
            "A.8 SM non-attempt state drifted")

    a4 = find_target(iter_jsonl(paths["a4_detail"]), str(frozen["asset_id"]))
    require(a4["family"] == "sm" and a4["candidate_selected"] is False and
            a4["strict_resolution"] == "UNRESOLVED" and a4["resolution"] == "UNRESOLVED",
            "A.4 SM authority state drifted")
    a4_candidates = {str(item["candidate_id"]): item for item in a4["candidates"]}
    require(set(a4_candidates) == set(ids) and all(
        a4_candidates[identity]["binding"] == "REJECTED" and
        a4_candidates[identity]["recovery_applied"] is False
        for identity in ids), "A.4 SM candidate set drifted")

    catalog_matches = []
    for item in iter_jsonl(paths["p2_12_catalog"]):
        if stable_asset_id(str(item["path"]), str(item["sha256"])) == frozen["asset_id"]:
            catalog_matches.append(item)
    require(len(catalog_matches) == 1 and catalog_matches[0]["family"] == "sm",
            "P2-12 frozen SM asset coverage drifted")
    return {"policy": policy, "frozen": frozen, "a4": a4, "blockers": blockers,
            "a4_candidates": a4_candidates, "catalog": catalog_matches[0], "paths": paths}


def prepare_from_a7(root: Path, asset_input: Path, candidate_input: Path,
                    asset_output: Path, candidate_output: Path) -> dict[str, Any]:
    context = validate_frozen(root)
    asset_rows = [line.rstrip("\n") for line in asset_input.read_text(encoding="utf-8").splitlines()
                  if line.split("\t")[4] == "sm"]
    require(len(asset_rows) == 1, "Prepared A.7 SM asset scope drifted")
    fields = asset_rows[0].split("\t")
    require(len(fields) == 8 and fields[0] == context["frozen"]["asset_id"] and
            fields[2] == context["catalog"]["sha256"] and
            int(fields[3]) == int(context["catalog"]["bytes"]) and
            fields[6] == context["frozen"]["candidate_set_sha256"],
            "Prepared A.7 SM asset binding drifted")
    ids = set(fields[7].split(","))
    rows = [line for line in candidate_input.read_text(encoding="utf-8").splitlines()
            if line.split("\t")[0] in ids]
    require(len(rows) == 2 and {line.split("\t")[0] for line in rows} == ids and
            all(len(line.split("\t")) == 5 and line.split("\t")[4] == "QStaticMesh"
                for line in rows), "Prepared A.7 SM candidates drifted")
    write_text(asset_output, asset_rows[0] + "\n")
    write_text(candidate_output, "\n".join(sorted(rows)) + "\n")
    return {"result": "PASS", "targets": 1, "candidate_edges": 2,
            "unique_candidates": 2, "family": "sm"}
