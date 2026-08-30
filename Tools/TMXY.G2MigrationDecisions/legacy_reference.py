"""Enumerate P2-09 comparable reference membership without emitting identities."""

from __future__ import annotations

import csv
import io
from pathlib import Path
from typing import Any

from g2_common import digest, file_digest, require


def ascii_fold(value: str) -> str:
    return "".join(chr(ord(char) + 32) if "A" <= char <= "Z" else char for char in value)


def read_header(path: Path) -> list[str]:
    data = path.read_bytes()
    try:
        text = data.decode("utf-8-sig", errors="strict")
    except UnicodeDecodeError:
        try:
            text = data.decode("gb18030", errors="strict")
        except UnicodeDecodeError:
            text = data.decode("latin-1", errors="strict")
    parsed = csv.reader(io.StringIO(text, newline=""))
    header = next(parsed, None)
    require(header is not None, "Legacy CSV header is missing")
    return header


def normalize_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    return str(value).split()


def column_names(table: dict[str, Any], identifiers: Any) -> list[str]:
    mapping = {str(column["id"]): str(column["source_name"]) for column in table["columns"]}
    return [mapping[item] for item in normalize_list(identifiers)]


def has_columns(header: list[str], names: list[str]) -> bool:
    folded = [ascii_fold(item) for item in header]
    return all(ascii_fold(name) in folded for name in names)


def legacy_manifest(legacy_root: Path) -> tuple[str, dict[str, list[str]]]:
    files = sorted(legacy_root.glob("*.csv"), key=lambda path: ascii_fold(path.stem))
    require(len(files) == 52, "Expected the frozen 52-file legacy CSV snapshot")
    lines = [f"{path.name}|{file_digest(path)}" for path in files]
    headers = {ascii_fold(path.stem): read_header(path) for path in files}
    return digest(lines), headers


def select_unique_manifest(matches: list[tuple[str, dict[str, list[str]]]]) -> tuple[str, dict[str, list[str]]]:
    require(len(matches) == 1, "Frozen legacy snapshot discovery did not yield one manifest-bound root")
    return matches[0]


def discover_legacy_snapshot(devdoc_root: Path, expected_manifest: str) -> tuple[str, dict[str, list[str]]]:
    require(devdoc_root.is_dir(), "Authorized legacy input root is unavailable")
    grouped: dict[Path, list[Path]] = {}
    for path in devdoc_root.rglob("*.csv"):
        if path.is_file():
            grouped.setdefault(path.parent, []).append(path)
    matches = []
    for candidate, files in grouped.items():
        if len(files) != 52:
            continue
        try:
            manifest, headers = legacy_manifest(candidate)
        except (OSError, UnicodeError, ValueError):
            continue
        if manifest == expected_manifest:
            matches.append((manifest, headers))
    return select_unique_manifest(matches)


def reference_members(registry: dict[str, Any], headers: dict[str, list[str]]) -> list[dict[str, Any]]:
    maps = {ascii_fold(Path(item["source_path"]).stem): item for item in registry["tables"]}
    identities = []
    for source_name, table in sorted(maps.items()):
        if source_name not in headers:
            continue
        for rule in table["foreign_keys"]:
            target_name = ascii_fold(Path(str(rule["target_table"])).stem)
            if target_name not in headers or target_name not in maps:
                continue
            source_columns = column_names(table, rule["source_column_ids"])
            target_columns = column_names(maps[target_name], rule["target_column_ids"])
            if not has_columns(headers[source_name], source_columns) or not has_columns(headers[target_name], target_columns):
                continue
            identities.append({
                "source": source_name,
                "source_columns": [ascii_fold(value) for value in source_columns],
                "target": target_name,
                "target_columns": [ascii_fold(value) for value in target_columns],
            })
    return sorted(identities, key=lambda item: digest(item))
