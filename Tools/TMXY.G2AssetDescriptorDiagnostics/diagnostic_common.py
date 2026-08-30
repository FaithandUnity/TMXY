"""Shared closed-set and hashing primitives for P2-20A.4."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


ASSET_FIELDS = {
    "asset_id", "candidate_count", "candidate_set_sha256", "descriptor_variants",
    "family", "heuristic_selection", "resolution", "resolution_basis", "structure",
    "valid_variants",
}
SELECTED_BASES = {
    "EQUIVALENT_VALID_DESCRIPTOR_SET", "DIVERGENT_DESCRIPTOR_SET",
    "DESCRIPTOR_VALIDATION_FAILED",
}
FAMILIES = {"qtx", "sm", "skem", "anim"}


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


def sha256_lines(values: Iterable[str]) -> str:
    return hashlib.sha256(("\n".join(sorted(values)) + "\n").encode("utf-8")).hexdigest()


def probe_candidate_set_sha256(values: Iterable[str]) -> str:
    payload = bytearray(b"tmxy-g2-asset-descriptor-candidate-set-v1\0")
    for value in sorted(values):
        payload.extend(value.encode("ascii"))
        payload.append(0)
    return hashlib.sha256(payload).hexdigest()


def stable_asset_id(relative_path: str, content_sha256: str) -> str:
    return hashlib.sha256(
        ("asset\0" + relative_path + "\0" + content_sha256).encode("utf-8")
    ).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root must be an object: {path.name}")
    return value


def iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as stream:
        for number, line in enumerate(stream, start=1):
            value = json.loads(line)
            require(isinstance(value, dict), f"JSONL record {number} is not an object")
            yield value


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.replace("\r\n", "\n").replace("\r", "\n"),
                    encoding="utf-8", newline="\n")


def resolve_repo_path(root: Path, relative: str) -> Path:
    require(relative and "\\" not in relative, "Repository path is not portable")
    item = Path(relative)
    require(not item.is_absolute() and ".." not in item.parts,
            "Repository path escaped the root")
    resolved = (root / item).resolve()
    require(resolved.is_relative_to(root) and resolved.is_file(),
            f"Required repository input is missing: {relative}")
    return resolved


def validate_bound_export(root: Path, report: dict[str, Any], section: str,
                          expected_lines: int | None = None) -> Path:
    binding = report[section]
    relative = binding.get("path", binding.get("local_path"))
    require(isinstance(relative, str), f"{section} has no bound export path")
    path = resolve_repo_path(root, relative)
    require(sha256_file(path) == binding["sha256"],
            f"{section} SHA-256 does not match its tracked evidence")
    if "lines" in binding:
        require(sum(1 for _ in path.open("rb")) == int(binding["lines"]),
                f"{section} line count does not match its tracked evidence")
    if expected_lines is not None:
        require(sum(1 for _ in path.open("rb")) == expected_lines,
                f"{section} frozen line count drifted")
    return path


def load_selected_workset(path: Path) -> dict[str, dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for item in iter_jsonl(path):
        require(set(item) == ASSET_FIELDS, "Asset binding workset record is not closed")
        include = (item["resolution_basis"] in SELECTED_BASES or
                   (item["family"] == "skem" and
                    item["resolution_basis"] == "UNIQUE_VALID_DESCRIPTOR"))
        if include:
            require(item["family"] in FAMILIES, "Selected family is unsupported")
            asset_id = str(item["asset_id"])
            require(asset_id not in selected, "Selected asset is duplicated")
            selected[asset_id] = item
    require(len(selected) == 3651, "P2-20A.4 target scope drifted from 3,651")
    require(sum(int(x["candidate_count"]) for x in selected.values()) == 12764,
            "P2-20A.4 candidate-edge scope drifted from 12,764")
    return selected
