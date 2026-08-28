"""Shared deterministic primitives for the P2-13 reference-closure builder."""

from __future__ import annotations

import collections
import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def ascii_lower(value: bytes) -> bytes:
    return bytes(item + 32 if 65 <= item <= 90 else item for item in value)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def encoded_line(value: dict[str, Any]) -> bytes:
    return (canonical_json(value) + "\n").encode("utf-8")


def typed_key(values: Iterable[Any]) -> str:
    return canonical_json(list(values))


def stable_id(namespace: str, *parts: str) -> str:
    return sha256_bytes((namespace + "\0" + "\0".join(parts)).encode("utf-8"))


def candidate_ascii_lower_hashes(value: str) -> list[str]:
    hashes: set[str] = set()
    for encoding in ("utf-8", "gb18030"):
        try:
            hashes.add(sha256_bytes(ascii_lower(value.encode(encoding))))
        except UnicodeEncodeError:
            continue
    return sorted(hashes)


class GraphWriter:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.stream = path.open("wb")
        self.digest = hashlib.sha256()
        self.bytes = 0
        self.lines = 0
        self.records: collections.Counter[str] = collections.Counter()

    def emit(self, value: dict[str, Any]) -> None:
        data = encoded_line(value)
        self.stream.write(data)
        self.digest.update(data)
        self.bytes += len(data)
        self.lines += 1
        self.records[str(value["record"])] += 1

    def close(self) -> dict[str, Any]:
        self.stream.close()
        return {
            "bytes": self.bytes,
            "lines": self.lines,
            "sha256": self.digest.hexdigest(),
            "records": dict(sorted(self.records.items())),
        }


def iter_json_lines(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        for line in stream:
            if line.strip():
                yield json.loads(line)


def table_export_path(table_root: Path, source_path: str) -> Path:
    source = PurePosixPath(source_path)
    return table_root.joinpath(*source.with_suffix("").parts, "normalized.jsonl")


def row_id(source_path: str, row: dict[str, Any], key_columns: list[str]) -> str:
    return stable_id("table-row", source_path, typed_key(row.get(item) for item in key_columns))


def is_inactive(values: list[Any], sentinels: list[Any]) -> bool:
    for value in values:
        if value is None:
            continue
        if not any(value == sentinel for sentinel in sentinels):
            return False
    return True


def condition_matches(row: dict[str, Any], condition: dict[str, Any] | None) -> bool:
    if condition is None:
        return False
    actual = row.get(str(condition["column_id"]))
    if condition["operator"] == "greater-than":
        return actual is not None and float(actual) > float(condition["value"])
    raise ValueError("unsupported runtime assertion operator")


def load_package_nodes(
    graph_path: Path, writer: GraphWriter
) -> tuple[
    list[dict[str, Any]],
    dict[str, list[dict[str, Any]]],
    dict[str, list[dict[str, Any]]],
]:
    nodes: list[dict[str, Any]] = []
    by_lower: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    by_package_basename: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for entry in iter_json_lines(graph_path):
        if entry["record"] != "node":
            break
        node = {
            "id": str(entry["id"]),
            "class": str(entry["class"]),
            "category": str(entry["category"]),
            "package": str(entry["package"]),
            "logical_name_sha256": str(entry["logical_name_sha256"]),
            "logical_name_ascii_lower_sha256": str(
                entry["logical_name_ascii_lower_sha256"]
            ),
        }
        nodes.append(node)
        by_lower[node["logical_name_ascii_lower_sha256"]].append(node)
        basename = PurePosixPath(node["package"]).name.lower()
        by_package_basename[basename].append(node)
        writer.emit(
            {
                "category": node["category"],
                "class": node["class"],
                "id": node["id"],
                "logical_name_ascii_lower_sha256": node[
                    "logical_name_ascii_lower_sha256"
                ],
                "logical_name_sha256": node["logical_name_sha256"],
                "package": node["package"],
                "record": "package_node",
            }
        )
    for values in by_lower.values():
        values.sort(key=lambda item: item["id"])
    for values in by_package_basename.values():
        values.sort(key=lambda item: item["id"])
    return nodes, by_lower, by_package_basename


def load_table_indexes(
    registry: dict[str, Any], table_root: Path, writer: GraphWriter
) -> tuple[dict[str, Any], dict[str, list[str]], dict[str, int]]:
    tables = {str(item["source_path"]): item for item in registry["tables"]}
    target_signatures: dict[str, set[tuple[str, ...]]] = collections.defaultdict(set)
    for table in registry["tables"]:
        primary = tuple(str(value) for value in table["primary_key"]["column_ids"])
        target_signatures[str(table["source_path"])].add(primary)
    for source_table in registry["tables"]:
        for foreign_key in source_table["foreign_keys"]:
            target_signatures[str(foreign_key["target_table"])].add(
                tuple(str(value) for value in foreign_key["target_column_ids"])
            )

    indexes: dict[tuple[str, tuple[str, ...]], dict[str, str]] = {}
    domain_members: dict[str, set[str]] = collections.defaultdict(set)
    ids_by_role: dict[str, list[str]] = collections.defaultdict(list)
    counts = {"physical_rows": 0, "canonical_rows": 0, "domain_nodes": 0}
    normalized_hashes: dict[str, str] = {}

    for source_path, table in tables.items():
        path = table_export_path(table_root, source_path)
        actual_hash = sha256_bytes(path.read_bytes())
        if actual_hash != str(table["normalized_sha256"]):
            raise ValueError(f"normalized table hash mismatch: {source_path}")
        normalized_hashes[source_path] = actual_hash
        primary = [str(value) for value in table["primary_key"]["column_ids"]]
        signatures = sorted(target_signatures[source_path])
        for signature in signatures:
            indexes[(source_path, signature)] = {}
        seen: set[str] = set()
        role = str(table["role"])
        for row in iter_json_lines(path):
            counts["physical_rows"] += 1
            identity = row_id(source_path, row, primary)
            if identity in seen:
                continue
            seen.add(identity)
            counts["canonical_rows"] += 1
            ids_by_role[role].append(identity)
            writer.emit(
                {
                    "id": identity,
                    "record": "table_node",
                    "role": role,
                    "table": source_path,
                }
            )
            for signature in signatures:
                key = typed_key(row.get(column) for column in signature)
                if list(signature) == primary:
                    target_id = identity
                else:
                    target_id = stable_id(
                        "table-domain", source_path, ",".join(signature), key
                    )
                    domain_members[target_id].add(identity)
                indexes[(source_path, signature)][key] = target_id
        if len(seen) != int(table["canonical_rows"]):
            raise ValueError(f"canonical row count mismatch: {source_path}")

    for domain_id in sorted(domain_members):
        counts["domain_nodes"] += 1
        writer.emit({"id": domain_id, "record": "table_domain_node"})
        for member in sorted(domain_members[domain_id]):
            writer.emit(
                {
                    "record": "table_domain_edge",
                    "source": domain_id,
                    "target": member,
                }
            )
    state = {
        "tables": tables,
        "indexes": indexes,
        "normalized_hashes": normalized_hashes,
    }
    for values in ids_by_role.values():
        values.sort()
    return state, ids_by_role, counts
