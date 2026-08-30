"""Closed-input helpers for the P2-20A.13 QTX declared-mip prefix proof."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


A7_ROOT_FIELDS = {"asset_id", "family", "candidate_count", "candidate_set_sha256",
    "prior_resolution", "effective_resolution", "candidate_selected", "automatic_resolution",
    "authority_status", "candidates"}
A7_CANDIDATE_FIELDS = {"automatic_resolution", "bind_result", "body_sha256", "candidate_id",
    "error_code", "error_context_sha256", "error_schema", "failure_id", "read_error_code",
    "descriptor_semantic_sha256"}
A8_ROOT_FIELDS = {"asset_id", "family", "attempted_edges", "successful_edges",
    "effective_resolution", "candidates"}
A8_CANDIDATE_FIELDS = {"candidate_id", "body_sha256", "descriptor_semantic_sha256", "attempted",
    "recovery_kind", "strict_error_code", "effective_binding", "recovery_applied",
    "effective_semantic_sha256", "qtx_recovery_contract"}
DETAIL_FIELDS = {"asset_id", "family", "candidate_count", "candidate_set_sha256", "recovery_kind",
    "basis", "source_strict_resolution", "a13_resolution_change", "candidate_selected",
    "automatic_resolution", "authority_state_changed", "candidate"}
DETAIL_CANDIDATE_FIELDS = {"candidate_id", "package_sha256", "body_sha256",
    "descriptor_semantic_sha256", "strict_semantic_sha256", "prefix_semantic_sha256",
    "input_payload_sha256", "consumed_payload_sha256", "ignored_tail_sha256",
    "decoded_mip_zero_sha256", "dds_sha256", "dds_payload_sha256", "strict_binding",
    "strict_error_code", "strict_prefix_binding", "explicit_prefix_binding", "format", "width",
    "height", "stored_mip_count", "declared_mip_count", "effective_mip_count",
    "payload_boundary_mip_count", "maximum_natural_mip_count", "input_payload_bytes",
    "consumed_payload_bytes", "ignored_payload_bytes", "decoded_mip_zero_bytes",
    "dds_header_bytes", "dds_payload_bytes", "dds_bytes", "dds_declared_mip_count",
    "dds_payload_prefix_only", "ignored_tail_excluded_from_dds", "payload_extent_basis",
    "recovery_applied", "adapter_applied", "content_disposition"}
BASE_PLAN_CONTRACT = (
    "Contracts/data-schema/g2-asset-binding-recovery-base-plan-v1.tsv")
UPSTREAM_INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_inventory", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a7_report", "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json", True),
    ("a7_inventory", "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json", True),
    ("a7_detail", "Data/Exports/P2-20/p2-20a-asset-binding-failure-diagnostics.jsonl", False),
    ("a8_report", "Data/Reports/p2-20a-asset-binding-recovery-report.json", True),
    ("a8_inventory", "Data/Inventory/p2-20a-asset-binding-recovery.json", True),
    ("a8_detail", "Data/Exports/P2-20/p2-20a-asset-binding-recovery.jsonl", False),
    ("core_report", "Data/Reports/p2-20a-core-resource-closure-report.json", True),
    ("core_inventory", "Data/Inventory/p2-20a-core-resource-closure.json", True),
    ("core_detail", "Data/Exports/P2-20/p2-20a-core-resource-closure.jsonl", False),
]
PREPARE_INPUTS = [
    ("base_plan_contract", BASE_PLAN_CONTRACT, True),
    ("p2_03_inventory", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False),
    ("p2_12_inventory", "Data/Inventory/p2-12-full-asset-inventory.json", True),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("policy", "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-policy-v1.json", True),
]
CONTRACT_INPUTS = [
    ("schema", "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-v1.schema.json", True),
    ("detail_schema", "Contracts/data-schema/g2-qtx-declared-mip-payload-prefix-detail-v1.schema.json", True),
]
INPUTS = UPSTREAM_INPUTS + PREPARE_INPUTS + CONTRACT_INPUTS
FROZEN_CONTRACT_SHA256 = {
    "base_plan_contract": "4f256efc82fadda9528d502ed77dce890c8cf914e827f089422fc5c38d10fb99",
    "policy": "67e2cb3f2ebf6843177df09fb086249f1c3ab4d6f81a8fa31b5af27b456123f5",
    "schema": "56c7dc13c9af0feaf38384e344d5107fad4f15b3ca841ec07b8a01d9c852cb46",
    "detail_schema": "911196c1f6e03cc7bf33ea84a954b404d8b7cc7a7b2533c7ebad435cab7db63f",
}
BLOCKER_FIELDS = {"identity_semantic_ambiguous_targets", "identity_semantic_ambiguous_edges",
    "asset_effective_ambiguous_targets", "asset_effective_ambiguous_edges",
    "strict_binding_failure_targets", "strict_binding_failure_edges",
    "asset_effective_unresolved_targets", "asset_effective_unresolved_edges",
    "auxiliary_nonterminal_instances", "conditional_required_missing", "migration_pending",
    "g2_satisfied", "g2_blocked"}


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
    with path.open("r", encoding="utf-8-sig") as stream:
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
    return {"role": role, "path": relative, "tracked": tracked, "bytes": path.stat().st_size,
            "lines": line_count(path), "sha256": sha256_file(path)}


def binding_set(entries: list[dict[str, Any]]) -> dict[str, Any]:
    canonical = "".join(f"{x['role']}\t{x['path']}\t{str(x['tracked']).lower()}\t"
                        f"{x['bytes']}\t{x['lines']}\t{x['sha256']}\n" for x in entries)
    return {"aggregate_sha256": sha256_text(canonical), "entries": entries}


def output_binding(path: Path, advertised: str, tracked: bool) -> dict[str, Any]:
    return {"path": advertised, "tracked": tracked, "bytes": path.stat().st_size,
            "lines": line_count(path), "sha256": sha256_file(path)}


def find_target(items: Iterable[dict[str, Any]], asset_id: str) -> dict[str, Any]:
    matches = [item for item in items if item.get("asset_id") == asset_id]
    require(len(matches) == 1, "Frozen target coverage is not exact")
    return matches[0]


def verify_inventory(root: Path, inventory: dict[str, Any], report_role: str,
                     detail_role: str, report_key: str = "report_json") -> None:
    report_relative = next(p for r, p, _ in INPUTS if r == report_role)
    detail_relative = next(p for r, p, _ in INPUTS if r == detail_role)
    outputs = inventory.get("outputs", {})
    report = outputs.get(report_key, inventory.get("report"))
    detail = outputs.get("detail_export", inventory.get("closure", {}).get("detail_export"))
    require(report == output_binding(repo_path(root, report_relative), report_relative,
                                     bool(report["tracked"])), "Inventory report binding drifted")
    require(detail == output_binding(repo_path(root, detail_relative), detail_relative, False),
            "Inventory detail binding drifted")


def plan_rows(path: Path) -> list[list[str]]:
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8-sig").splitlines()]
    require(len(rows) == 21 and all(len(row) == 7 for row in rows),
            "A.8 eligible recovery plan shape drifted")
    require(all(all(len(row[index]) == 64 and
                    set(row[index]) <= set("0123456789abcdef") for index in range(4))
                for row in rows), "A.8 plan identity or hash field drifted")
    require(rows == sorted(rows, key=lambda row: (row[0], row[1])) and
            len({(row[0], row[1]) for row in rows}) == 21,
            "A.8 plan ordering or edge identity drifted")
    require(sum(row[4:] == ["qtx", "qtx_complete_mip_chain", "payload_size_mismatch"]
                for row in rows) == 16 and
            sum(row[4:] == ["anim", "anim_payload_frame_counts", "frame_count_mismatch"]
                for row in rows) == 5, "A.8 plan recovery-rule distribution drifted")
    return rows


def validate_source_inventories(paths: dict[str, Path]) -> None:
    p203 = load_json(paths["p2_03_inventory"])["graph"]
    require(p203["local_path"] == next(p for r, p, _ in PREPARE_INPUTS if r == "p2_03_graph") and
            p203["git_tracked"] is False and p203["lines"] == line_count(paths["p2_03_graph"]) and
            p203["bytes"] == paths["p2_03_graph"].stat().st_size and
            p203["sha256"] == sha256_file(paths["p2_03_graph"]),
            "P2-03 graph inventory binding drifted")
    p212 = load_json(paths["p2_12_inventory"])["catalog"]
    require(p212["path"] == next(p for r, p, _ in PREPARE_INPUTS if r == "p2_12_catalog") and
            p212["tracked"] is False and p212["lines"] == line_count(paths["p2_12_catalog"]) and
            p212["bytes"] == paths["p2_12_catalog"].stat().st_size and
            p212["sha256"] == sha256_file(paths["p2_12_catalog"]),
            "P2-12 catalog inventory binding drifted")


def validate_prepare_context(root: Path) -> dict[str, Any]:
    paths = {role: repo_path(root, relative) for role, relative, _ in PREPARE_INPUTS}
    require(all(sha256_file(paths[role]) == FROZEN_CONTRACT_SHA256[role]
                for role in ("base_plan_contract", "policy")),
            "A.13 frozen base-plan contract or policy bytes drifted")
    policy = load_json(paths["policy"])
    require(policy["base_plan_contract"] == {
        "path": BASE_PLAN_CONTRACT, "tracked": True, "rows": 21, "bytes": 6504,
        "sha256": FROZEN_CONTRACT_SHA256["base_plan_contract"],
    }, "A.13 base-plan contract policy drifted")
    require(policy["scope"] == {"family": "qtx", "strict_error_code": "payload_size_mismatch",
        "targets": 6, "candidate_edges": 6, "unique_candidates": 6,
        "recovery_kind": "qtx_declared_mip_payload_prefix",
        "basis": "declared_mip_payload_prefix_contract"}, "A.13 policy scope drifted")
    selected = {str(item["asset_id"]): item for item in policy["selected_targets"]}
    excluded = {str(item["asset_id"]): item for item in policy["excluded_unresolved_targets"]}
    selected_edges = {(str(item["asset_id"]), str(item["candidate_id"]))
                      for item in policy["selected_targets"]}
    excluded_edges = {(str(item["asset_id"]), str(candidate_id))
                      for item in policy["excluded_unresolved_targets"]
                      for candidate_id in item["candidate_ids"]}
    require(len(policy["selected_targets"]) == len(selected) == len(selected_edges) == 6 and
            len(policy["excluded_unresolved_targets"]) == len(excluded) == 4 and
            len(excluded_edges) == 6 and not set(selected) & set(excluded) and
            not selected_edges & excluded_edges,
            "A.13 selected/excluded target partition drifted")
    base = plan_rows(paths["base_plan_contract"])
    by_edge = {(row[0], row[1]): row for row in base}
    for item in selected.values():
        key = (str(item["asset_id"]), str(item["candidate_id"]))
        require(key in by_edge and by_edge[key] == [key[0], key[1], str(item["body_sha256"]),
                str(item["source_sha256"]), "qtx", "qtx_complete_mip_chain",
                "payload_size_mismatch"], "A.13 selected base-plan edge drifted")
    require(all(edge in by_edge and by_edge[edge][4:] ==
                ["qtx", "qtx_complete_mip_chain", "payload_size_mismatch"]
                for edge in excluded_edges), "A.13 excluded base-plan edge drifted")

    validate_source_inventories(paths)
    catalog_by_id: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(paths["p2_12_catalog"]):
        identity = stable_asset_id(str(item["path"]), str(item["sha256"]))
        if identity in selected:
            require(identity not in catalog_by_id, "P2-12 selected asset identity duplicated")
            catalog_by_id[identity] = item
    require(set(catalog_by_id) == set(selected) and all(
            item["family"] == "qtx" and item["structure"] == "UNRESOLVED" and
            item["sha256"] == selected[identity]["source_sha256"] and
            int(item["package_candidates"]) == 1
            for identity, item in catalog_by_id.items()),
            "P2-12 selected source coverage or metadata drifted")

    candidate_ids = {str(item["candidate_id"]) for item in selected.values()}
    nodes: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(paths["p2_03_graph"]):
        identity = str(item.get("id"))
        if item.get("record") == "node" and identity in candidate_ids:
            require(identity not in nodes, "P2-03 selected candidate identity duplicated")
            nodes[identity] = item
    require(set(nodes) == candidate_ids and all(item["class"] == "QTexture" and
            isinstance(item["package"], str) and item["package"] and
            isinstance(item["body_offset"], int) and item["body_offset"] >= 0 and
            isinstance(item["body_size"], int) and item["body_size"] > 0
            for item in nodes.values()), "P2-03 selected candidate coverage or metadata drifted")
    return {"policy": policy, "paths": paths, "selected": selected, "excluded": excluded,
            "selected_edges": selected_edges, "excluded_edges": excluded_edges,
            "catalog_by_id": catalog_by_id, "nodes": nodes, "base_plan": base}


def validate_final_context(root: Path) -> dict[str, Any]:
    context = validate_prepare_context(root)
    paths = {role: repo_path(root, relative) for role, relative, _ in INPUTS}
    require(all(sha256_file(paths[role]) == digest
                for role, digest in FROZEN_CONTRACT_SHA256.items()),
            "A.13 frozen policy or schema bytes drifted")
    selected, excluded = context["selected"], context["excluded"]

    reports = {role: load_json(paths[role]) for role in
               ("a4_report", "a7_report", "a8_report", "core_report")}
    inventories = {role: load_json(paths[role]) for role in
                   ("a4_inventory", "a7_inventory", "a8_inventory", "core_inventory")}
    require(reports["a4_report"]["evidence_revision"] == "P2-20A.4" and
            reports["a7_report"]["evidence_revision"] == "P2-20A.7" and
            reports["a8_report"]["evidence_revision"] == "P2-20A.8" and
            reports["core_report"]["evidence_revision"] == "P2-20A.3",
            "Upstream evidence revision drifted")
    require(all(report["result"] == "BLOCKED" for report in reports.values()),
            "Upstream blocked state drifted")
    verify_inventory(root, inventories["a4_inventory"], "a4_report", "a4_detail")
    verify_inventory(root, inventories["a7_inventory"], "a7_report", "a7_detail")
    verify_inventory(root, inventories["a8_inventory"], "a8_report", "a8_detail")
    verify_inventory(root, inventories["core_inventory"], "core_report", "core_detail")

    blockers = reports["a7_report"]["preserved_blockers"]
    require(set(blockers) == BLOCKER_FIELDS and all(isinstance(v, int) and v >= 0
            for v in blockers.values()), "Dynamic preserved blockers drifted")
    closure = reports["core_report"]["closure"]
    asset = closure["asset_binding"]
    require((blockers["asset_effective_ambiguous_targets"],
             blockers["asset_effective_ambiguous_edges"],
             blockers["asset_effective_unresolved_targets"],
             blockers["asset_effective_unresolved_edges"],
             blockers["conditional_required_missing"],
             blockers["auxiliary_nonterminal_instances"]) ==
            (asset["ambiguous_targets"], asset["ambiguous_edges"], asset["unresolved_targets"],
             asset["unresolved_edges"], closure["conditional_required"]["conditional_required_missing"],
             reports["core_report"]["scope_definition"]["auxiliary_config"]["inventory_files"]),
            "A.7 blockers differ from final Core closure")

    a7_all = list(iter_jsonl(paths["a7_detail"]))
    qtx_strict = [x for x in a7_all if x.get("family") == "qtx" and
                  x.get("prior_resolution") == "UNRESOLVED"]
    strict_by_id = {str(x["asset_id"]): x for x in qtx_strict}
    scoped_ids = set(selected) | set(excluded)
    require(len(qtx_strict) == 12 and sum(int(x["candidate_count"]) for x in qtx_strict) == 16 and
            scoped_ids <= set(strict_by_id) and
            sum(int(strict_by_id[x]["candidate_count"]) for x in scoped_ids) == 12,
            "A.7 strict-unresolved QTX workset drifted")
    a8_all = list(iter_jsonl(paths["a8_detail"]))
    a4_all = list(iter_jsonl(paths["a4_detail"]))
    catalog_by_id = context["catalog_by_id"]
    frozen: dict[str, dict[str, Any]] = {}
    for asset_id, expected in selected.items():
        a7 = find_target(a7_all, asset_id)
        require(set(a7) == A7_ROOT_FIELDS and a7["candidate_count"] == 1 and
                a7["candidate_selected"] is False and a7["automatic_resolution"] is False and
                a7["prior_resolution"] == "UNRESOLVED" and
                a7["effective_resolution"] == "RESOLVED",
                "A.7 selected target state drifted")
        candidate = a7["candidates"][0]
        require(set(candidate) == A7_CANDIDATE_FIELDS and candidate["candidate_id"] == expected["candidate_id"] and
                candidate["body_sha256"] == expected["body_sha256"] and
                candidate["descriptor_semantic_sha256"] == expected["descriptor_semantic_sha256"] and
                candidate["bind_result"] == "REJECTED" and
                candidate["error_code"] == "payload_size_mismatch", "A.7 selected edge drifted")
        require(candidate_set_sha256([candidate["candidate_id"]]) == a7["candidate_set_sha256"],
                "A.7 candidate set hash drifted")
        a8 = find_target(a8_all, asset_id)
        a8_candidate = a8["candidates"][0]
        require(set(a8) == A8_ROOT_FIELDS and a8["attempted_edges"] == 1 and
                len(a8["candidates"]) == 1 and set(a8_candidate) == A8_CANDIDATE_FIELDS and
                a8_candidate["candidate_id"] == candidate["candidate_id"] and
                a8["successful_edges"] == 1 and a8["effective_resolution"] == "RESOLVED" and
                a8_candidate["effective_binding"] == "PASS" and
                a8_candidate["recovery_kind"] == "qtx_declared_mip_payload_prefix" and
                a8_candidate["recovery_applied"] is True,
                "A.8 selected edge shape drifted")
        a4 = find_target(a4_all, asset_id)
        require(a4["family"] == "qtx" and a4["candidate_selected"] is False and
                a4["resolution"] == "RESOLVED",
                "A.4 authority state drifted")
        require(asset_id in catalog_by_id and catalog_by_id[asset_id]["family"] == "qtx" and
                catalog_by_id[asset_id]["sha256"] == expected["source_sha256"],
                "P2-12 selected source binding drifted")
        frozen[asset_id] = {"a7": a7, "a4": a4, "catalog": catalog_by_id[asset_id]}
    for asset_id, expected in excluded.items():
        a7 = find_target(qtx_strict, asset_id)
        require([str(x["candidate_id"]) for x in a7["candidates"]] == expected["candidate_ids"],
                "A.13 excluded candidate set drifted")

    effective_unresolved = {str(x["asset_id"]) for x in qtx_strict
                            if x["effective_resolution"] == "UNRESOLVED"}
    require(effective_unresolved == set(excluded),
            "A.7 final effective QTX partition drifted")
    context.update({"paths": paths, "frozen": frozen, "reports": reports,
                    "blockers": blockers, "effective_phase": "POST_APPLICATION"})
    return context


def prepare_scope_and_plan(root: Path, asset_output: Path, candidate_output: Path,
                           effective_plan_output: Path) -> dict[str, Any]:
    context = validate_prepare_context(root)
    asset_rows: list[str] = []
    candidate_rows: list[str] = []
    for asset_id in sorted(context["selected"]):
        expected = context["selected"][asset_id]
        source = context["catalog_by_id"][asset_id]
        candidate_id = str(expected["candidate_id"])
        node = context["nodes"][candidate_id]
        asset_fields = [asset_id, str(source["path"]), str(source["sha256"]),
            str(source["bytes"]), "qtx", str(source["structure"]),
            candidate_set_sha256([candidate_id]), candidate_id]
        candidate_fields = [candidate_id, str(node["package"]), str(node["body_offset"]),
                            str(node["body_size"]), "QTexture"]
        require(all("\t" not in value and "\r" not in value and "\n" not in value
                    for value in asset_fields + candidate_fields),
                "Prepared A.13 probe TSV field is unsafe")
        asset_rows.append("\t".join(asset_fields))
        candidate_rows.append("\t".join(candidate_fields))
    effective = []
    changed = 0
    for row in context["base_plan"]:
        copy = list(row)
        if (copy[0], copy[1]) in context["selected_edges"]:
            copy[5] = "qtx_declared_mip_payload_prefix"
            changed += 1
        effective.append(copy)
    require(changed == 6 and all(a[:5] + a[6:] == b[:5] + b[6:]
            for a, b in zip(context["base_plan"], effective)), "Effective plan mutation escaped kind cell")
    write_text(asset_output, "\n".join(asset_rows) + "\n")
    write_text(candidate_output, "\n".join(candidate_rows) + "\n")
    write_text(effective_plan_output, "\n".join("\t".join(row) for row in effective) + "\n")
    return {"result": "PASS", "targets": 6, "candidate_edges": 6, "unique_candidates": 6,
            "excluded_targets": 4, "excluded_edges": 6, "effective_plan_rows": 21,
            "effective_plan_changed_rows": 6, "family": "qtx"}
