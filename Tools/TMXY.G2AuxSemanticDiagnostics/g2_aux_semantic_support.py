"""Shared primitives for disclosure-safe auxiliary semantic diagnostics."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable
import xml.etree.ElementTree as ET


CURRENT_ASSIGNMENT = re.compile(r"^[^;#\s][^=]*=")


class EvidenceError(RuntimeError):
    pass


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


def lower_ascii_text(value: str) -> str:
    return "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in value)


def canonical_identity(value: str) -> str:
    return lower_ascii_text(value.strip().replace("\\", "/"))


def lower_ascii_bytes(value: bytes) -> bytes:
    return bytes(ch + 32 if 65 <= ch <= 90 else ch for ch in value)


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
            f"{label} binding is not a safe repository-relative path")
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts,
            f"{label} binding escaped its root")
    resolved = (root / candidate).resolve(strict=True)
    require(resolved.is_relative_to(root), f"{label} binding escaped its root")
    return resolved


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not readable JSON") from error
    require(isinstance(value, dict), f"{label} root is not an object")
    return value


def transform_ecf(source: bytes) -> bytearray:
    result = bytearray(len(source))
    full = len(source) - len(source) % 4
    for offset in range(0, full, 4):
        result[offset] = (~source[offset + 2]) & 0xFF
        result[offset + 1] = (~source[offset + 3]) & 0xFF
        result[offset + 2] = (~source[offset]) & 0xFF
        result[offset + 3] = (~source[offset + 1]) & 0xFF
    for offset in range(full, len(source)):
        result[offset] = (~source[offset]) & 0xFF
    return result


def decode_ecf(raw: bytes, classification: str) -> str:
    transformed = transform_ecf(raw)
    try:
        encoding = {"ascii": "ascii", "gbk": "gbk", "utf8": "utf-8",
                    "utf8-or-gbk": "gbk"}.get(classification)
        require(encoding is not None, "unsupported ECF encoding classification")
        return bytes(transformed).decode(encoding, errors="strict")
    finally:
        transformed[:] = b"\x00" * len(transformed)


def current_assignments(text: str) -> list[str]:
    return [line.split("=", 1)[1].strip() for line in re.split(r"\r?\n", text)
            if CURRENT_ASSIGNMENT.match(line)]


def legacy_assignments(text: str) -> list[str]:
    result: list[str] = []
    for line in text.split("\r\n"):
        at = line.find("=")
        if at > 0:
            result.append(line[at + 1:].strip())
    return result


def consumed_region_values(root: ET.Element) -> Iterable[tuple[str, str]]:
    level = root.attrib.get("client_map")
    if level is not None:
        yield "package-root", level
    maps = root.find("ClientMaps")
    if maps is not None:
        for map_node in list(maps):
            texture = map_node.attrib.get("tex")
            if texture is not None:
                yield "object", texture
            if map_node.tag in {"MyUnit", "MarkUnit"}:
                continue
            for child in list(map_node):
                if child.tag == "Icon":
                    for attribute in ("tex", "lightTex"):
                        value = child.attrib.get(attribute)
                        if value is not None:
                            yield "object", value
                elif child.tag == "ColorRegion":
                    value = child.attrib.get("lightTex")
                    if value is not None:
                        yield "object", value
    regions = root.find("Regions")
    if regions is not None:
        for child in list(regions):
            attribute = ("music" if child.tag == "DefaultBackground" else
                         "client_music" if child.tag == "Region" else None)
            if attribute is not None and child.attrib.get(attribute) is not None:
                yield "file", child.attrib[attribute]


def bind_source_hashes(root: Path, bindings: dict[str, str]) -> list[dict[str, str]]:
    """Bind source bodies by approved digest without serializing or embedding paths."""
    require(bindings and all(isinstance(k, str) and isinstance(v, str)
                             for k, v in bindings.items()),
            "legacy source bindings are incomplete")
    pending = set(bindings.values())
    found = {digest: 0 for digest in pending}
    for path in root.rglob("*.cpp"):
        if path.is_file():
            digest = sha256_file(path)
            if digest in pending:
                found[digest] += 1
    require(all(count == 1 for count in found.values()),
            "one or more legacy source bodies are absent or ambiguous")
    return [{"role": role, "sha256": bindings[role]} for role in sorted(bindings)]
