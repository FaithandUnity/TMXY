"""Closed-set helpers for P2-20A.8 asset-binding recovery evidence."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


SHA256 = "^[0-9a-f]{64}$"
PLAN_COLUMNS = (
    "asset_id", "candidate_id", "body_sha256", "source_sha256", "family",
    "recovery_kind", "strict_error_code",
)
ATTEMPT_RULES = {
    ("qtx", "payload_size_mismatch"): "qtx_complete_mip_chain",
    ("anim", "frame_count_mismatch"): "anim_payload_frame_counts",
}
ALLOWED_RECOVERY_KINDS = {
    ("qtx", "payload_size_mismatch"): {
        "qtx_complete_mip_chain", "qtx_declared_mip_payload_prefix",
    },
    ("anim", "frame_count_mismatch"): {"anim_payload_frame_counts"},
}
A7_ROOT_FIELDS = {
    "asset_id", "family", "candidate_count", "candidate_set_sha256",
    "prior_resolution", "effective_resolution", "candidate_selected",
    "automatic_resolution", "authority_status", "candidates",
}
A7_CANDIDATE_FIELDS = {
    "candidate_id", "body_sha256", "descriptor_semantic_sha256", "bind_result",
    "error_schema", "error_code", "read_error_code", "error_context_sha256",
    "failure_id", "automatic_resolution",
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


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def stable_asset_id(relative_path: str, source_sha256: str) -> str:
    return sha256_text("asset\0" + relative_path + "\0" + source_sha256)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root is not an object: {path.name}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL row {number} is not an object")
            yield value


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n").replace("\r", "\n"),
                    encoding="utf-8", newline="\n")


def line_count(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def repo_relative(root: Path, path: Path) -> str:
    resolved = path.resolve()
    require(resolved.is_relative_to(root), "Evidence path escaped repository root")
    return resolved.relative_to(root).as_posix()


def binding(root: Path, role: str, path: Path, tracked: bool) -> dict[str, Any]:
    require(path.is_file(), f"Missing evidence input: {path.name}")
    return {
        "role": role,
        "path": repo_relative(root, path),
        "tracked": tracked,
        "bytes": path.stat().st_size,
        "lines": line_count(path),
        "sha256": sha256_file(path),
    }


def binding_set(entries: list[dict[str, Any]]) -> dict[str, Any]:
    text = "".join(
        f"{x['role']}\t{x['path']}\t{str(x['tracked']).lower()}\t{x['bytes']}\t"
        f"{x['lines']}\t{x['sha256']}\n" for x in entries
    )
    return {"aggregate_sha256": sha256_text(text), "entries": entries}


def output_binding(root: Path, path: Path, advertised: str | None = None) -> dict[str, Any]:
    require(path.is_file(), f"Missing evidence output: {path.name}")
    relative = advertised if advertised is not None else repo_relative(root, path)
    require(relative and "\\" not in relative and ".." not in Path(relative).parts,
            "Advertised output path is not portable")
    return {"path": relative, "tracked": False, "bytes": path.stat().st_size,
            "lines": line_count(path), "sha256": sha256_file(path)}


def find_bound_input(report: dict[str, Any], role: str) -> dict[str, Any]:
    found = [x for x in report["input_bindings"]["entries"] if x["role"] == role]
    require(len(found) == 1, f"A.7 input role is not unique: {role}")
    return found[0]


def verify_file_binding(root: Path, item: dict[str, Any]) -> Path:
    relative = str(item["path"])
    require("\\" not in relative and ".." not in Path(relative).parts,
            "Bound path is not portable")
    path = (root / relative).resolve()
    require(path.is_relative_to(root) and path.is_file(), "Bound input is missing")
    require(path.stat().st_size == int(item["bytes"]) and
            line_count(path) == int(item["lines"]) and
            sha256_file(path) == item["sha256"], "Bound input hash or size drifted")
    return path


def load_frozen_a7(root: Path) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]], Path]:
    report_path = root / "Data/Reports/p2-20a-asset-binding-failure-diagnostics-report.json"
    evidence_path = root / "Data/Inventory/p2-20a-asset-binding-failure-diagnostics.json"
    report, evidence = load_json(report_path), load_json(evidence_path)
    require(report["evidence_revision"] == "P2-20A.7" and report["result"] == "BLOCKED",
            "A.7 tracked report is not the frozen blocked diagnostic")
    require(report["scope"]["targets"] == 19 and report["scope"]["candidate_edges"] == 24,
            "A.7 tracked scope drifted")
    require(evidence["outputs"]["report_json"]["sha256"] == sha256_file(report_path),
            "A.7 report is not bound by its inventory")
    detail_binding = report["detail_export"]
    detail_path = verify_file_binding(root, detail_binding)
    require(evidence["outputs"]["detail_export"]["sha256"] == sha256_file(detail_path),
            "A.7 detail is not bound by its inventory")
    details = list(iter_jsonl(detail_path))
    require(len(details) == 19, "A.7 detail target count drifted")
    edges = 0
    for item in details:
        require(set(item) == A7_ROOT_FIELDS, "A.7 detail root is not closed")
        require(item["prior_resolution"] == "UNRESOLVED" and
                item["effective_resolution"] in {"RESOLVED", "AMBIGUOUS", "UNRESOLVED"} and
                item["candidate_selected"] is False and
                item["automatic_resolution"] is False, "A.7 authority state drifted")
        require(len(item["candidates"]) == item["candidate_count"],
                "A.7 candidate count drifted")
        for candidate in item["candidates"]:
            require(set(candidate) == A7_CANDIDATE_FIELDS,
                    "A.7 candidate detail is not closed")
            require(candidate["bind_result"] == "REJECTED" and
                    candidate["automatic_resolution"] is False,
                    "A.7 strict binding state drifted")
            edges += 1
    require(edges == 24, "A.7 candidate edge count drifted")
    catalog_binding = find_bound_input(report, "p2_12_catalog")
    catalog_path = verify_file_binding(root, catalog_binding)
    return report, evidence, details, catalog_path


def source_hashes(details: list[dict[str, Any]], catalog_path: Path) -> dict[str, str]:
    wanted = {str(item["asset_id"]) for item in details}
    result: dict[str, str] = {}
    for item in iter_jsonl(catalog_path):
        identity = stable_asset_id(str(item["path"]), str(item["sha256"]))
        if identity in wanted:
            require(identity not in result, "P2-12 A.7 asset identity is duplicated")
            result[identity] = str(item["sha256"])
    require(set(result) == wanted, "P2-12 does not cover the complete A.7 target set")
    return result


def build_attempt_rows(details: list[dict[str, Any]], sources: dict[str, str]) -> list[tuple[str, ...]]:
    rows: list[tuple[str, ...]] = []
    for item in details:
        for candidate in item["candidates"]:
            key = (str(item["family"]), str(candidate["error_code"]))
            if key not in ATTEMPT_RULES:
                continue
            rows.append((
                str(item["asset_id"]), str(candidate["candidate_id"]),
                str(candidate["body_sha256"]), sources[str(item["asset_id"])], key[0],
                ATTEMPT_RULES[key], key[1],
            ))
    rows.sort(key=lambda x: (x[0], x[1]))
    require(len(rows) == len(set((x[0], x[1]) for x in rows)),
            "Recovery attempt edge is duplicated")
    return rows


def write_plan(path: Path, rows: list[tuple[str, ...]]) -> None:
    require(all(len(row) == len(PLAN_COLUMNS) for row in rows), "Plan width drifted")
    require(all(all("\t" not in x and "\r" not in x and "\n" not in x for x in row)
                for row in rows), "Plan field is not TSV-safe")
    write_text(path, "".join("\t".join(row) + "\n" for row in rows))


def read_plan(path: Path) -> list[tuple[str, ...]]:
    rows: list[tuple[str, ...]] = []
    with path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            row = tuple(line.rstrip("\n").split("\t"))
            require(len(row) == len(PLAN_COLUMNS), f"Plan row {number} width drifted")
            require(all(len(row[index]) == 64 for index in range(4)),
                    f"Plan row {number} identity width drifted")
            require((row[4], row[6]) in ALLOWED_RECOVERY_KINDS and
                    row[5] in ALLOWED_RECOVERY_KINDS[(row[4], row[6])],
                    f"Plan row {number} recovery rule drifted")
            rows.append(row)
    require(rows == sorted(rows, key=lambda x: (x[0], x[1])), "Plan is not ordered")
    require(len(rows) == len(set((x[0], x[1]) for x in rows)), "Plan edge duplicated")
    return rows
