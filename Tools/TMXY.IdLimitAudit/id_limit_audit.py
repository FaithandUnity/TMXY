#!/usr/bin/env python3
"""P2-11 Canonical ID width, sparsity, and legacy fixed-limit audit."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SOURCE_EXTENSIONS = {
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx",
    ".cs", ".java", ".py", ".lua", ".xml", ".ini", ".cfg",
}
SIGNALS = {
    "level_limit_symbol": re.compile(rb"\b(?:max_?level|level_?max|maxlevel)\b", re.I),
    "slot_limit_symbol": re.compile(rb"\b(?:max_?slots?|slot_?(?:count|max)|maxslot)\b", re.I),
    "u16_boundary": re.compile(rb"(?<![0-9A-Za-z_])(?:65535|65536|0[xX][fF]{4})(?![0-9A-Za-z_])"),
    "u8_boundary": re.compile(rb"(?<![0-9A-Za-z_])(?:255|256|0[xX][fF]{2})(?![0-9A-Za-z_])"),
}
LEVEL_COMPONENTS = {
    ("clsvshare/levelinfo", "c0001"),
    ("clsvshare/profession_lvl", "c0002"),
    ("clsvshare/skill_table", "c0004"),
}
RISK_NAMES = {
    "legacy_type_exception", "level_cap_saturated", "sparse_lt_10pct",
    "string_identifier", "tombstone_reserved", "u16_near_limit",
    "u16_overflow", "u16_saturated", "u8_overflow",
}


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


def required_bits(minimum: int, maximum: int) -> tuple[str, int]:
    if minimum >= 0:
        return "unsigned", max(1, maximum.bit_length())
    magnitude = max(abs(minimum), abs(maximum))
    return "signed", max(2, magnitude.bit_length() + 1)


def density_band(distinct: int, span: int) -> str:
    ratio = distinct / span if span else 1.0
    if ratio < 0.01:
        return "lt-1pct"
    if ratio < 0.1:
        return "1-to-10pct"
    if ratio < 0.5:
        return "10-to-50pct"
    return "gte-50pct"


def component_audits(map_path: Path, evidence: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    metadata: dict[tuple[str, int], dict[str, Any]] = {}
    for domain in evidence["domains"]:
        for index, (column_id, value_type) in enumerate(
            zip(domain["key_column_ids"], domain["key_types"], strict=True)
        ):
            metadata[(str(domain["domain"]), index)] = {
                "column_id": str(column_id), "type": str(value_type)
            }
    values: dict[tuple[str, int], dict[str, Any]] = {
        key: {"active": set(), "reserved": set(), "tombstones": 0, "opaque": 0}
        for key in metadata
    }
    with map_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            domain = str(record["domain"])
            for index, component in enumerate(record["canonical_id"]):
                bucket = values[(domain, index)]
                component_type = str(component["type"])
                if component_type == "legacy-opaque":
                    bucket["opaque"] += 1
                    continue
                value = component["value"]
                bucket["reserved"].add(value)
                if record["status"] == "active":
                    bucket["active"].add(value)
                else:
                    bucket["tombstones"] += 1

    full = []
    tracked = []
    for (domain, index), item in sorted(metadata.items()):
        bucket = values[(domain, index)]
        risks = []
        audit: dict[str, Any] = {
            "record": "id_component_audit",
            "domain": domain,
            "column_id": item["column_id"],
            "component_index": index,
            "type": item["type"],
            "active_distinct": len(bucket["active"]),
            "reserved_distinct": len(bucket["reserved"]),
            "tombstone_records": bucket["tombstones"],
            "legacy_opaque_records": bucket["opaque"],
        }
        if item["type"] == "int64":
            active = sorted(int(value) for value in bucket["active"])
            reserved = sorted(int(value) for value in bucket["reserved"])
            minimum, maximum = active[0], active[-1]
            reserved_minimum, reserved_maximum = reserved[0], reserved[-1]
            sign, bits = required_bits(minimum, maximum)
            span = maximum - minimum + 1
            band = density_band(len(active), span)
            risks.extend(["u8_overflow"] if maximum >= 256 else [])
            risks.extend(["u16_overflow"] if maximum >= 65536 else [])
            risks.extend(["u16_saturated"] if maximum == 65535 else [])
            risks.extend(["u16_near_limit"] if 58982 <= maximum < 65535 else [])
            risks.extend(["sparse_lt_10pct"] if len(active) / span < 0.1 else [])
            if (ascii_fold(domain), item["column_id"]) in LEVEL_COMPONENTS and maximum >= 100:
                risks.append("level_cap_saturated")
            audit.update({
                "active_minimum": minimum, "active_maximum": maximum,
                "reserved_minimum": reserved_minimum, "reserved_maximum": reserved_maximum,
                "required_sign": sign, "required_bits": bits, "active_span": span,
                "active_density_numerator": len(active), "active_density_denominator": span,
                "density_band": band,
            })
            safe = {
                "required_sign": sign, "required_bits": bits, "density_band": band
            }
        else:
            lengths = sorted(len(str(value).encode("utf-8")) for value in bucket["active"])
            audit.update({
                "active_minimum_utf8_bytes": lengths[0],
                "active_maximum_utf8_bytes": lengths[-1],
            })
            risks.append("string_identifier")
            safe = {"required_sign": "not-numeric", "required_bits": None, "density_band": "not-numeric"}
        if bucket["opaque"]:
            risks.append("legacy_type_exception")
        if bucket["tombstones"]:
            risks.append("tombstone_reserved")
        audit["risks"] = sorted(set(risks))
        full.append(audit)
        tracked.append({
            "domain": domain, "column_id": item["column_id"], "component_index": index,
            "type": item["type"], "active_distinct": len(bucket["active"]),
            "reserved_distinct": len(bucket["reserved"]),
            "tombstone_records": bucket["tombstones"],
            "legacy_opaque_records": bucket["opaque"], "risks": audit["risks"], **safe,
        })
    return full, tracked


def source_scan(roots: list[tuple[str, Path]]) -> tuple[list[dict[str, Any]], dict[str, Any], str]:
    records = []
    per_rule: collections.Counter[str] = collections.Counter()
    matched_files: collections.Counter[str] = collections.Counter()
    source_files: collections.Counter[str] = collections.Counter()
    manifest = []
    for root_name, root in roots:
        paths = sorted(
            (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in SOURCE_EXTENSIONS),
            key=lambda path: path.as_posix().lower(),
        )
        source_files[root_name] = len(paths)
        for path in paths:
            relative = path.relative_to(root).as_posix()
            sha = file_digest(path)
            manifest.append(f"{root_name}/{relative}|{sha}")
            data = path.read_bytes()
            for rule, pattern in SIGNALS.items():
                hits = len(pattern.findall(data))
                if not hits:
                    continue
                per_rule[rule] += hits
                matched_files[rule] += 1
                records.append({
                    "record": "legacy_source_limit_signal", "root": root_name,
                    "relative_path": relative, "source_sha256": sha, "rule": rule,
                    "hit_count": hits,
                })
    summary = {
        "rules": {
            rule: {"files": matched_files[rule], "hits": per_rule[rule]}
            for rule in sorted(SIGNALS)
        },
        "source_files": dict(sorted(source_files.items())),
        "total_source_files": sum(source_files.values()),
        "total_signal_records": len(records),
        "total_signal_hits": sum(per_rule.values()),
    }
    return records, summary, digest(manifest)


def build(args: argparse.Namespace) -> dict[str, Any]:
    evidence = json.loads(args.canonical_evidence.read_text(encoding="utf-8"))
    components, tracked = component_audits(args.canonical_map, evidence)
    roots = [
        ("legacy-client", args.client),
        ("legacy-server", args.server),
        ("legacy-tool", args.tool),
    ]
    signals, signal_summary, source_manifest = source_scan(roots)
    records = components + sorted(
        signals, key=lambda item: (item["rule"], item["root"], item["relative_path"].lower())
    )
    output_hash = hashlib.sha256()
    output_bytes = 0
    with args.output.open("wb") as stream:
        for record in records:
            encoded = canonical(record) + b"\n"
            stream.write(encoded)
            output_hash.update(encoded)
            output_bytes += len(encoded)
    risks: collections.Counter[str] = collections.Counter()
    bit_buckets: collections.Counter[str] = collections.Counter()
    for component in tracked:
        risks.update(component["risks"])
        bits = component["required_bits"]
        if bits is None:
            bit_buckets["non_numeric"] += 1
        elif bits <= 8:
            bit_buckets["lte_8"] += 1
        elif bits <= 16:
            bit_buckets["lte_16"] += 1
        elif bits <= 32:
            bit_buckets["lte_32"] += 1
        else:
            bit_buckets["gt_32"] += 1
    risk_counts = {name: risks[name] for name in sorted(RISK_NAMES)}
    return {
        "result": "PASS" if risks["u16_overflow"] == 0 else "FAIL",
        "report": {"lines": len(records), "bytes": output_bytes, "sha256": output_hash.hexdigest()},
        "summary": {
            "bit_width_buckets": dict(sorted(bit_buckets.items())),
            "component_count": len(tracked),
            "domain_count": evidence["summary"]["domain_count"],
            "numeric_components": sum(item["type"] == "int64" for item in tracked),
            "risk_counts": risk_counts,
            "string_components": sum(item["type"] == "string" for item in tracked),
        },
        "components": tracked,
        "source_signals": signal_summary,
        "inputs": {
            "canonical_map_sha256": file_digest(args.canonical_map),
            "canonical_evidence_sha256": file_digest(args.canonical_evidence),
            "legacy_source_manifest_sha256": source_manifest,
        },
    }


def self_test() -> int:
    assertions = 0
    assertions += int(required_bits(0, 255) == ("unsigned", 8))
    assertions += int(required_bits(0, 65535) == ("unsigned", 16))
    assertions += int(required_bits(-1, 1) == ("signed", 2))
    assertions += int(density_band(1, 1000) == "lt-1pct")
    assertions += int(bool(SIGNALS["u16_boundary"].search(b"65536")))
    assertions += int(bool(SIGNALS["level_limit_symbol"].search(b"MAX_LEVEL")))
    assertions += int(not SIGNALS["slot_limit_symbol"].search(b"slotting"))
    print(json.dumps({"assertions": assertions, "result": "PASS" if assertions == 7 else "FAIL"}))
    return 0 if assertions == 7 else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--canonical-map", type=Path)
    parser.add_argument("--canonical-evidence", type=Path)
    parser.add_argument("--client", type=Path)
    parser.add_argument("--server", type=Path)
    parser.add_argument("--tool", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    required = (args.canonical_map, args.canonical_evidence, args.client, args.server, args.tool, args.output)
    if any(value is None for value in required):
        parser.error("all inputs required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(json.dumps(build(args), ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
