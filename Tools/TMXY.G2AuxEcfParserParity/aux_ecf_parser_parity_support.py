"""Primitives for disclosure-safe P2-20A.10 ECF parser diagnostics."""

from __future__ import annotations

import collections
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable, Sequence


A3_ASSIGNMENT = re.compile(r"^[^;#\s][^=]*=")
ENCODINGS = {"ascii": "ascii", "gbk": "gbk", "utf8": "utf-8",
             "utf8-or-gbk": "gbk"}


class EvidenceError(RuntimeError):
    """Raised when an evidence boundary fails closed."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def sha256_bytes(value: bytes | bytearray) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def domain_hash(domain: str, *parts: str) -> str:
    digest = hashlib.sha256()
    for part in (domain, *parts):
        raw = part.encode("utf-8", errors="strict")
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def ordered_string_hash(values: Iterable[str]) -> str:
    digest = hashlib.sha256()
    for value in values:
        raw = value.encode("utf-8", errors="strict")
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def string_set_hash(values: Iterable[str]) -> str:
    return ordered_string_hash(sorted(set(values)))


def lower_ascii_text(value: str) -> str:
    return "".join(chr(ord(char) + 32) if "A" <= char <= "Z" else char
                   for char in value)


def canonical_identity(value: str) -> str:
    return lower_ascii_text(value.strip().replace("\\", "/"))


def lower_ascii_bytes(value: bytes) -> bytes:
    return bytes(char + 32 if 65 <= char <= 90 else char for char in value)


def package_lookup_hashes(value: str) -> set[str]:
    result: set[str] = set()
    for encoding in ("utf-8", "gb18030"):
        try:
            result.add(sha256_bytes(lower_ascii_bytes(value.strip().encode(encoding))))
        except UnicodeEncodeError:
            pass
    return result


def resolve_inside(root: Path, relative: object, label: str) -> Path:
    require(isinstance(relative, str) and relative and "\\" not in relative,
            f"{label} path is not portable")
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts,
            f"{label} path escaped its root")
    resolved = (root / candidate).resolve(strict=True)
    require(resolved.is_relative_to(root), f"{label} path escaped its root")
    return resolved


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes())
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not readable JSON") from error
    require(isinstance(value, dict), f"{label} root is not an object")
    return value


def current_a3_transform(source: bytes) -> bytes:
    """Reproduce the frozen A.3 full-four-byte-only transform exactly."""
    result = bytearray(len(source))
    full = len(source) - len(source) % 4
    for offset in range(0, full, 4):
        result[offset] = (~source[offset + 2]) & 0xFF
        result[offset + 1] = (~source[offset + 3]) & 0xFF
        result[offset + 2] = (~source[offset]) & 0xFF
        result[offset + 3] = (~source[offset + 1]) & 0xFF
    for offset in range(full, len(source)):
        result[offset] = (~source[offset]) & 0xFF
    return bytes(result)


def reference_legacy_transform(source: bytes) -> bytes:
    """Port the observed QConfig swap loop literally, including a 3-byte tail."""
    result = bytearray(source)
    for offset in range(0, len(result), 4):
        if offset + 2 < len(result):
            result[offset], result[offset + 2] = result[offset + 2], result[offset]
        if offset + 1 < len(result) and offset + 3 < len(result):
            result[offset + 1], result[offset + 3] = (
                result[offset + 3], result[offset + 1])
    for offset, value in enumerate(result):
        result[offset] = 0xFF - value
    return bytes(result)


def independent_legacy_transform(source: bytes) -> bytes:
    """Independent direct mapping used to cross-check the literal reference port."""
    result = bytearray(len(source))
    for offset in range(0, len(source), 4):
        remaining = len(source) - offset
        if remaining >= 4:
            mapping = (2, 3, 0, 1)
        elif remaining == 3:
            mapping = (2, 1, 0)
        else:
            mapping = tuple(range(remaining))
        for target, relative in enumerate(mapping):
            result[offset + target] = (~source[offset + relative]) & 0xFF
    return bytes(result)


def _encoding(classification: str) -> str:
    encoding = ENCODINGS.get(classification)
    require(encoding is not None, "unsupported ECF encoding classification")
    return encoding


def a3_pairs(plain: bytes, classification: str) -> list[tuple[bytes, bytes]]:
    """Replay the frozen A.3 regex, universal-LF split, and Python strip."""
    encoding = _encoding(classification)
    text = plain.decode(encoding, errors="strict")
    result: list[tuple[bytes, bytes]] = []
    for line in re.split(r"\r?\n", text):
        if not A3_ASSIGNMENT.match(line):
            continue
        key, value = line.split("=", 1)
        result.append((key.strip().encode(encoding, errors="strict"),
                       value.strip().encode(encoding, errors="strict")))
    return result


def reference_legacy_pairs(plain: bytes) -> list[tuple[bytes, bytes]]:
    """Literal CRLF split plus first-equals and ASCII tab/space trimming."""
    result: list[tuple[bytes, bytes]] = []
    for segment in plain.split(b"\r\n"):
        equals = segment.find(b"=")
        if equals > 0:
            result.append((segment[:equals].strip(b" \t"),
                           segment[equals + 1:].strip(b" \t")))
    return result


def _trim_space_tab(value: bytes) -> bytes:
    left, right = 0, len(value)
    while left < right and value[left] in (0x09, 0x20):
        left += 1
    while right > left and value[right - 1] in (0x09, 0x20):
        right -= 1
    return value[left:right]


def independent_legacy_pairs(plain: bytes) -> list[tuple[bytes, bytes]]:
    """Streaming implementation independent of bytes.split and bytes.strip."""
    result: list[tuple[bytes, bytes]] = []
    cursor = 0
    while True:
        boundary = plain.find(b"\r\n", cursor)
        final = boundary < 0
        segment = plain[cursor:] if final else plain[cursor:boundary]
        equals = segment.find(b"=")
        if equals > 0:
            result.append((_trim_space_tab(segment[:equals]),
                           _trim_space_tab(segment[equals + 1:])))
        if final:
            break
        cursor = boundary + 2
    return result


def pair_digest(pair: tuple[bytes, bytes]) -> str:
    digest = hashlib.sha256(b"tmxy-ecf-pair-v1\x00")
    for part in pair:
        digest.update(len(part).to_bytes(8, "big"))
        digest.update(part)
    return digest.hexdigest()


def pair_sequence_hash(pairs: Sequence[tuple[bytes, bytes]]) -> str:
    return ordered_string_hash(pair_digest(pair) for pair in pairs)


def compare_pairs(left: Sequence[tuple[bytes, bytes]],
                  right: Sequence[tuple[bytes, bytes]]) -> dict[str, int | bool]:
    left_counts = collections.Counter(pair_digest(pair) for pair in left)
    right_counts = collections.Counter(pair_digest(pair) for pair in right)
    return {
        "equal": list(left) == list(right),
        "left_count": len(left),
        "right_count": len(right),
        "shared_count": sum((left_counts & right_counts).values()),
        "left_only_count": sum((left_counts - right_counts).values()),
        "right_only_count": sum((right_counts - left_counts).values()),
    }


def newline_profile(plain: bytes) -> dict[str, int | bool | str]:
    crlf = plain.count(b"\r\n")
    lone_lf = plain.count(b"\n") - crlf
    lone_cr = plain.count(b"\r") - crlf
    profile = "CRLF_ONLY" if lone_lf == 0 and lone_cr == 0 else "MIXED"
    return {"profile": profile, "crlf": crlf, "lone_lf": lone_lf,
            "lone_cr": lone_cr, "nul": plain.count(b"\x00"),
            "trailing_crlf": plain.endswith(b"\r\n")}


def bind_legacy_sources(root: Path, expected: dict[str, str]) -> list[dict[str, str]]:
    require(expected and all(isinstance(key, str) and isinstance(value, str)
                             for key, value in expected.items()),
            "legacy source bindings are incomplete")
    counts = {digest: 0 for digest in expected.values()}
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".cpp", ".h"}:
            digest = sha256_file(path)
            if digest in counts:
                counts[digest] += 1
    require(all(count == 1 for count in counts.values()),
            "legacy source body is absent or digest-ambiguous")
    return [{"role": role, "sha256": expected[role]} for role in sorted(expected)]


def load_indexes(root: Path, inventory: dict[str, Any], asset_evidence: dict[str, Any],
                 reference_evidence: dict[str, Any]) -> tuple[dict[str, tuple[str, ...]],
                                                               dict[str, tuple[str, ...]],
                                                               dict[str, tuple[str, ...]]]:
    catalog = asset_evidence.get("catalog", {})
    graph = reference_evidence.get("graph", {})
    require(catalog.get("tracked") is False and graph.get("tracked") is False,
            "ignored candidate indexes are not bound")
    catalog_path = resolve_inside(root, catalog.get("path"), "asset catalog")
    graph_path = resolve_inside(root, graph.get("path"), "reference graph")
    require(catalog_path.stat().st_size == int(catalog["bytes"]) and
            sha256_file(catalog_path) == catalog["sha256"], "asset catalog drifted")
    require(graph_path.stat().st_size == int(graph["bytes"]) and
            sha256_file(graph_path) == graph["sha256"], "reference graph drifted")
    assets: dict[str, set[str]] = collections.defaultdict(set)
    catalog_lines = 0
    for raw in catalog_path.open("rb"):
        catalog_lines += 1
        record = json.loads(raw)
        value = record.get("path")
        require(isinstance(value, str), "asset identity is absent")
        canonical = canonical_identity(value)
        assets[canonical].add(domain_hash("g2-aux-asset-target-v1", canonical))
    require(catalog_lines == int(catalog["lines"]), "asset catalog line count drifted")
    packages: dict[str, set[str]] = collections.defaultdict(set)
    graph_lines = 0
    for raw in graph_path.open("rb"):
        graph_lines += 1
        record = json.loads(raw)
        if record.get("record") == "package_node":
            lookup, node = record.get("logical_name_ascii_lower_sha256"), record.get("id")
            require(isinstance(lookup, str) and isinstance(node, str),
                    "package node identity is absent")
            packages[lookup].add(domain_hash("g2-aux-package-target-v1", node))
    require(graph_lines == int(graph["lines"]), "reference graph line count drifted")
    configs: dict[str, set[str]] = collections.defaultdict(set)
    for entry in inventory["files"]:
        canonical = canonical_identity(str(entry["path"]))
        configs[canonical].add(domain_hash("g2-aux-config-target-v1", canonical))
    freeze = lambda value: {key: tuple(sorted(items)) for key, items in value.items()}
    return freeze(assets), freeze(packages), freeze(configs)


def candidate_projection(pairs: Sequence[tuple[bytes, bytes]], classification: str,
                         indexes: tuple[dict[str, tuple[str, ...]],
                                        dict[str, tuple[str, ...]],
                                        dict[str, tuple[str, ...]]]) -> tuple[dict[str, Any],
                                                                            list[str]]:
    assets, packages, configs = indexes
    encoding = _encoding(classification)
    counts = collections.Counter()
    candidate_ids: list[str] = []
    nonempty = 0
    for _, raw_value in pairs:
        value = raw_value.decode(encoding, errors="strict")
        if value:
            nonempty += 1
        canonical = canonical_identity(value)
        matches = {
            "asset": assets.get(canonical, ()),
            "package": tuple(sorted({candidate for lookup in package_lookup_hashes(value)
                                     for candidate in packages.get(lookup, ())})),
            "config": configs.get(canonical, ()),
        }
        for kind, candidates in matches.items():
            if candidates:
                counts[f"{kind}_occurrences"] += 1
                counts[f"{kind}_edges"] += len(candidates)
                counts[f"{kind}_unique"] += int(len(candidates) == 1)
                counts[f"{kind}_ambiguous"] += int(len(candidates) > 1)
                candidate_ids.extend(f"{kind}:{candidate}" for candidate in candidates)
    fields = {f"{kind}_{suffix}": counts[f"{kind}_{suffix}"]
              for kind in ("asset", "package", "config")
              for suffix in ("occurrences", "edges", "unique", "ambiguous")}
    ordered_candidates = sorted(candidate_ids)
    return ({"pair_records": len(pairs), "nonempty_pair_values": nonempty,
             **fields, "candidate_multiset_sha256": ordered_string_hash(ordered_candidates)},
            ordered_candidates)


def run_self_test() -> dict[str, Any]:
    assertions = 0
    for length in range(17):
        raw = bytes(range(length))
        require(reference_legacy_transform(raw) == independent_legacy_transform(raw),
                "independent transform ports disagree")
        assertions += 1
    raw = bytes((0x10, 0x20, 0x30))
    require(reference_legacy_transform(raw) == bytes((0xCF, 0xDF, 0xEF)) and
            current_a3_transform(raw) == bytes((0xEF, 0xDF, 0xCF)),
            "three-byte tail regression escaped")
    assertions += 1
    plain = b"a\t =\t1 \r\n#comment=2\r\n;comment=3\r\nempty=\r\nmulti=a=b\r\ndup=x\r\ndup=x"
    reference = reference_legacy_pairs(plain)
    independent = independent_legacy_pairs(plain)
    require(reference == independent and len(reference) == 7 and
            reference[0] == (b"a", b"1") and reference[3] == (b"empty", b"") and
            reference[4] == (b"multi", b"a=b") and reference[-1] == (b"dup", b"x"),
            "legacy first-equals, trim, empty, multi-equals, or duplicate contract drifted")
    assertions += 1
    filtered = a3_pairs(plain, "ascii")
    require(len(filtered) == 5 and compare_pairs(filtered, reference)["right_only_count"] == 2,
            "A.3 comment-marker filter contract drifted")
    assertions += 1
    require(reference_legacy_pairs(b"a=1\nb=2\rc=3") == [(b"a", b"1\nb=2\rc=3")],
            "legacy CRLF-only split contract drifted")
    assertions += 1
    gbk_plain = "键\t=\t值\r\n".encode("gbk")
    require(a3_pairs(gbk_plain, "gbk") == reference_legacy_pairs(gbk_plain),
            "GBK parser contract drifted")
    assertions += 1
    require(newline_profile(b"a=1\r\n")["profile"] == "CRLF_ONLY" and
            newline_profile(b"a=1\n")["lone_lf"] == 1 and
            newline_profile(b"a=1\r")["lone_cr"] == 1 and
            newline_profile(b"a=\x00\r\n")["nul"] == 1,
            "newline or NUL detector drifted")
    assertions += 1
    require(pair_sequence_hash(reference) == pair_sequence_hash(independent) and
            domain_hash("x", "a", "bc") != domain_hash("x", "ab", "c"),
            "pair or domain hashing contract drifted")
    assertions += 1
    return {"result": "PASS", "assertions": assertions,
            "negative_cases": {
                "three_byte_tail_identity_complement_rejected": True,
                "lf_as_crlf_rejected": True,
                "cr_as_crlf_rejected": True,
                "nul_payload_detected": True,
                "comment_marker_filter_collapse_rejected": True,
            }}
