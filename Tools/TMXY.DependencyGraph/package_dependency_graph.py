#!/usr/bin/env python3
"""Build a deterministic, name-redacted graph from normalized Package trees."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, TextIO


MAX_OBJECTS = 200_000
MAX_PROPERTIES = 16_384
MAX_PROPERTY_NAME_BYTES = 4_096


def lower_ascii(value: bytes) -> bytes:
    return bytes(item + 32 if 65 <= item <= 90 else item for item in value)

EXACT_OBJECT_REFERENCES = {
    "diffuse": "texture",
    "bump": "texture",
    "blend": "texture",
    "selfIllum": "texture",
    "Mask": "texture",
    "reflection": "texture",
    "fur": "texture",
    "sound": "sound",
    "geom": "mesh",
    "ambientSound": "sound",
    "pgeom": "mesh",
    "projTex": "texture",
    "tailTexture": "texture",
    "terrainInfo": "scene",
    "terrBump": "texture",
    "skyTexture": "texture",
    "skyTextureDest": "texture",
    "areaTex": "texture",
    "waterBump": "texture",
    "waterEdge": "texture",
    "woldMoveMap": "texture",
}

ARRAY_OBJECT_REFERENCES = (
    (re.compile(r"^skins\[\d+\]$"), "material"),
    (re.compile(r"^_anim\[\d+\]$"), "animation"),
    (re.compile(r"^notify\[\d+\]$"), "notify"),
    (re.compile(r"^texList\[\d+\]$"), "texture"),
    (re.compile(r"^emitters\[\d+\]$"), "particle"),
    (re.compile(r"^sounds\[\d+\]$"), "sound"),
    (re.compile(r"^lightActors\[\d+\]$"), "scene"),
)

SUFFIX_OBJECT_REFERENCES = (
    (".texture", "texture"),
    (".staticMesh", "mesh"),
    (".suGeom", "mesh"),
    (".skyTex", "texture"),
    (".lensFlareGeom", "mesh"),
    (".effGeom", "mesh"),
    (".effectGeom", "mesh"),
    (".tailTexture", "texture"),
)

LOGICAL_REFERENCES = (
    (re.compile(r"^(?:anims|standbyAnims)\[\d+\]$"), "animation-name"),
    (re.compile(r"^(?:defaultAnim|_animName|_skeName|sectionName)$"), "logical-name"),
    (re.compile(r"^effects\[\d+\]\.boneName$"), "bone-name"),
)

CATEGORY_BY_CLASS = {
    "QTexture": "texture",
    "QPhongShader": "material",
    "QGeomEffectShader": "material",
    "QStaticMesh": "mesh",
    "QSkelMesh": "mesh",
    "QActor": "scene",
    "QLevel": "scene",
    "QTerrainInfo": "scene",
    "QAntiPortal": "scene",
    "QFogVolume": "scene",
    "QProjector": "scene",
    "QEmitter": "particle",
    "QParticleSys": "particle",
    "QSkelAnim": "animation",
    "QANSound": "sound",
    "QSound": "sound",
    "QUnitAction": "action",
    "QToolAction": "action",
    "QToolSwitchAction": "action",
}


@dataclass(frozen=True)
class Node:
    package: str
    name: bytes
    class_name: str
    body_offset: int
    body_size: int
    property_count: int

    @property
    def logical_name_hash(self) -> str:
        return hashlib.sha256(self.name).hexdigest()

    @property
    def logical_name_ascii_lower_hash(self) -> str:
        return hashlib.sha256(lower_ascii(self.name)).hexdigest()

    @property
    def node_id(self) -> str:
        identity = self.package.encode("utf-8") + b"\0" + self.name
        return hashlib.sha256(identity).hexdigest()


@dataclass(frozen=True)
class CandidateEdge:
    source_id: str
    target_name: bytes
    kind: str
    property_name: str
    logical: bool


def read_u16(data: bytes, offset: int) -> tuple[int, int]:
    if offset + 2 > len(data):
        raise ValueError("truncated_u16")
    return struct.unpack_from("<H", data, offset)[0], offset + 2


def parse_envelope(body: bytes) -> list[tuple[str, bytes]]:
    count, offset = read_u16(body, 0)
    if count > MAX_PROPERTIES:
        raise ValueError("property_count_limit")
    records: list[tuple[str, bytes]] = []
    for _ in range(count):
        name_size, offset = read_u16(body, offset)
        if name_size > MAX_PROPERTY_NAME_BYTES or offset + name_size > len(body):
            raise ValueError("property_name_out_of_body")
        name_bytes = body[offset : offset + name_size]
        offset += name_size
        try:
            name = name_bytes.decode("ascii")
        except UnicodeDecodeError as error:
            raise ValueError("property_name_not_ascii") from error
        value_size, offset = read_u16(body, offset)
        if offset + value_size > len(body):
            raise ValueError("property_value_out_of_body")
        records.append((name, body[offset : offset + value_size]))
        offset += value_size
    if offset != len(body):
        raise ValueError("object_body_trailing_bytes")
    return records


def decode_reference(value: bytes) -> bytes:
    size, offset = read_u16(value, 0)
    if offset + size != len(value):
        raise ValueError("reference_value_size_mismatch")
    return value[offset:]


def classify_reference(property_name: str) -> tuple[bool, str] | None:
    exact = EXACT_OBJECT_REFERENCES.get(property_name)
    if exact is not None:
        return False, exact
    for pattern, kind in ARRAY_OBJECT_REFERENCES:
        if pattern.fullmatch(property_name):
            return False, kind
    for suffix, kind in SUFFIX_OBJECT_REFERENCES:
        if property_name.endswith(suffix):
            return False, kind
    for pattern, kind in LOGICAL_REFERENCES:
        if pattern.fullmatch(property_name):
            return True, kind
    return None


def safe_package_path(root: Path, label: str) -> Path:
    if not label.startswith("Packages/") or "\t" in label or "\n" in label or "\r" in label:
        raise ValueError("unsafe_package_label")
    root = root.resolve()
    candidate = (root / label).resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError("package_path_escape")
    return candidate


def parse_tree_stream(stream: TextIO, legacy_root: Path) -> tuple[list[Node], list[CandidateEdge], int]:
    nodes: list[Node] = []
    candidates: list[CandidateEdge] = []
    property_total = 0
    for line in stream:
        if not line.strip():
            continue
        tree = json.loads(line)
        label = str(tree["source"]["label"])
        package_path = safe_package_path(legacy_root, label)
        package_bytes = package_path.read_bytes()
        for item in tree["objects"]:
            name = bytes.fromhex(str(item["name"]["hex"]))
            class_bytes = bytes.fromhex(str(item["class_name"]["hex"]))
            class_name = class_bytes.decode("ascii")
            body_offset = int(item["body"]["offset"])
            body_size = int(item["body"]["size"])
            if body_offset < 0 or body_size < 0 or body_offset + body_size > len(package_bytes):
                raise ValueError("object_range_out_of_package")
            properties = parse_envelope(package_bytes[body_offset : body_offset + body_size])
            property_total += len(properties)
            node = Node(label, name, class_name, body_offset, body_size, len(properties))
            nodes.append(node)
            if len(nodes) > MAX_OBJECTS:
                raise ValueError("object_count_limit")
            for property_name, value in properties:
                rule = classify_reference(property_name)
                if rule is None:
                    continue
                logical, kind = rule
                target = decode_reference(value)
                if not target:
                    continue
                candidates.append(CandidateEdge(node.node_id, target, kind, property_name, logical))
    return nodes, candidates, property_total


def json_line(value: dict[str, object]) -> bytes:
    return (json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n").encode(
        "utf-8"
    )


def write_graph(path: Path, nodes: Iterable[Node], candidates: Iterable[CandidateEdge]) -> dict[str, object]:
    ordered_nodes = sorted(nodes, key=lambda item: (item.package, item.name, item.class_name, item.body_offset))
    name_counts = collections.Counter(item.name for item in ordered_nodes)
    lower_name_counts = collections.Counter(lower_ascii(item.name) for item in ordered_nodes)
    ordered_edges = sorted(
        candidates,
        key=lambda item: (item.source_id, item.kind, item.property_name, item.target_name),
    )
    digest = hashlib.sha256()
    byte_count = 0
    line_count = 0
    edge_resolution: collections.Counter[str] = collections.Counter()
    edge_kinds: collections.Counter[str] = collections.Counter()
    class_counts: collections.Counter[str] = collections.Counter()
    category_counts: collections.Counter[str] = collections.Counter()

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as output:
        for node in ordered_nodes:
            class_counts[node.class_name] += 1
            category_counts[CATEGORY_BY_CLASS.get(node.class_name, "other")] += 1
            record = {
                "body_offset": node.body_offset,
                "body_size": node.body_size,
                "category": CATEGORY_BY_CLASS.get(node.class_name, "other"),
                "class": node.class_name,
                "id": node.node_id,
                "logical_name_ascii_lower_sha256": node.logical_name_ascii_lower_hash,
                "logical_name_sha256": node.logical_name_hash,
                "package": node.package,
                "property_count": node.property_count,
                "record": "node",
            }
            encoded = json_line(record)
            output.write(encoded)
            digest.update(encoded)
            byte_count += len(encoded)
            line_count += 1
        for edge in ordered_edges:
            matches = 0 if edge.logical else lower_name_counts[lower_ascii(edge.target_name)]
            if edge.logical:
                resolution = "logical"
            elif matches == 0:
                resolution = "unresolved"
            elif matches == 1:
                resolution = "unique"
            else:
                resolution = "ambiguous"
            edge_resolution[resolution] += 1
            edge_kinds[edge.kind] += 1
            record = {
                "candidate_count": matches,
                "kind": edge.kind,
                "property": edge.property_name,
                "record": "edge",
                "resolution": resolution,
                "source": edge.source_id,
                "target_logical_name_ascii_lower_sha256": hashlib.sha256(
                    lower_ascii(edge.target_name)
                ).hexdigest(),
                "target_logical_name_sha256": hashlib.sha256(edge.target_name).hexdigest(),
            }
            encoded = json_line(record)
            output.write(encoded)
            digest.update(encoded)
            byte_count += len(encoded)
            line_count += 1
    return {
        "bytes": byte_count,
        "sha256": digest.hexdigest(),
        "lines": line_count,
        "nodes": len(ordered_nodes),
        "edges": len(ordered_edges),
        "unique_logical_names": len(name_counts),
        "duplicate_logical_names": sum(1 for count in name_counts.values() if count > 1),
        "maximum_logical_name_multiplicity": max(name_counts.values(), default=0),
        "unique_ascii_lower_logical_names": len(lower_name_counts),
        "duplicate_ascii_lower_logical_names": sum(
            1 for count in lower_name_counts.values() if count > 1
        ),
        "maximum_ascii_lower_logical_name_multiplicity": max(
            lower_name_counts.values(), default=0
        ),
        "classes": dict(sorted(class_counts.items())),
        "categories": dict(sorted(category_counts.items())),
        "edge_kinds": dict(sorted(edge_kinds.items())),
        "edge_resolution": dict(sorted(edge_resolution.items())),
        "query_probe_node_id": ordered_edges[0].source_id if ordered_edges else "",
    }


def run_self_test() -> int:
    assertions = 0
    body = bytearray(struct.pack("<H", 2))
    for name, value in ((b"diffuse", b"mat.tex"), (b"future", b"opaque")):
        encoded = struct.pack("<H", len(value)) + value
        body += struct.pack("<H", len(name)) + name + struct.pack("<H", len(encoded)) + encoded
    properties = parse_envelope(bytes(body))
    assertions += int(len(properties) == 2)
    assertions += int(classify_reference("diffuse") == (False, "texture"))
    assertions += int(classify_reference("skins[12]") == (False, "material"))
    assertions += int(classify_reference("effects[2].boneName") == (True, "bone-name"))
    assertions += int(classify_reference("future") is None)
    assertions += int(decode_reference(properties[0][1]) == b"mat.tex")
    node = Node("Packages/test", b"mesh.object", "QStaticMesh", 20, 40, 2)
    assertions += int(len(node.node_id) == 64 and len(node.logical_name_hash) == 64)
    assertions += int(
        node.logical_name_ascii_lower_hash
        == hashlib.sha256(b"mesh.object").hexdigest()
    )
    assertions += int(b"mesh.object" not in json_line({"id": node.node_id}))
    expected = 9
    print(json.dumps({"result": "PASS" if assertions == expected else "FAIL", "assertions": assertions}))
    return 0 if assertions == expected else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--legacy-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return run_self_test()
    if args.legacy_root is None or args.output is None:
        parser.error("--legacy-root and --output are required")
    nodes, candidates, property_total = parse_tree_stream(sys.stdin, args.legacy_root)
    summary = write_graph(args.output, nodes, candidates)
    summary["properties"] = property_total
    summary["envelope_failures"] = 0
    summary["reference_value_failures"] = 0
    summary["object_names_emitted"] = False
    summary["class_names_emitted"] = True
    summary["object_bodies_copied"] = False
    print(json.dumps(summary, ensure_ascii=True, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
