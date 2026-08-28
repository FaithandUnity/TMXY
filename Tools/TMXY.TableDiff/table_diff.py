#!/usr/bin/env python3
"""P2-09 hash-only legacy/current CSV differ without disclosing values."""

from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import io
import json
import re
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def file_digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def ascii_fold(value: str) -> str:
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in value)


def read_csv(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    encoding = "utf-8"
    try:
        text = data.decode("utf-8-sig", errors="strict")
    except UnicodeDecodeError:
        try:
            encoding = "gb18030"
            text = data.decode("gb18030", errors="strict")
        except UnicodeDecodeError:
            # Comma/newline structure remains ASCII and latin-1 is a reversible
            # byte mapping. Do not silently replace malformed legacy bytes.
            encoding = "byte-preserving-latin1"
            text = data.decode("latin-1", errors="strict")
    parsed = list(csv.reader(io.StringIO(text, newline="")))
    if not parsed:
        raise ValueError(f"empty CSV: {path}")
    header, rows = parsed[0], parsed[1:]
    while rows and not any(rows[-1]):
        rows.pop()
    return {"header": header, "rows": rows, "encoding": encoding, "bytes": len(data), "sha256": file_digest(path)}


def column_keys(header: list[str]) -> list[str]:
    counts: collections.Counter[str] = collections.Counter()
    result = []
    for name in header:
        folded = ascii_fold(name)
        counts[folded] += 1
        result.append(f"{folded}#{counts[folded]}")
    return result


INTEGER = re.compile(r"^[+-]?[0-9]+$")


def infer(values: list[str]) -> str:
    nonempty = [value for value in values if value != ""]
    if not nonempty:
        return "empty"
    if all(INTEGER.fullmatch(value) for value in nonempty):
        return "int64"
    try:
        for value in nonempty:
            Decimal(value)
        return "decimal"
    except InvalidOperation:
        return "string"


def column_stats(header: list[str], rows: list[list[str]]) -> dict[str, dict[str, Any]]:
    result = {}
    for index, key in enumerate(column_keys(header)):
        values = [row[index] if index < len(row) else "" for row in rows]
        counts = collections.Counter(values)
        mode_value, mode_count = min(counts.items(), key=lambda item: (-item[1], item[0])) if counts else ("", 0)
        result[key] = {
            "type": infer(values), "empty": counts.get("", 0),
            "mode_sha256": digest(mode_value), "mode_count": mode_count,
        }
    return result


def row_multiset(rows: list[list[str]]) -> collections.Counter[str]:
    return collections.Counter(digest(row) for row in rows)


def counter_diff(old: collections.Counter[str], new: collections.Counter[str]) -> tuple[int, int, int]:
    keys = set(old) | set(new)
    shared = sum(min(old[key], new[key]) for key in keys)
    return shared, sum((old - new).values()), sum((new - old).values())


def normalize_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    return str(value).split()


def registry_maps(registry: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {ascii_fold(Path(item["source_path"]).stem): item for item in registry["tables"]}


def column_names(table: dict[str, Any], ids: Any) -> list[str]:
    mapping = {str(column["id"]): str(column["source_name"]) for column in table["columns"]}
    return [mapping[item] for item in normalize_list(ids)]


def indexes(header: list[str], names: list[str]) -> list[int] | None:
    folded = [ascii_fold(item) for item in header]
    result = []
    for name in names:
        try:
            result.append(folded.index(ascii_fold(name)))
        except ValueError:
            return None
    return result


def key_counter(data: dict[str, Any], indices: list[int]) -> collections.Counter[tuple[str, ...]]:
    return collections.Counter(tuple(row[index] if index < len(row) else "" for index in indices) for row in data["rows"])


def foreign_key_summary(legacy: dict[str, dict[str, Any]], registry: dict[str, Any]) -> dict[str, int]:
    maps = registry_maps(registry)
    rules = active = dangling = current_active = current_dangling = changed = 0
    for source_name, table in maps.items():
        if source_name not in legacy:
            continue
        for rule in table["foreign_keys"]:
            target_name = ascii_fold(Path(str(rule["target_table"])).stem)
            if target_name not in legacy or target_name not in maps:
                continue
            source_indices = indexes(legacy[source_name]["header"], column_names(table, rule["source_column_ids"]))
            target_table = maps[target_name]
            target_indices = indexes(legacy[target_name]["header"], column_names(target_table, rule["target_column_ids"]))
            if source_indices is None or target_indices is None:
                continue
            target_keys = set(key_counter(legacy[target_name], target_indices))
            sentinels = set(normalize_list(rule.get("sentinel_values", [])))
            old_active = old_dangling = 0
            for row in legacy[source_name]["rows"]:
                key = tuple(row[index] if index < len(row) else "" for index in source_indices)
                if not any(key) or (len(key) == 1 and key[0] in sentinels):
                    continue
                old_active += 1
                old_dangling += int(key not in target_keys)
            rules += 1; active += old_active; dangling += old_dangling
            current_active += int(rule["active_rows"]); current_dangling += int(rule["dangling_rows"])
            changed += int(old_active != int(rule["active_rows"]) or old_dangling != int(rule["dangling_rows"]))
    return {"comparable_rules": rules, "legacy_active_references": active,
            "legacy_dangling_references": dangling, "current_active_references": current_active,
            "current_dangling_references": current_dangling, "changed_rules": changed}


def build(args: argparse.Namespace) -> dict[str, Any]:
    legacy_files = sorted(args.legacy.glob("*.csv"), key=lambda p: ascii_fold(p.stem))
    current_files = sorted(args.current.glob("CLSVShare/*/raw.csv"))
    current_paths = {ascii_fold(path.parent.name): path for path in current_files}
    legacy: dict[str, dict[str, Any]] = {}
    current: dict[str, dict[str, Any]] = {}
    for path in legacy_files:
        key = ascii_fold(path.stem)
        if key in legacy:
            raise ValueError(f"legacy basename collision: {path.stem}")
        legacy[key] = read_csv(path)
        legacy[key]["name"] = path.stem
    for key, path in current_paths.items():
        current[key] = read_csv(path)
    registry = json.loads(args.registry.read_text(encoding="utf-8"))
    regmaps = registry_maps(registry)

    report_stream = args.output.open("wb")
    report_sha = hashlib.sha256(); report_bytes = report_lines = 0
    totals = collections.Counter(); encodings = collections.Counter()
    try:
        for key, old in sorted(legacy.items()):
            new = current.get(key)
            if new is None:
                item = {"record": "table_diff", "table": old["name"], "state": "legacy-only"}
                totals["unpaired"] += 1
            else:
                old_columns = column_stats(old["header"], old["rows"])
                new_columns = column_stats(new["header"], new["rows"])
                shared_columns = set(old_columns) & set(new_columns)
                shared_rows, removed_rows, added_rows = counter_diff(row_multiset(old["rows"]), row_multiset(new["rows"]))
                types_changed = sum(old_columns[c]["type"] != new_columns[c]["type"] for c in shared_columns)
                modes_changed = sum(old_columns[c]["mode_sha256"] != new_columns[c]["mode_sha256"] for c in shared_columns)
                core = regmaps.get(key)
                key_summary = {"applicable": False}
                if core is not None:
                    names = column_names(core, core["primary_key"]["column_ids"])
                    old_indexes = indexes(old["header"], names); new_indexes = indexes(new["header"], names)
                    if old_indexes is not None and new_indexes is not None:
                        old_keys = key_counter(old, old_indexes); new_keys = key_counter(new, new_indexes)
                        key_summary = {"applicable": True, "legacy_unique_keys": len(old_keys),
                            "current_unique_keys": len(new_keys), "shared_keys": len(set(old_keys) & set(new_keys)),
                            "legacy_only_keys": len(set(old_keys) - set(new_keys)),
                            "current_only_keys": len(set(new_keys) - set(old_keys)),
                            "legacy_duplicate_keys": sum(v > 1 for v in old_keys.values()),
                            "current_duplicate_keys": sum(v > 1 for v in new_keys.values())}
                        totals["core_key_tables"] += 1
                item = {"record": "table_diff", "table": old["name"], "state": "paired",
                    "legacy": {"bytes": old["bytes"], "rows": len(old["rows"]), "columns": len(old["header"]),
                        "encoding": old["encoding"], "sha256": old["sha256"], "header_sha256": digest(old["header"])},
                    "current": {"bytes": new["bytes"], "rows": len(new["rows"]), "columns": len(new["header"]),
                        "encoding": new["encoding"], "sha256": new["sha256"], "header_sha256": digest(new["header"])},
                    "schema": {"header_equal": old["header"] == new["header"], "shared_columns": len(shared_columns),
                        "legacy_only_columns": len(set(old_columns) - set(new_columns)),
                        "current_only_columns": len(set(new_columns) - set(old_columns)),
                        "inferred_type_changes": types_changed, "observed_mode_hash_changes": modes_changed},
                    "rows": {"shared_exact": shared_rows, "legacy_only": removed_rows, "current_only": added_rows},
                    "primary_key": key_summary}
                totals["paired"] += 1; totals["legacy_rows"] += len(old["rows"]); totals["current_rows"] += len(new["rows"])
                totals["shared_exact_rows"] += shared_rows; totals["legacy_only_rows"] += removed_rows; totals["current_only_rows"] += added_rows
                totals["shared_columns"] += len(shared_columns); totals["legacy_only_columns"] += len(set(old_columns)-set(new_columns))
                totals["current_only_columns"] += len(set(new_columns)-set(old_columns)); totals["type_changes"] += types_changed
                totals["mode_changes"] += modes_changed; totals["equal_headers"] += int(old["header"] == new["header"])
            encodings[old["encoding"]] += 1
            data = canonical(item) + b"\n"; report_stream.write(data); report_sha.update(data)
            report_bytes += len(data); report_lines += 1
    finally:
        report_stream.close()
    manifest_lines = [f"{path.name}|{file_digest(path)}" for path in legacy_files]
    references = foreign_key_summary(legacy, registry)
    return {"result": "PASS", "report": {"lines": report_lines, "bytes": report_bytes, "sha256": report_sha.hexdigest()},
        "summary": {"legacy_tables": len(legacy), "current_active_tables": len(current), "paired_tables": totals["paired"],
            "unpaired_legacy_tables": totals["unpaired"], "legacy_bytes": sum(item["bytes"] for item in legacy.values()),
            "legacy_encodings": dict(sorted(encodings.items())), "equal_headers": totals["equal_headers"],
            "columns": {"shared": totals["shared_columns"], "legacy_only": totals["legacy_only_columns"],
                "current_only": totals["current_only_columns"], "inferred_type_changes": totals["type_changes"],
                "observed_mode_hash_changes": totals["mode_changes"]},
            "rows": {"legacy": totals["legacy_rows"], "current": totals["current_rows"],
                "shared_exact": totals["shared_exact_rows"], "legacy_only": totals["legacy_only_rows"],
                "current_only": totals["current_only_rows"]}, "core_primary_key_tables": totals["core_key_tables"],
            "references": references, "legacy_build_known": False, "authoritative_default_claims": 0},
        "inputs": {"legacy_manifest_sha256": digest(manifest_lines), "core_registry_sha256": file_digest(args.registry)}}


def self_test() -> int:
    a = collections.Counter({"a": 2, "b": 1}); b = collections.Counter({"a": 1, "c": 3})
    shared, old, new = counter_diff(a, b)
    assertions = int(shared == 1) + int(old == 2) + int(new == 3)
    assertions += int(infer(["1", "-2"]) == "int64") + int(infer(["1.5", "2"]) == "decimal")
    print(json.dumps({"assertions": assertions, "result": "PASS" if assertions == 5 else "FAIL"}, separators=(",", ":")))
    return 0 if assertions == 5 else 1


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--legacy", type=Path); parser.add_argument("--current", type=Path)
    parser.add_argument("--registry", type=Path); parser.add_argument("--output", type=Path); parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test: return self_test()
    if any(value is None for value in (args.legacy, args.current, args.registry, args.output)): parser.error("all inputs required")
    args.output.parent.mkdir(parents=True, exist_ok=True); print(json.dumps(build(args), ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__": raise SystemExit(main())
