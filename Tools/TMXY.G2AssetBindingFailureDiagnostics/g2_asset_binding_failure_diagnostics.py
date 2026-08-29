"""Deterministic P2-20A.7 production-binding failure diagnostics."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


A4_ROOT_FIELDS = {
    "asset_id", "candidate_count", "candidate_identity_exact", "candidate_selected",
    "candidate_set_sha256", "candidates", "compatible_semantic_variants", "counts",
    "family", "heuristic_selection", "prior_resolution", "prior_resolution_basis",
    "production_binder_used", "resolution", "resolution_basis", "strict_resolution",
    "strict_resolution_basis", "strict_compatible_semantic_variants", "structure",
}
A4_CANDIDATE_FIELDS = {
    "binding", "body_sha256", "candidate_id", "descriptor", "descriptor_semantic_sha256",
    "effective_binding", "effective_semantic_sha256", "recovery_applied", "recovery_kind",
    "identity_mirror_ascii_lower_match", "identity_normalized_descriptor_semantic_sha256",
    "identity_normalized_semantic_sha256", "semantic_sha256",
}
PROBE_FIELDS = {"asset_id", "candidate_count", "candidate_set_sha256", "candidates", "family"}
PROBE_CANDIDATE_FIELDS = {
    "automatic_resolution", "bind_result", "body_sha256", "candidate_id", "error_code",
    "error_context_sha256", "error_schema", "failure_id", "read_error_code",
}
DETAIL_FIELDS = {
    "asset_id", "family", "candidate_count", "candidate_set_sha256", "prior_resolution",
    "effective_resolution", "candidate_selected", "automatic_resolution",
    "authority_status", "candidates",
}
DETAIL_CANDIDATE_FIELDS = PROBE_CANDIDATE_FIELDS | {"descriptor_semantic_sha256"}
FAMILY_SCHEMA = {
    "anim": "AnimationError/v1", "qtx": "TextureError/v1", "sm": "StaticMeshError/v1",
}
INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a4_evidence", "Data/Inventory/p2-20a-asset-descriptor-diagnostics.json", True),
    ("a4_policy", "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json", True),
    ("p2_03_evidence", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False),
    ("p2_12_evidence", "Data/Inventory/p2-12-full-asset-inventory.json", True),
    ("p2_12_catalog", "Data/Exports/P2-12/p2-12-full-asset-inventory.jsonl", False),
    ("a5_report", "Data/Reports/p2-20a-aux-semantic-diagnostics-report.json", True),
    ("a6_report", "Data/Reports/p2-20a-asset-identity-normalization-report.json", True),
    ("policy", "Contracts/data-schema/g2-asset-binding-failure-diagnostics-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-asset-binding-failure-diagnostics-v1.schema.json", True),
    ("detail_schema", "Contracts/data-schema/g2-asset-binding-failure-detail-v1.schema.json", True),
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


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


def failure_id(asset_id: str, candidate_id: str, schema: str, code: str,
               read_code: str | None, context_sha: str) -> str:
    values = (asset_id, candidate_id, schema, code, read_code or "none", context_sha)
    payload = bytearray(b"tmxy-g2-asset-binding-failure-v1")
    for value in values:
        payload.append(0)
        payload.extend(value.encode("ascii"))
    return hashlib.sha256(payload).hexdigest()


def binding(root: Path, role: str, relative: str, tracked: bool) -> dict[str, Any]:
    path = repo_path(root, relative)
    return {"role": role, "path": relative, "tracked": tracked,
            "bytes": path.stat().st_size, "lines": line_count(path), "sha256": sha256_file(path)}


def output_binding(path: Path, advertised: str, tracked: bool) -> dict[str, Any]:
    return {"path": advertised, "tracked": tracked, "bytes": path.stat().st_size,
            "lines": line_count(path), "sha256": sha256_file(path)}


def validate_bound_export(root: Path, report: dict[str, Any], field: str,
                          relative: str, lines: int) -> Path:
    item = report[field]
    require(item.get("path", item.get("local_path")) == relative and item["lines"] == lines,
            f"{field} path or count drifted")
    path = repo_path(root, relative)
    require(item["sha256"] == sha256_file(path), f"{field} hash drifted")
    return path


def validate_context(root: Path, paths: dict[str, Path], policy: dict[str, Any]) -> None:
    require(policy["evidence_revision"] == "P2-20A.7" and
            policy["scope"]["targets"] == 19 and policy["scope"]["candidate_edges"] == 24,
            "A.7 policy identity or scope drifted")
    a4 = load_json(paths["a4_report"])
    require(a4["evidence_revision"] == "P2-20A.4" and a4["result"] == "BLOCKED" and
            a4["review_execution_result"] == "PASS" and
            a4["measured"]["strict_unresolved_targets"] == 19 and
            a4["measured"]["strict_unresolved_edges"] == 24 and
            a4["measured"]["ambiguous_targets"] == 189 and
            a4["measured"]["reconciled_full_workset"]["ambiguous_edges"] == 546 and
            a4["measured"]["unresolved_targets"] == 12 and
            a4["measured"]["reconciled_full_workset"]["unresolved_edges"] == 15 and
            a4["g2_06_satisfied"] is False and a4["p3_authorized"] is False,
            "A.4 unresolved state drifted")
    advertised = a4["detail_export"]
    require(advertised["path"] == INPUTS[1][1] and advertised["lines"] == 3651 and
            advertised["sha256"] == sha256_file(paths["a4_detail"]), "A.4 detail binding drifted")
    evidence = load_json(paths["a4_evidence"])
    require(evidence["outputs"]["report_json"]["sha256"] == sha256_file(paths["a4_report"]) and
            evidence["outputs"]["detail_export"]["sha256"] == sha256_file(paths["a4_detail"]),
            "A.4 evidence output binding drifted")
    p203 = load_json(paths["p2_03_evidence"])
    validate_bound_export(root, p203, "graph", INPUTS[5][1], 269064)
    p212 = load_json(paths["p2_12_evidence"])
    validate_bound_export(root, p212, "catalog", INPUTS[7][1], 40090)
    a5 = load_json(paths["a5_report"])
    a6 = load_json(paths["a6_report"])
    preserved = policy["preserved_blockers"]
    require(a5["semantic_state"]["nonterminal_instances"] ==
            preserved["auxiliary_nonterminal_instances"], "A.5 blocker drifted")
    require(a6["measured"]["effective"]["ambiguous_targets"] ==
            preserved["identity_semantic_ambiguous_targets"] and
            a6["measured"]["effective"]["ambiguous_edges"] ==
            preserved["identity_semantic_ambiguous_edges"], "A.6 blocker drifted")
    require(a4["measured"]["ambiguous_targets"] ==
            preserved["asset_effective_ambiguous_targets"] and
            a4["measured"]["reconciled_full_workset"]["ambiguous_edges"] ==
            preserved["asset_effective_ambiguous_edges"] and
            a4["measured"]["strict_unresolved_targets"] ==
            preserved["strict_binding_failure_targets"] and
            a4["measured"]["strict_unresolved_edges"] ==
            preserved["strict_binding_failure_edges"] and
            a4["measured"]["unresolved_targets"] ==
            preserved["asset_effective_unresolved_targets"] and
            a4["measured"]["reconciled_full_workset"]["unresolved_edges"] ==
            preserved["asset_effective_unresolved_edges"], "A.4 blocker drifted")


def load_unresolved(path: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    total = 0
    for item in iter_jsonl(path):
        total += 1
        require(set(item) == A4_ROOT_FIELDS, "A.4 detail record is not closed")
        if item["strict_resolution"] != "UNRESOLVED":
            continue
        require(item["strict_resolution_basis"] == "NO_PRODUCTION_COMPATIBLE_CANDIDATE" and
                item["candidate_identity_exact"] is True and
                item["candidate_selected"] is False and item["heuristic_selection"] is False and
                item["production_binder_used"] is True, "A.4 unresolved controls drifted")
        candidates = item["candidates"]
        require(len(candidates) == item["candidate_count"] and
                all(set(x) == A4_CANDIDATE_FIELDS and x["descriptor"] == "PARSED" and
                    x["binding"] == "REJECTED" for x in candidates),
                "A.4 unresolved candidate disposition drifted")
        ids = [str(x["candidate_id"]) for x in candidates]
        require(len(ids) == len(set(ids)) and candidate_set_sha256(ids) == item["candidate_set_sha256"],
                "A.4 unresolved candidate set drifted")
        result[str(item["asset_id"])] = item
    require(total == 3651 and len(result) == 19 and
            sum(int(x["candidate_count"]) for x in result.values()) == 24,
            "A.4 unresolved population drifted")
    return result


def prepare(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    paths = {role: repo_path(root, relative) for role, relative, _ in INPUTS}
    policy = load_json(paths["policy"])
    validate_context(root, paths, policy)
    unresolved = load_unresolved(paths["a4_detail"])
    assets: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(paths["p2_12_catalog"]):
        asset_id = stable_asset_id(str(item["path"]), str(item["sha256"]))
        if asset_id in unresolved:
            require(asset_id not in assets, "P2-12 A.7 asset duplicated")
            assets[asset_id] = item
    require(set(assets) == set(unresolved), "P2-12 A.7 asset coverage drifted")
    candidate_ids = {str(x["candidate_id"]) for item in unresolved.values()
                     for x in item["candidates"]}
    require(len(candidate_ids) == 24, "A.7 candidate identities are not unique")
    nodes: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(paths["p2_03_graph"]):
        if item.get("record") == "node" and item.get("id") in candidate_ids:
            identity = str(item["id"])
            require(identity not in nodes, "P2-03 A.7 candidate duplicated")
            nodes[identity] = item
    require(set(nodes) == candidate_ids, "P2-03 A.7 candidate coverage drifted")
    asset_rows: list[str] = []
    expected_class = {"anim": "QSkelMesh", "qtx": "QTexture", "sm": "QStaticMesh"}
    for asset_id in sorted(unresolved):
        source = assets[asset_id]
        prior = unresolved[asset_id]
        ids = sorted(str(x["candidate_id"]) for x in prior["candidates"])
        require(source["family"] == prior["family"] and source["structure"] == prior["structure"],
                "P2-12 asset metadata drifted")
        fields = [asset_id, str(source["path"]), str(source["sha256"]), str(source["bytes"]),
                  str(source["family"]), str(source["structure"]),
                  str(prior["candidate_set_sha256"]), ",".join(ids)]
        require(all("\t" not in x and "\r" not in x and "\n" not in x for x in fields),
                "A.7 asset TSV field is unsafe")
        asset_rows.append("\t".join(fields))
    candidate_rows: list[str] = []
    for identity in sorted(nodes):
        node = nodes[identity]
        families = {str(item["family"]) for item in unresolved.values()
                    if identity in {str(x["candidate_id"]) for x in item["candidates"]}}
        require(all(node["class"] == expected_class[family] for family in families),
                "P2-03 candidate family drifted")
        fields = [identity, str(node["package"]), str(node["body_offset"]),
                  str(node["body_size"]), str(node["class"])]
        require(all("\t" not in x and "\r" not in x and "\n" not in x for x in fields),
                "A.7 candidate TSV field is unsafe")
        candidate_rows.append("\t".join(fields))
    write_text(Path(args.asset_tsv), "\n".join(asset_rows) + "\n")
    write_text(Path(args.candidate_tsv), "\n".join(candidate_rows) + "\n")
    return {"schema_version": 1, "result": "PASS", "targets": 19,
            "candidate_edges": 24, "unique_candidates": 24}


def finalize(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    paths = {role: repo_path(root, relative) for role, relative, _ in INPUTS}
    policy = load_json(paths["policy"])
    validate_context(root, paths, policy)
    unresolved = load_unresolved(paths["a4_detail"])
    probe_records = list(iter_jsonl(Path(args.probe_jsonl)))
    require(len(probe_records) == 19, "A.7 probe target count drifted")
    expected_ids = set(unresolved)
    require({str(x.get("asset_id")) for x in probe_records} == expected_ids,
            "A.7 probe target set drifted")
    detail_records: list[dict[str, Any]] = []
    by_error: collections.Counter[tuple[str, str, str]] = collections.Counter()
    family_counts: dict[str, dict[str, int]] = {
        family: {"targets": 0, "candidate_edges": 0} for family in ("anim", "qtx", "sm")}
    for probe in sorted(probe_records, key=lambda x: str(x["asset_id"])):
        require(set(probe) == PROBE_FIELDS, "A.7 probe record is not closed")
        asset_id = str(probe["asset_id"])
        prior = unresolved[asset_id]
        require(probe["family"] == prior["family"] and
                probe["candidate_count"] == prior["candidate_count"] and
                probe["candidate_set_sha256"] == prior["candidate_set_sha256"],
                "A.7 probe target binding drifted")
        prior_candidates = {str(x["candidate_id"]): x for x in prior["candidates"]}
        candidates: list[dict[str, Any]] = []
        for observed in probe["candidates"]:
            require(set(observed) == PROBE_CANDIDATE_FIELDS, "A.7 probe candidate is not closed")
            identity = str(observed["candidate_id"])
            require(identity in prior_candidates, "A.7 probe candidate is not in A.4")
            frozen = prior_candidates[identity]
            schema = str(observed["error_schema"])
            code = str(observed["error_code"])
            read_code = observed["read_error_code"]
            require(schema == FAMILY_SCHEMA[probe["family"]] and
                    code in policy["production_error_schemas"][schema] and
                    (read_code is None or read_code in policy["read_error_codes"]),
                    "A.7 production error is not family typed")
            require(observed["bind_result"] == "REJECTED" and
                    observed["automatic_resolution"] is False and
                    observed["body_sha256"] == frozen["body_sha256"] and
                    observed["failure_id"] == failure_id(
                        asset_id, identity, schema, code, read_code,
                        str(observed["error_context_sha256"])),
                    "A.7 candidate binding or failure identity drifted")
            merged = dict(observed)
            merged["descriptor_semantic_sha256"] = frozen["descriptor_semantic_sha256"]
            require(set(merged) == DETAIL_CANDIDATE_FIELDS, "A.7 detail candidate is not closed")
            candidates.append(merged)
            by_error[(str(probe["family"]), schema, code)] += 1
        require(set(prior_candidates) == {str(x["candidate_id"]) for x in candidates},
                "A.7 candidate coverage drifted")
        family_counts[str(probe["family"])]["targets"] += 1
        family_counts[str(probe["family"])]["candidate_edges"] += len(candidates)
        detail = {"asset_id": asset_id, "family": probe["family"],
                  "candidate_count": len(candidates),
                  "candidate_set_sha256": probe["candidate_set_sha256"],
                  "prior_resolution": "UNRESOLVED",
                  "effective_resolution": prior["resolution"],
                  "candidate_selected": False, "automatic_resolution": False,
                  "authority_status": "REQUIRED_NOT_PROVIDED",
                  "candidates": sorted(candidates, key=lambda x: str(x["candidate_id"]))}
        require(set(detail) == DETAIL_FIELDS, "A.7 detail target is not closed")
        detail_records.append(detail)
    require(family_counts == policy["scope"]["by_family"] and sum(by_error.values()) == 24,
            "A.7 family or error reconciliation drifted")
    detail_path = Path(args.detail_output).resolve()
    report_path = Path(args.json_output).resolve()
    markdown_path = Path(args.markdown_output).resolve()
    write_text(detail_path, "\n".join(canonical_json(x) for x in detail_records) + "\n")
    entries = [binding(root, *item) for item in INPUTS]
    aggregate = "".join(f"{x['role']}\t{x['path']}\t{x['tracked']}\t{x['bytes']}\t{x['lines']}\t{x['sha256']}\n"
                        for x in entries)
    captured = args.captured_utc or dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    dt.datetime.fromisoformat(captured.replace("Z", "+00:00"))
    effective_targets = collections.Counter(str(x["effective_resolution"]).lower()
                                            for x in detail_records)
    effective_edges = collections.Counter()
    for item in detail_records:
        effective_edges[str(item["effective_resolution"]).lower()] += item["candidate_count"]
    measured = {"diagnosed_targets": 19, "diagnosed_candidate_edges": 24,
                "typed_error_edges": 24, "unclassified_error_edges": 0,
                "candidate_selections": 0, "automatic_resolutions": 0,
                "owner_dispositions": 0, "by_family": family_counts,
                "by_error": [{"family": family, "error_schema": schema,
                              "error_code": code, "count": count}
                             for (family, schema, code), count in sorted(by_error.items())],
                "effective": {"resolved_targets": effective_targets["resolved"],
                              "resolved_edges": effective_edges["resolved"],
                              "ambiguous_targets": effective_targets["ambiguous"],
                              "ambiguous_edges": effective_edges["ambiguous"],
                              "unresolved_targets": effective_targets["unresolved"],
                              "unresolved_edges": effective_edges["unresolved"]}}
    require(measured["by_error"] == policy["expected_error_counts"],
            "A.7 production error distribution drifted")
    report = {"schema_version": 1, "evidence_revision": "P2-20A.7",
              "captured_utc": captured, "task_id": "P2-20A", "criterion_id": "G2-06",
              "source_build": "qy-3.0.0.413", "result": "BLOCKED",
              "review_execution_result": "PASS", "task_status": "BLOCKED",
              "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
              "remediation_scope_complete": False, "g2_06_satisfied": False,
              "p3_authorized": False,
              "input_bindings": {"aggregate_sha256": sha256_text(aggregate), "entries": entries},
              "detail_export": output_binding(
                  detail_path, policy["outputs"]["detail_export"], False),
              "scope": policy["scope"], "measured": measured,
              "classification_controls": policy["controls"],
              "authority_boundary": {"machine_can_reproduce": True,
                 "machine_can_classify_errors": True, "machine_can_select_candidate": False,
                 "machine_can_approve_disposition": False,
                 "technical_adapter_must_be_contract_proven": True,
                 "content_change_or_no_ref_requires_owner": True,
                 "owner_records": 0, "approved_fixes": 0, "verified_resolutions": 0},
              "preserved_blockers": policy["preserved_blockers"],
              "blockers": [
                  {"reason_code": "PRODUCTION_BINDING_REJECTIONS_REMAIN_EFFECTIVELY_OPEN",
                   "count": effective_targets["ambiguous"] + effective_targets["unresolved"]},
                  {"reason_code": "FULL_WORKSET_AMBIGUITY_REMAINS_OPEN",
                   "count": policy["preserved_blockers"]["asset_effective_ambiguous_targets"]}],
              "negative_contracts": policy["negative_contracts"],
              "g2_projection": {"criteria_total": 9, "satisfied": 7, "blocked": 2,
                                "g2_decision": "BLOCKED"},
              "contracts": {"policy_sha256": sha256_file(paths["policy"]),
                            "schema_sha256": sha256_file(paths["schema"]),
                            "detail_schema_sha256": sha256_file(paths["detail_schema"])},
              "disclosure": policy["disclosure"]}
    write_text(report_path, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    markdown_lines = ["# P2-20A.7 Production Binding Failure Diagnostics", "",
        "- Review execution: `PASS`; task result: `BLOCKED`",
        "- Strict diagnostic scope: 19 unresolved targets / 24 rejected candidate edges",
        "- Typed production errors: 24; unclassified errors: 0",
        "- Candidate selections: 0; automatic resolutions: 0; owner dispositions: 0",
        f"- Effective resolved by contract: {effective_targets['resolved']} targets / {effective_edges['resolved']} edges",
        f"- Effective unresolved after explicit recovery: {effective_targets['unresolved']} targets / {effective_edges['unresolved']} edges",
        f"- Full A.4 ambiguity remains {load_json(paths['a4_report'])['measured']['ambiguous_targets']} targets / {load_json(paths['a4_report'])['measured']['reconciled_full_workset']['ambiguous_edges']} edges; 212 auxiliary instances and 1,359 migration decisions remain open",
        "- G2 remains 7/9 BLOCKED; P3 remains unauthorized", "",
        "Error codes are reproducible diagnostics, not content-corruption proof or authority disposition.",
        "Raw error contexts, offsets, names, paths, payload values, and legacy source lines are not emitted.", ""]
    write_text(markdown_path, "\n".join(markdown_lines))
    return {"schema_version": 1, "result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
            "targets": 19, "candidate_edges": 24, "typed_error_edges": 24,
            "unclassified_error_edges": 0,
            "effective_resolved_targets": effective_targets["resolved"],
            "effective_resolved_edges": effective_edges["resolved"],
            "effective_ambiguous_targets": effective_targets["ambiguous"],
            "effective_ambiguous_edges": effective_edges["ambiguous"],
            "effective_unresolved_targets": effective_targets["unresolved"],
            "effective_unresolved_edges": effective_edges["unresolved"],
            "candidate_selections": 0, "g2_06_satisfied": False, "p3_authorized": False,
            "report_sha256": sha256_file(report_path), "detail_sha256": sha256_file(detail_path)}


def self_test() -> dict[str, Any]:
    assertions = 0
    require(stable_asset_id("a/b.qtx", "0" * 64) == stable_asset_id("a/b.qtx", "0" * 64),
            "Stable asset id failed"); assertions += 1
    require(stable_asset_id("a/b.qtx", "0" * 64) != stable_asset_id("A/b.qtx", "0" * 64),
            "Asset path case was folded"); assertions += 1
    require(candidate_set_sha256(["b" * 64, "a" * 64]) ==
            candidate_set_sha256(["a" * 64, "b" * 64]), "Candidate set is unstable"); assertions += 1
    require(candidate_set_sha256(["a" * 64]) != candidate_set_sha256(["b" * 64]),
            "Candidate set fixture collided"); assertions += 1
    first = failure_id("a" * 64, "b" * 64, "TextureError/v1", "read_failure", None, "c" * 64)
    require(len(first) == 64, "Failure id is invalid"); assertions += 1
    require(first != failure_id("a" * 64, "b" * 64, "TextureError/v1", "read_failure",
                                "out_of_bounds", "c" * 64), "Read error was omitted"); assertions += 1
    require(set(FAMILY_SCHEMA) == {"anim", "qtx", "sm"}, "Family set drifted"); assertions += 1
    require(len(INPUTS) == 13 and len({x[0] for x in INPUTS}) == 13,
            "Input role set drifted"); assertions += 1
    require("descriptor_semantic_sha256" in DETAIL_CANDIDATE_FIELDS,
            "A.4 descriptor binding disappeared"); assertions += 1
    require("automatic_resolution" in DETAIL_FIELDS and "candidate_selected" in DETAIL_FIELDS,
            "Fail-closed detail controls disappeared"); assertions += 1
    return {"schema_version": 1, "result": "PASS", "assertions": assertions}


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command")
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--root", required=True)
    prepare_parser.add_argument("--asset-tsv", required=True)
    prepare_parser.add_argument("--candidate-tsv", required=True)
    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("--root", required=True)
    finalize_parser.add_argument("--probe-jsonl", required=True)
    finalize_parser.add_argument("--detail-output", required=True)
    finalize_parser.add_argument("--json-output", required=True)
    finalize_parser.add_argument("--markdown-output", required=True)
    finalize_parser.add_argument("--captured-utc")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = self_test()
    elif args.command == "prepare":
        result = prepare(args)
    elif args.command == "finalize":
        result = finalize(args)
    else:
        parser.error("choose prepare, finalize, or --self-test")
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
