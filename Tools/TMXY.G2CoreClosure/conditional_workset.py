"""Deterministic redacted member workset for conditionally required gaps."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any

from core_common import canonical_json, require, sha256_file, sha256_lines, write_text


REASON = "missing-required-value"
FIELDS = {"member_sha256", "rule_id", "reason"}


def stable_id(namespace: str, *parts: str) -> str:
    payload = namespace + "\0" + "\0".join(parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def typed_key(values: list[Any]) -> str:
    return canonical_json(values)


def condition_matches(row: dict[str, Any], condition: dict[str, Any]) -> bool:
    require(condition["operator"] == "greater-than", "Unsupported runtime condition")
    actual = row.get(str(condition["column_id"]))
    return actual is not None and float(actual) > float(condition["value"])


def normalized_relative(source_path: str) -> str:
    source = PurePosixPath(source_path)
    return str(PurePosixPath("tables") / source.with_suffix("") / "normalized.jsonl")


def find_normalized_metadata(p206: dict[str, Any], source_path: str) -> dict[str, Any]:
    table = next((item for item in p206["tables"] if item["source_path"] == source_path), None)
    require(table is not None and table["generated"] is True, "Conditional source table is absent")
    relative = normalized_relative(source_path)
    item = next((entry for entry in table["files"] if entry["path"] == relative and
                 entry["kind"] == "normalized"), None)
    require(item is not None, "Conditional normalized source metadata is absent")
    return item


def build_conditional_workset(policy: dict[str, Any], reference_policy: dict[str, Any],
                              p206: dict[str, Any], p213: dict[str, Any],
                              core_registry: dict[str, Any], table_root: Path,
                              output: Path) -> dict[str, Any]:
    rules = [item for item in reference_policy["table_object_references"]
             if item.get("runtime_assert_when") is not None]
    require(len(rules) == policy["conditional_required_scope"]["required_rule_count"],
            "Conditional-required rule authority changed")
    tables = {item["source_path"]: item for item in core_registry["tables"]}
    records: list[dict[str, str]] = []
    source_hashes: list[str] = []
    asserting_rows = 0

    for rule in sorted(rules, key=lambda item: item["id"]):
        source_path = str(rule["table"])
        metadata = find_normalized_metadata(p206, source_path)
        relative = normalized_relative(source_path)
        path = (table_root / PurePosixPath(relative).relative_to("tables")).resolve()
        require(path.is_relative_to(table_root.resolve()) and path.is_file(),
                "Conditional normalized source is unavailable")
        require(sha256_file(path) == metadata["sha256"] and
                path.stat().st_size == metadata["bytes"],
                "Conditional normalized source hash binding failed")
        source_hashes.append(str(metadata["sha256"]))
        registry = tables.get(source_path)
        require(registry is not None and registry["primary_key"]["result"] == "PASS",
                "Conditional source has no qualified primary key")
        primary = [str(item) for item in registry["primary_key"]["column_ids"]]
        sentinels = {str(item) for item in rule["sentinel_values"]}
        with path.open("r", encoding="utf-8", newline="") as stream:
            for line in stream:
                row = json.loads(line)
                if not condition_matches(row, rule["runtime_assert_when"]):
                    continue
                asserting_rows += 1
                value = row.get(str(rule["column_id"]))
                text = "" if value is None else str(value).strip()
                if text and text not in sentinels:
                    continue
                row_hash = stable_id("table-row", source_path,
                                     typed_key([row.get(item) for item in primary]))
                records.append({
                    "member_sha256": stable_id("conditional-required", str(rule["id"]), row_hash),
                    "rule_id": str(rule["id"]),
                    "reason": REASON,
                })

    lines = sorted(canonical_json(item) for item in records)
    require(all(set(item) == FIELDS for item in records), "Workset disclosure fields changed")
    require(len({item["member_sha256"] for item in records}) == len(records),
            "Conditional-required member set contains duplicates")
    expected = p213["table_closure"]["object_references"]
    require(asserting_rows == expected["runtime_assert_rows"] and
            len(records) == expected["runtime_assert_missing_values"],
            "Conditional-required member reconstruction disagrees with P2-13")
    write_text(output, "\n".join(lines) + "\n")
    return {
        "runtime_assert_rows": asserting_rows,
        "conditional_required_missing": len(records),
        "member_source_file_count": len(source_hashes),
        "member_source_file_set_sha256": sha256_lines(source_hashes),
        "member_set_exported": True,
        "member_set_count": len(records),
        "member_set_sha256": sha256_lines(lines),
    }
