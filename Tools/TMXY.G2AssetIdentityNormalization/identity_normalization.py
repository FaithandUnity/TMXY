"""P2-20A.6 fail-closed identity-normalization safety audit."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


ROOT_FIELDS = {
    "asset_id", "candidate_count", "candidate_identity_exact", "candidate_selected",
    "candidate_set_sha256", "candidates", "compatible_semantic_variants", "counts",
    "family", "heuristic_selection", "prior_resolution", "prior_resolution_basis",
    "production_binder_used", "resolution", "resolution_basis", "strict_resolution",
    "strict_resolution_basis", "strict_compatible_semantic_variants", "structure",
}
CANDIDATE_FIELDS = {
    "binding", "body_sha256", "candidate_id", "descriptor", "descriptor_semantic_sha256",
    "effective_binding", "effective_semantic_sha256", "recovery_applied", "recovery_kind",
    "identity_mirror_ascii_lower_match", "identity_normalized_descriptor_semantic_sha256",
    "identity_normalized_semantic_sha256", "semantic_sha256",
}
DETAIL_FIELDS = {
    "asset_id", "candidate_count", "candidate_set_sha256", "case_fold_identity_collision",
    "exact_identity_variants", "ascii_lower_identity_variants", "raw_semantic_variants",
    "strict_descriptor_semantic_variants", "strict_full_semantic_variants",
    "effective_resolution", "candidate_selected", "first_candidate_selection_used",
    "candidates",
}
DETAIL_CANDIDATE_FIELDS = {
    "candidate_id", "body_sha256", "logical_name_sha256",
    "logical_name_ascii_lower_sha256", "semantic_sha256",
    "identity_normalized_descriptor_semantic_sha256",
    "identity_normalized_semantic_sha256",
}
FAMILY_CLASS = {"qtx": "QTexture", "sm": "QStaticMesh", "skem": "QSkelMesh", "anim": "QSkelMesh"}
INPUTS = [
    ("a4_report", "Data/Reports/p2-20a-asset-descriptor-diagnostics-report.json", True),
    ("a4_detail", "Data/Exports/P2-20/p2-20a-asset-descriptor-diagnostics.jsonl", False),
    ("a4_policy", "Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json", True),
    ("p2_03_evidence", "Data/Inventory/p2-03-package-dependency-graph.json", True),
    ("p2_03_graph", "Data/Exports/P2-03/p2-03-package-dependency-graph.jsonl", False),
    ("policy", "Contracts/data-schema/g2-asset-identity-normalization-policy-v1.json", True),
    ("schema", "Contracts/data-schema/g2-asset-identity-normalization-v1.schema.json", True),
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


def sha256_lines(values: Iterable[str]) -> str:
    return sha256_text("\n".join(sorted(values)) + "\n")


def line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        result = json.load(stream)
    require(isinstance(result, dict), f"JSON root is not an object: {path.name}")
    return result


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL record {number} is not an object")
            yield value


def safe_path(root: Path, relative: str) -> Path:
    require(relative and "\\" not in relative, "Repository path is not portable")
    item = Path(relative)
    require(not item.is_absolute() and ".." not in item.parts, "Repository path escaped root")
    result = (root / item).resolve()
    require(result.is_relative_to(root) and result.is_file(), f"Missing input: {relative}")
    return result


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n").replace("\r", "\n"),
                    encoding="utf-8", newline="\n")


def binding(root: Path, role: str, relative: str, tracked: bool) -> dict[str, Any]:
    path = safe_path(root, relative)
    return {
        "role": role, "path": relative, "tracked": tracked,
        "bytes": path.stat().st_size, "lines": line_count(path), "sha256": sha256_file(path),
    }


def file_binding(path: Path, advertised: str, tracked: bool) -> dict[str, Any]:
    return {
        "path": advertised, "tracked": tracked, "bytes": path.stat().st_size,
        "lines": line_count(path), "sha256": sha256_file(path),
    }


def validate_policy(policy: dict[str, Any]) -> None:
    require(policy.get("schema_version") == 1 and policy.get("evidence_revision") == "P2-20A.6",
            "Policy identity mismatch")
    require(policy.get("task_id") == "P2-20A" and policy.get("criterion_id") == "G2-06" and
            policy.get("source_build") == "qy-3.0.0.413", "Policy task identity mismatch")
    rules = policy["normalization_rules"]
    require(rules == {
        "identity_grouping": "P2-03 ASCII-lower identity hash only",
        "ascii_bytes_only": True, "unicode_casefold": False,
        "locale_sensitive_mapping": False, "path_normalization": False,
        "descriptor_field_normalization": False,
        "identity_grouping_is_semantic_equivalence": False,
        "strict_descriptor_semantics_required": True, "strict_full_semantics_required": True,
        "nested_references_preserved": True, "unknown_properties_preserved": True,
        "floating_point_bits_preserved": True, "field_order_preserved": True,
        "first_candidate_selection": False, "representative_candidate_selection": False,
        "coarse_equivalence_substitution": False,
    }, "Normalization policy is not the strict closed rule set")


def validate_sources(root: Path, report: dict[str, Any], p203: dict[str, Any],
                     detail_path: Path, graph_path: Path) -> None:
    require(report.get("evidence_revision") == "P2-20A.4" and report.get("task_id") == "P2-20A" and
            report.get("criterion_id") == "G2-06", "A.4 report identity mismatch")
    require(report.get("result") == "BLOCKED" and report.get("review_execution_result") == "PASS" and
            report.get("completion_criteria_satisfied") is False and
            report.get("diagnostic_scope_complete") is True and
            report.get("g2_06_satisfied") is False and report.get("p3_authorized") is False,
            "A.4 report is not fail-closed")
    require(report["scope"]["targets"] == 3651 and report["scope"]["candidate_edges"] == 12764 and
            report["scope"]["candidate_identity_exact"] is True and
            report["scope"]["first_candidate_selection_used"] is False and
            report["measured"]["by_resolution_basis_targets"][
                "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"] == 15 and
            report["measured"]["by_resolution_basis_edges"][
                "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"] == 30,
            "A.4 ambiguous scope drifted")
    advertised = report["detail_export"]
    require(advertised["path"] == INPUTS[1][1] and advertised["lines"] == 3651 and
            advertised["sha256"] == sha256_file(detail_path), "A.4 detail binding mismatch")
    require(p203.get("task") == "P2-03" and p203.get("result") == "PASS" and
            p203.get("completion_criteria_satisfied") is True, "P2-03 evidence is not complete")
    graph = p203["graph"]
    require(graph["local_path"] == INPUTS[4][1] and graph["lines"] == 269064 and
            graph["sha256"] == sha256_file(graph_path), "P2-03 graph binding mismatch")
    a4_policy = load_json(safe_path(root, INPUTS[2][1]))
    semantic = a4_policy["semantic_signature"]
    require(semantic["object_name_included"] is True and semantic["ordered_fields_preserved"] is True and
            semantic["unknown_property_name_and_value_bytes_included"] is True and
            semantic["floating_point_bits_preserved"] is True and
            semantic["storage_offsets_and_sizes_excluded"] is True,
            "A.4 semantic signature is not strict enough")


def load_ambiguous(detail_path: Path) -> list[dict[str, Any]]:
    ambiguous: list[dict[str, Any]] = []
    total = 0
    for item in iter_jsonl(detail_path):
        total += 1
        require(set(item) == ROOT_FIELDS, "A.4 detail record is not closed")
        if item["resolution_basis"] == "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES":
            ambiguous.append(item)
    require(total == 3651 and len(ambiguous) == 15, "A.4 detail population drifted")
    require(sum(int(x["candidate_count"]) for x in ambiguous) == 30,
            "A.4 ambiguous edge population drifted")
    return ambiguous


def load_nodes(graph_path: Path, expected_ids: set[str]) -> dict[str, dict[str, Any]]:
    nodes: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(graph_path):
        if item.get("record") == "node" and item.get("id") in expected_ids:
            identity = str(item["id"])
            require(identity not in nodes, "P2-03 candidate identity is duplicated")
            nodes[identity] = item
    require(set(nodes) == expected_ids, "P2-03 candidate identity set is incomplete")
    return nodes


def classify(item: dict[str, Any], nodes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    require(item["candidate_count"] == 2 and item["candidate_identity_exact"] is True and
            item["candidate_selected"] is False and item["heuristic_selection"] is False and
            item["production_binder_used"] is True and item["compatible_semantic_variants"] == 2,
            "Ambiguous target controls drifted")
    candidates = item["candidates"]
    require(isinstance(candidates, list) and len(candidates) == 2, "Candidate pair is incomplete")
    ids = [str(x["candidate_id"]) for x in candidates]
    require(ids == sorted(ids) and len(set(ids)) == 2 and
            sha256_lines(ids) == item["candidate_set_sha256"], "Candidate set binding drifted")
    family = str(item["family"])
    require(family in FAMILY_CLASS, "Unsupported ambiguous family")
    detail_candidates: list[dict[str, Any]] = []
    for candidate in candidates:
        require(set(candidate) == CANDIDATE_FIELDS, "A.4 candidate record is not closed")
        require(candidate["descriptor"] == "PARSED" and candidate["binding"] == "PASS" and
                candidate["effective_binding"] == "PASS" and
                candidate["effective_semantic_sha256"] == candidate["semantic_sha256"] and
                candidate["recovery_applied"] is False and candidate["recovery_kind"] == "none",
                "Ambiguous candidate lacks production semantics")
        for name in CANDIDATE_FIELDS - {"binding", "descriptor", "effective_binding",
                                        "identity_mirror_ascii_lower_match", "recovery_applied",
                                        "recovery_kind"}:
            require(isinstance(candidate[name], str) and len(candidate[name]) == 64,
                    f"Candidate hash field is invalid: {name}")
        require(isinstance(candidate["identity_mirror_ascii_lower_match"], bool),
                "Identity mirror observation is not boolean")
        node = nodes[str(candidate["candidate_id"])]
        require(node.get("class") == FAMILY_CLASS[family], "P2-03 candidate class drifted")
        exact = str(node["logical_name_sha256"])
        lower = str(node["logical_name_ascii_lower_sha256"])
        require(len(exact) == 64 and len(lower) == 64, "P2-03 identity hash is invalid")
        detail_candidates.append({
            "candidate_id": candidate["candidate_id"], "body_sha256": candidate["body_sha256"],
            "logical_name_sha256": exact, "logical_name_ascii_lower_sha256": lower,
            "semantic_sha256": candidate["semantic_sha256"],
            "identity_normalized_descriptor_semantic_sha256":
                candidate["identity_normalized_descriptor_semantic_sha256"],
            "identity_normalized_semantic_sha256": candidate["identity_normalized_semantic_sha256"],
        })
    exact_variants = len({x["logical_name_sha256"] for x in detail_candidates})
    lower_variants = len({x["logical_name_ascii_lower_sha256"] for x in detail_candidates})
    raw_variants = len({x["semantic_sha256"] for x in detail_candidates})
    descriptor_variants = len({x["identity_normalized_descriptor_semantic_sha256"]
                               for x in detail_candidates})
    semantic_variants = len({x["identity_normalized_semantic_sha256"]
                             for x in detail_candidates})
    require(exact_variants in {1, 2} and raw_variants == 2, "Source ambiguity was erased")
    case_fold = exact_variants == 2 and lower_variants == 1
    require((exact_variants, lower_variants) in {(1, 1), (2, 1), (2, 2)},
            "Unexpected P2-03 identity multiplicity")
    effective = "RESOLVED" if descriptor_variants == 1 and semantic_variants == 1 else "AMBIGUOUS"
    result = {
        "asset_id": item["asset_id"], "candidate_count": 2,
        "candidate_set_sha256": item["candidate_set_sha256"],
        "case_fold_identity_collision": case_fold, "exact_identity_variants": exact_variants,
        "ascii_lower_identity_variants": lower_variants, "raw_semantic_variants": raw_variants,
        "strict_descriptor_semantic_variants": descriptor_variants,
        "strict_full_semantic_variants": semantic_variants, "effective_resolution": effective,
        "candidate_selected": False, "first_candidate_selection_used": False,
        "candidates": detail_candidates,
    }
    require(set(result) == DETAIL_FIELDS and
            all(set(x) == DETAIL_CANDIDATE_FIELDS for x in detail_candidates),
            "A.6 detail record is not closed")
    return result


def aggregate(records: list[dict[str, Any]], source: dict[str, Any]) -> dict[str, Any]:
    case_records = [x for x in records if x["case_fold_identity_collision"]]
    descriptor_equal = [x for x in records if x["strict_descriptor_semantic_variants"] == 1]
    semantic_equal = [x for x in records if x["strict_full_semantic_variants"] == 1]
    resolved = [x for x in records if x["effective_resolution"] == "RESOLVED"]
    measured = {
        "source_ambiguous_targets": len(records),
        "source_candidate_edges": sum(x["candidate_count"] for x in records),
        "case_fold_collision_targets": len(case_records),
        "case_fold_collision_edges": sum(x["candidate_count"] for x in case_records),
        "non_case_identity_targets": len(records) - len(case_records),
        "non_case_identity_edges": sum(x["candidate_count"] for x in records if x not in case_records),
        "strict_descriptor_equivalent_targets": len(descriptor_equal),
        "strict_descriptor_equivalent_edges": sum(x["candidate_count"] for x in descriptor_equal),
        "strict_full_semantic_equivalent_targets": len(semantic_equal),
        "strict_full_semantic_equivalent_edges": sum(x["candidate_count"] for x in semantic_equal),
        "effective": {
            "resolved_targets": len(resolved),
            "resolved_edges": sum(x["candidate_count"] for x in resolved),
            "ambiguous_targets": len(records) - len(resolved),
            "ambiguous_edges": sum(x["candidate_count"] for x in records if x not in resolved),
        },
        "candidate_selections": sum(bool(x["candidate_selected"]) for x in records),
        "reconciled_full_workset": dict(source),
    }
    return measured


def markdown(report: dict[str, Any]) -> str:
    m = report["measured"]
    return "\n".join([
        "# P2-20A.6 Identity Normalization Safety Audit", "",
        f"- Result: `{report['result']}`; review execution: `{report['review_execution_result']}`",
        f"- Source ambiguous scope: {m['source_ambiguous_targets']} targets / {m['source_candidate_edges']} edges",
        f"- P2-03 ASCII-lower collision: {m['case_fold_collision_targets']} targets / {m['case_fold_collision_edges']} edges",
        f"- Non-case identity multiplicity: {m['non_case_identity_targets']} targets / {m['non_case_identity_edges']} edges",
        f"- Strict descriptor equivalence: {m['strict_descriptor_equivalent_targets']} targets / {m['strict_descriptor_equivalent_edges']} edges",
        f"- Strict full-semantic equivalence: {m['strict_full_semantic_equivalent_targets']} targets / {m['strict_full_semantic_equivalent_edges']} edges",
        f"- Effective ambiguity retained: {m['effective']['ambiguous_targets']} targets / {m['effective']['ambiguous_edges']} edges",
        "- Candidate selection: 0; ASCII-lower identity grouping is not semantic equivalence.",
        "- G2 remains 7/9 BLOCKED and P3 remains unauthorized.", "",
        "The tracked report contains aggregates and hashes only. Anonymous record detail remains ignored.", "",
    ])


def generate(args: argparse.Namespace) -> dict[str, Any]:
    root = Path(args.root).resolve()
    policy = load_json(safe_path(root, INPUTS[5][1]))
    validate_policy(policy)
    paths = {role: safe_path(root, relative) for role, relative, _ in INPUTS}
    report = load_json(paths["a4_report"])
    p203 = load_json(paths["p2_03_evidence"])
    validate_sources(root, report, p203, paths["a4_detail"], paths["p2_03_graph"])
    ambiguous = load_ambiguous(paths["a4_detail"])
    candidate_ids = {str(candidate["candidate_id"]) for item in ambiguous
                     for candidate in item["candidates"]}
    require(len(candidate_ids) > 1, "Ambiguous candidate identity set collapsed")
    nodes = load_nodes(paths["p2_03_graph"], candidate_ids)
    records = [classify(item, nodes) for item in sorted(ambiguous, key=lambda x: x["asset_id"])]
    source_full = report["measured"]["reconciled_full_workset"]
    measured = aggregate(records, source_full)
    require(measured == policy["expected_measured"], "Measured A.6 facts drifted")
    detail_path = Path(args.detail_output).resolve()
    json_path = Path(args.json_output).resolve()
    markdown_path = Path(args.markdown_output).resolve()
    write_text(detail_path, "\n".join(canonical_json(x) for x in records) + "\n")
    entries = [binding(root, *item) for item in INPUTS]
    aggregate_text = "".join(
        f"{x['role']}\t{x['path']}\t{x['tracked']}\t{x['bytes']}\t{x['lines']}\t{x['sha256']}\n"
        for x in entries)
    captured = args.captured_utc or dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
    dt.datetime.fromisoformat(captured.replace("Z", "+00:00"))
    controls = dict(policy["normalization_rules"])
    controls.pop("identity_grouping")
    controls["ascii_lower_identity_grouping_only"] = controls.pop("ascii_bytes_only")
    report_out = {
        "schema_version": 1, "evidence_revision": "P2-20A.6", "captured_utc": captured,
        "task_id": "P2-20A", "criterion_id": "G2-06", "source_build": "qy-3.0.0.413",
        "result": "BLOCKED", "review_execution_result": "PASS", "task_status": "BLOCKED",
        "completion_criteria_satisfied": False, "diagnostic_scope_complete": True,
        "scope_complete": False, "g2_06_satisfied": False, "p3_authorized": False,
        "input_bindings": {"aggregate_sha256": sha256_text(aggregate_text), "entries": entries},
        "detail_export": file_binding(detail_path,
            "Data/Exports/P2-20/p2-20a-asset-identity-normalization.jsonl", False),
        "scope": {
            "source_revision": "P2-20A.4", "source_resolution": "AMBIGUOUS",
            "source_ambiguous_targets": 15, "source_candidate_edges": 30,
            "candidate_count_per_target": 2, "candidate_identity_exact": True,
            "production_descriptor_semantics_used": True, "candidate_selected": False,
            "first_candidate_selection_used": False,
            "representative_candidate_selection_used": False,
        },
        "measured": measured, "normalization_controls": controls,
        "blockers": [
            {"reason_code": "CASE_FOLD_COLLISION_NOT_SEMANTIC_EQUIVALENCE", "count": 13},
            {"reason_code": "NON_CASE_IDENTITY_MULTIPLICITY", "count": 2},
            {"reason_code": "STRICT_SEMANTIC_EQUIVALENCE_ABSENT", "count": 15},
        ],
        "negative_contracts": policy["negative_contracts"],
        "g2_projection": {"criteria_total": 9, "satisfied": 7, "blocked": 2,
                          "g2_decision": "BLOCKED"},
        "contracts": {"policy_sha256": sha256_file(paths["policy"]),
                      "schema_sha256": sha256_file(paths["schema"])},
        "disclosure": policy["disclosure"],
    }
    write_text(json_path, json.dumps(report_out, ensure_ascii=False, indent=2) + "\n")
    write_text(markdown_path, markdown(report_out))
    return {
        "result": "PASS_DIAGNOSTIC", "task_status": "BLOCKED",
        "case_fold_collision_targets": measured["case_fold_collision_targets"],
        "strict_semantic_equivalent_targets": measured["strict_full_semantic_equivalent_targets"],
        "effective_ambiguous_targets": measured["effective"]["ambiguous_targets"],
        "g2_06_satisfied": False, "p3_authorized": False,
        "report_sha256": sha256_file(json_path), "detail_sha256": sha256_file(detail_path),
    }


def ascii_lower(value: bytes) -> bytes:
    return bytes(byte + 32 if 65 <= byte <= 90 else byte for byte in value)


def self_test() -> dict[str, Any]:
    assertions = 0
    require(ascii_lower(b"A-Z_09") == b"a-z_09", "ASCII lower failed"); assertions += 1
    require(ascii_lower(bytes([0xC4, 0x41])) == bytes([0xC4, 0x61]),
            "Non-ASCII byte changed"); assertions += 1
    require(sha256_lines(["b" * 64, "a" * 64]) == sha256_lines(["a" * 64, "b" * 64]),
            "Candidate-set digest is not order stable"); assertions += 1
    require(sha256_lines(["a" * 64]) != sha256_lines(["b" * 64]),
            "Candidate-set digest collision fixture"); assertions += 1
    require(FAMILY_CLASS["anim"] == "QSkelMesh", "Animation class mapping drifted"); assertions += 1
    require(len(INPUTS) == 7 and len({x[0] for x in INPUTS}) == 7,
            "Input roles are not closed"); assertions += 1
    require(ROOT_FIELDS.issuperset({"candidate_selected", "heuristic_selection"}),
            "Selection controls disappeared"); assertions += 1
    require("identity_normalized_descriptor_semantic_sha256" in CANDIDATE_FIELDS and
            "identity_normalized_semantic_sha256" in CANDIDATE_FIELDS,
            "Strict semantic hashes disappeared"); assertions += 1
    require("logical_name_ascii_lower_sha256" in DETAIL_CANDIDATE_FIELDS,
            "P2-03 lower identity proof disappeared"); assertions += 1
    require("candidate_selected" in DETAIL_FIELDS and
            "first_candidate_selection_used" in DETAIL_FIELDS,
            "Fail-closed detail controls disappeared"); assertions += 1
    return {"schema_version": 1, "result": "PASS", "assertions": assertions}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root")
    parser.add_argument("--detail-output")
    parser.add_argument("--json-output")
    parser.add_argument("--markdown-output")
    parser.add_argument("--captured-utc")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        result = self_test()
    else:
        require(all((args.root, args.detail_output, args.json_output, args.markdown_output)),
                "Generation requires root and all output paths")
        result = generate(args)
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
