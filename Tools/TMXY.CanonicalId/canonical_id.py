#!/usr/bin/env python3
"""Build the P2-10 typed, namespaced Canonical ID map."""

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


INTEGER = re.compile(r"^[+-]?[0-9]+$")


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
    return "".join(chr(ord(char) + 32) if "A" <= char <= "Z" else char for char in value)


def read_csv(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    try:
        text = data.decode("utf-8-sig", errors="strict")
    except UnicodeDecodeError:
        try:
            text = data.decode("gb18030", errors="strict")
        except UnicodeDecodeError:
            text = data.decode("latin-1", errors="strict")
    first_line = text.splitlines()[0] if text else ""
    if "," in first_line:
        delimiter = ","
    elif "*" in first_line:
        delimiter = "*"
    else:
        delimiter = ","
    parsed = list(csv.reader(io.StringIO(text, newline=""), delimiter=delimiter))
    if not parsed:
        raise ValueError(f"empty CSV: {path}")
    rows = parsed[1:]
    while rows and not any(rows[-1]):
        rows.pop()
    return {"header": parsed[0], "rows": rows}


def normalize_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    return str(value).split()


def column_names(table: dict[str, Any], ids: Any) -> list[str]:
    mapping = {str(column["id"]): str(column["source_name"]) for column in table["columns"]}
    return [mapping[item] for item in normalize_list(ids)]


def column_types(table: dict[str, Any], ids: Any) -> list[str]:
    mapping = {str(column["id"]): str(column["type"]) for column in table["columns"]}
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


TypedComponent = tuple[str, int | str]
TypedKey = tuple[TypedComponent, ...]


def typed_value(value: str, value_type: str, legacy_fallback: bool = False) -> TypedComponent:
    if value_type == "int64":
        if not INTEGER.fullmatch(value):
            if legacy_fallback:
                return ("legacy-opaque", value)
            raise ValueError("non-integer primary-key component")
        parsed = int(value)
        if parsed < -(2**63) or parsed > 2**63 - 1:
            if legacy_fallback:
                return ("legacy-opaque", value)
            raise ValueError("primary-key component exceeds int64")
        return ("int64", parsed)
    if value_type == "decimal":
        try:
            parsed = Decimal(value)
        except InvalidOperation as error:
            if legacy_fallback:
                return ("legacy-opaque", value)
            raise ValueError("invalid decimal primary-key component") from error
        return ("decimal", format(parsed.normalize(), "f"))
    if value_type == "string":
        return ("string", value)
    raise ValueError(f"unsupported primary-key type: {value_type}")


def typed_rows(
    data: dict[str, Any], indices: list[int], types: list[str], legacy_fallback: bool = False
) -> tuple[dict[TypedKey, list[str]], int]:
    result: dict[TypedKey, list[str]] = collections.defaultdict(list)
    exceptions = 0
    for row in data["rows"]:
        key = tuple(
            typed_value(
                row[index] if index < len(row) else "", value_type, legacy_fallback
            )
            for index, value_type in zip(indices, types, strict=True)
        )
        exceptions += sum(component[0] == "legacy-opaque" for component in key)
        result[key].append(digest(row))
    return result, exceptions


def wire_key(key: TypedKey) -> list[dict[str, int | str]]:
    return [{"type": component[0], "value": component[1]} for component in key]


def key_sort(key: TypedKey) -> bytes:
    return canonical(wire_key(key))


def domain_map(
    table: dict[str, Any], legacy: dict[str, Any] | None, current: dict[str, Any]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    ids = normalize_list(table["primary_key"]["column_ids"])
    names = column_names(table, ids)
    types = column_types(table, ids)
    current_indices = indexes(current["header"], names)
    if current_indices is None:
        raise ValueError(f"current primary-key columns missing: {table['logical_name']}")
    current_rows, current_exceptions = typed_rows(current, current_indices, types)
    if current_exceptions:
        raise ValueError(f"current key type exception: {table['logical_name']}")
    legacy_rows: dict[TypedKey, list[str]] = {}
    legacy_exceptions = 0
    if legacy is not None:
        legacy_indices = indexes(legacy["header"], names)
        if legacy_indices is None:
            raise ValueError(f"legacy primary-key columns missing: {table['logical_name']}")
        legacy_rows, legacy_exceptions = typed_rows(
            legacy, legacy_indices, types, legacy_fallback=True
        )

    collapsed_groups = collapsed_occurrences = conflicts = 0
    duplicate_policy = str(table["primary_key"]["duplicate_policy"])
    for rows in current_rows.values():
        if len(rows) <= 1:
            continue
        if duplicate_policy == "collapse-identical-rows" and len(set(rows)) == 1:
            collapsed_groups += 1
            collapsed_occurrences += len(rows) - 1
        else:
            conflicts += 1
    conflicts += sum(len(rows) > 1 for rows in legacy_rows.values())

    old_keys = set(legacy_rows)
    new_keys = set(current_rows)
    records = []
    actions: collections.Counter[str] = collections.Counter()
    for key in sorted(old_keys | new_keys, key=key_sort):
        old = key in old_keys
        new = key in new_keys
        if old and new:
            action, status = "preserve_shared", "active"
        elif new:
            action, status = "adopt_current", "active"
        else:
            action, status = "preserve_legacy_tombstone", "tombstone"
        actions[action] += 1
        records.append(
            {
                "action": action,
                "canonical_id": wire_key(key),
                "canonical_id_sha256": digest(
                    {
                        "namespace": ascii_fold(str(table["logical_name"])),
                        "key": wire_key(key),
                    }
                ),
                "current_present": new,
                "domain": str(table["logical_name"]),
                "legacy_present": old,
                "record": "canonical_id_mapping",
                "status": status,
            }
        )
    summary = {
        "actions": dict(sorted(actions.items())),
        "active": len(new_keys),
        "collapsed_duplicate_groups": collapsed_groups,
        "collapsed_duplicate_occurrences": collapsed_occurrences,
        "conflicts": conflicts,
        "current_physical_rows": len(current["rows"]),
        "current_unique_ids": len(new_keys),
        "domain": str(table["logical_name"]),
        "key_arity": len(ids),
        "key_column_ids": ids,
        "key_types": types,
        "legacy_snapshot_present": legacy is not None,
        "legacy_type_exception_components": legacy_exceptions,
        "legacy_unique_ids": len(old_keys),
        "mappings": len(old_keys | new_keys),
        "shared_ids": len(old_keys & new_keys),
        "tombstones": len(old_keys - new_keys),
    }
    return records, summary


def build(args: argparse.Namespace) -> dict[str, Any]:
    registry = json.loads(args.registry.read_text(encoding="utf-8"))
    legacy_paths = sorted(args.legacy.glob("*.csv"), key=lambda path: ascii_fold(path.stem))
    current_paths = sorted(args.current.glob("CLSVShare/*/raw.csv")) + sorted(
        args.current.glob("Table/*/raw.csv")
    )
    legacy = {ascii_fold(path.stem): read_csv(path) for path in legacy_paths}
    current = {ascii_fold(path.parent.name): read_csv(path) for path in current_paths}

    report_hash = hashlib.sha256()
    report_bytes = report_lines = 0
    domains = []
    totals: collections.Counter[str] = collections.Counter()
    with args.output.open("wb") as stream:
        for table in sorted(registry["tables"], key=lambda item: ascii_fold(item["logical_name"])):
            name = ascii_fold(Path(str(table["source_path"])).stem)
            if name not in current:
                raise ValueError(f"current core table missing: {table['logical_name']}")
            records, domain = domain_map(table, legacy.get(name), current[name])
            domains.append(domain)
            for item in records:
                encoded = canonical(item) + b"\n"
                stream.write(encoded)
                report_hash.update(encoded)
                report_bytes += len(encoded)
                report_lines += 1
            totals.update(
                {
                    "active": domain["active"],
                    "collapsed_duplicate_groups": domain["collapsed_duplicate_groups"],
                    "collapsed_duplicate_occurrences": domain["collapsed_duplicate_occurrences"],
                    "conflicts": domain["conflicts"],
                    "current_physical_rows": domain["current_physical_rows"],
                    "current_unique_ids": domain["current_unique_ids"],
                    "legacy_unique_ids": domain["legacy_unique_ids"],
                    "legacy_type_exception_components": domain[
                        "legacy_type_exception_components"
                    ],
                    "mappings": domain["mappings"],
                    "shared_ids": domain["shared_ids"],
                    "tombstones": domain["tombstones"],
                    "legacy_domains": int(domain["legacy_snapshot_present"]),
                }
            )
            totals.update(domain["actions"])

    legacy_manifest = [f"{path.name}|{file_digest(path)}" for path in legacy_paths]
    current_manifest = [
        f"{path.parent.parent.name}/{path.parent.name}|{file_digest(path)}" for path in current_paths
    ]
    return {
        "result": "PASS" if totals["conflicts"] == 0 else "FAIL",
        "report": {"bytes": report_bytes, "lines": report_lines, "sha256": report_hash.hexdigest()},
        "summary": {
            "active_ids": totals["active"],
            "automatic_renumberings": 0,
            "collapsed_duplicate_groups": totals["collapsed_duplicate_groups"],
            "collapsed_duplicate_occurrences": totals["collapsed_duplicate_occurrences"],
            "comparable_legacy_domains": totals["legacy_domains"],
            "conflicts": totals["conflicts"],
            "current_only_ids": totals["adopt_current"],
            "current_physical_rows": totals["current_physical_rows"],
            "current_unique_ids": totals["current_unique_ids"],
            "domain_count": len(domains),
            "explicit_remaps": 0,
            "legacy_preserved_ids": totals["legacy_unique_ids"],
            "legacy_type_exception_components": totals["legacy_type_exception_components"],
            "legacy_unique_ids": totals["legacy_unique_ids"],
            "mapping_records": totals["mappings"],
            "shared_ids": totals["shared_ids"],
            "tombstones": totals["tombstones"],
            "unresolved_conflicts": totals["conflicts"],
        },
        "domains": domains,
        "inputs": {
            "current_manifest_sha256": digest(current_manifest),
            "legacy_manifest_sha256": digest(legacy_manifest),
            "registry_sha256": file_digest(args.registry),
        },
    }


def self_test() -> int:
    assertions = 0
    assertions += int(typed_value("001", "int64") == ("int64", 1))
    assertions += int(typed_value("abc", "string") == ("string", "abc"))
    assertions += int(ascii_fold("AbZ") == "abz")
    assertions += int(list(csv.reader(["a*b"], delimiter="*"))[0] == ["a", "b"])
    assertions += int(digest({"b": 2, "a": 1}) == digest({"a": 1, "b": 2}))
    assertions += int(
        key_sort((("int64", 2),)) > key_sort((("int64", 1),))
    )
    try:
        typed_value("1.5", "int64")
        rejected = False
    except ValueError:
        rejected = True
    assertions += int(rejected)
    assertions += int(typed_value("1.5", "int64", True) == ("legacy-opaque", "1.5"))
    print(json.dumps({"assertions": assertions, "result": "PASS" if assertions == 8 else "FAIL"}))
    return 0 if assertions == 8 else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--legacy", type=Path)
    parser.add_argument("--current", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if any(value is None for value in (args.legacy, args.current, args.registry, args.output)):
        parser.error("all inputs required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(json.dumps(build(args), ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
