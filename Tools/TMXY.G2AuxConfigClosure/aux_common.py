#!/usr/bin/env python3
"""Safe, deterministic primitives for the G2 auxiliary-config extractor.

This module deliberately has no functions that serialize legacy scalar values,
configuration keys, source paths, line numbers, or primary keys.  Callers get
only domain-separated anonymous identities and closed aggregate records.
"""

from __future__ import annotations

import hashlib
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence


SCHEMA_VERSION = 1


class EvidenceError(RuntimeError):
    """Raised when an evidence binding or fail-closed invariant is violated."""


@dataclass(frozen=True)
class Scalar:
    """An in-memory scalar; ``value`` must never be serialized by this tool."""

    ordinal: int
    kind: str
    value: str


def sha256_bytes(value: bytes | bytearray | memoryview) -> str:
    return hashlib.sha256(value).hexdigest()


def lower_ascii_bytes(value: bytes) -> bytes:
    """Lower ASCII bytes without changing any byte outside A-Z."""

    return bytes(item + 32 if 65 <= item <= 90 else item for item in value)


def lower_ascii_text(value: str) -> str:
    """Lower only ASCII characters, preserving all other Unicode code points."""

    return "".join(chr(ord(item) + 32) if "A" <= item <= "Z" else item for item in value)


def canonical_identity_text(value: str) -> str:
    """Canonicalize a whole path-like scalar without inferring a target.

    Only surrounding whitespace, slash direction, and ASCII case are changed.
    No basename, extension, dot-segment, substring, or Unicode normalization is
    performed, so this helper cannot promote a heuristic match to an identity.
    """

    return lower_ascii_text(value.strip().replace("\\", "/"))


def domain_hash(domain: str, *parts: str) -> str:
    """Hash length-prefixed UTF-8 components under an explicit domain."""

    digest = hashlib.sha256()
    for part in (domain, *parts):
        encoded = part.encode("utf-8", errors="strict")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    return digest.hexdigest()


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("ascii")


def canonical_json_line(value: object) -> bytes:
    return canonical_json_bytes(value) + b"\n"


def string_set_sha256(values: Iterable[str]) -> str:
    """Hash a sorted, duplicate-free sequence as canonical JSON lines."""

    ordered = sorted(set(values))
    digest = hashlib.sha256()
    for value in ordered:
        digest.update(canonical_json_line(value))
    return digest.hexdigest()


def candidate_set_sha256(values: Sequence[str]) -> str:
    """Hash the exact sorted candidate list; duplicates are forbidden."""

    ordered = sorted(values)
    if len(ordered) != len(set(ordered)):
        raise EvidenceError("candidate set contains duplicate anonymous identities")
    return sha256_bytes(canonical_json_bytes(ordered))


def package_lookup_hashes(value: str) -> tuple[str, ...]:
    """Return exact package-name lookup hashes for supported legacy encodings.

    Package names are byte identities.  A decoded config scalar is therefore
    tested using UTF-8 and GB18030 encodings, with ASCII-only case folding to
    match the P2-13 graph contract.  Encoding failure simply removes that exact
    representation; it never causes a fuzzy fallback.
    """

    trimmed = value.strip()
    encoded_variants: set[bytes] = set()
    for encoding in ("utf-8", "gb18030"):
        try:
            encoded_variants.add(trimmed.encode(encoding, errors="strict"))
        except UnicodeEncodeError:
            continue
    return tuple(
        sorted(sha256_bytes(lower_ascii_bytes(encoded)) for encoded in encoded_variants)
    )


def transform_ecf(source: bytes | bytearray | memoryview) -> bytearray:
    """Apply the P2-05 self-inverse ECF byte transform."""

    result = bytearray(len(source))
    full_bytes = len(source) - (len(source) % 4)
    for offset in range(0, full_bytes, 4):
        result[offset] = (~source[offset + 2]) & 0xFF
        result[offset + 1] = (~source[offset + 3]) & 0xFF
        result[offset + 2] = (~source[offset]) & 0xFF
        result[offset + 3] = (~source[offset + 1]) & 0xFF
    for offset in range(full_bytes, len(source)):
        result[offset] = (~source[offset]) & 0xFF
    return result


def clear_mutable_buffer(value: bytearray | None) -> None:
    if value is not None:
        value[:] = b"\x00" * len(value)


def decode_bytes(source: bytes | bytearray, classification: str) -> str:
    """Strictly decode a P2-05-classified buffer without fallback guessing."""

    if classification == "ascii":
        return bytes(source).decode("ascii", errors="strict")
    if classification == "gbk":
        return bytes(source).decode("gbk", errors="strict")
    if classification == "utf8":
        return bytes(source).decode("utf-8", errors="strict")
    if classification == "utf8-or-gbk":
        # P2-05 classifies legacy XML/ECF as GBK when both codecs accept it.
        return bytes(source).decode("gbk", errors="strict")
    raise EvidenceError("unsupported or opaque P2-05 encoding classification")


_ASSIGNMENT = re.compile(r"^[^;#\s][^=]*=")
_FORBIDDEN_XML_DECLARATION = re.compile(r"<!\s*(?:DOCTYPE|ENTITY)\b", re.IGNORECASE)


def extract_ecf_scalars(text: str) -> tuple[list[Scalar], int]:
    """Extract ordered assignment RHS values and count repeated keys.

    The key strings are retained only transiently for the repeat count and are
    never returned.  Each assignment remains a distinct scalar in source order;
    neither first-value nor last-value semantics are applied.
    """

    scalars: list[Scalar] = []
    key_counts: dict[str, int] = {}
    for line in re.split(r"\r?\n", text):
        if not _ASSIGNMENT.match(line):
            continue
        key, value = line.split("=", 1)
        transient_key = key.strip()
        key_counts[transient_key] = key_counts.get(transient_key, 0) + 1
        scalars.append(Scalar(len(scalars), "ecf-assignment", value.strip()))
    repeated = sum(count - 1 for count in key_counts.values())
    key_counts.clear()
    return scalars, repeated


def _walk_xml_scalars(root: ET.Element, synthetic_root: bool) -> list[Scalar]:
    scalars: list[Scalar] = []

    def append(kind: str, value: str | None) -> None:
        if value is None:
            return
        trimmed = value.strip()
        if kind == "xml-text" and not trimmed:
            return
        scalars.append(Scalar(len(scalars), kind, trimmed))

    def visit(element: ET.Element) -> None:
        for value in element.attrib.values():
            append("xml-attribute", value)
        append("xml-text", element.text)
        for child in list(element):
            visit(child)
            append("xml-text", child.tail)

    if synthetic_root:
        append("xml-text", root.text)
        for child in list(root):
            visit(child)
            append("xml-text", child.tail)
    else:
        visit(root)
    return scalars


def extract_xml_scalars(text: str, classification: str) -> list[Scalar]:
    """Parse a strict XML document/fragment with DTD and entities prohibited."""

    if _FORBIDDEN_XML_DECLARATION.search(text):
        raise EvidenceError("DTD or entity declaration is forbidden")
    if classification == "xml-document":
        wrapped = text
        synthetic_root = False
    elif classification == "xml-fragment":
        wrapped = "<tmxy_aux_fragment>" + text + "</tmxy_aux_fragment>"
        synthetic_root = True
    else:
        raise EvidenceError("malformed XML cannot enter the strict parser")
    try:
        root = ET.fromstring(wrapped)
    except ET.ParseError as error:
        raise EvidenceError("P2-05 parseable XML failed strict extraction") from error
    return _walk_xml_scalars(root, synthetic_root)


def validate_closed_record(record: Mapping[str, object], allowed_fields: frozenset[str]) -> None:
    actual = frozenset(record.keys())
    if actual != allowed_fields:
        raise EvidenceError("detail record violates its closed field set")


def run_common_self_test() -> int:
    """Exercise transformations, parser hardening, and deterministic hashes."""

    assertions = 0

    probe = bytearray(b"abcdefghi")
    transformed = transform_ecf(probe)
    restored = transform_ecf(transformed)
    assert restored == probe
    assertions += 1
    clear_mutable_buffer(transformed)
    clear_mutable_buffer(restored)
    assert not any(transformed) and not any(restored)
    assertions += 1

    scalars, repeated = extract_ecf_scalars("A=one\r\nA=two\n;A=ignored\nB=three")
    assert [item.value for item in scalars] == ["one", "two", "three"]
    assert repeated == 1
    assertions += 2

    document = extract_xml_scalars('<r A="one"><x>two</x></r>', "xml-document")
    assert [(item.kind, item.value) for item in document] == [
        ("xml-attribute", "one"),
        ("xml-text", "two"),
    ]
    assertions += 1
    fragment = extract_xml_scalars('<a X="one"/><b>two</b>', "xml-fragment")
    assert [(item.kind, item.value) for item in fragment] == [
        ("xml-attribute", "one"),
        ("xml-text", "two"),
    ]
    assertions += 1

    try:
        extract_xml_scalars('<!DOCTYPE r [<!ENTITY x "y">]><r>&x;</r>', "xml-document")
    except EvidenceError:
        assertions += 1
    else:
        raise AssertionError("DTD test did not fail closed")

    assert canonical_identity_text(r"  A\\B.C  ") == "a//b.c"
    assertions += 1
    assert lower_ascii_bytes(b"Az\x80") == b"az\x80"
    assertions += 1
    assert candidate_set_sha256(("b", "a")) == candidate_set_sha256(("a", "b"))
    assertions += 1
    try:
        candidate_set_sha256(("a", "a"))
    except EvidenceError:
        assertions += 1
    else:
        raise AssertionError("duplicate candidate test did not fail closed")

    return assertions
