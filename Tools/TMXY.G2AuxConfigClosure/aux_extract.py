#!/usr/bin/env python3
"""Extract redacted auxiliary-config reference candidates for G2-06.

The extractor validates the P2-05 file-instance population and the ignored
P2-12/P2-13 inputs before producing any result.  It never serializes source
paths, config keys, scalar values, line numbers, primary keys, or observed
extrema.  Exact lexical candidates remain ``candidate-only``; this module has
no authority to approve semantic roots.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Mapping, Sequence

from aux_common import (
    SCHEMA_VERSION,
    EvidenceError,
    Scalar,
    candidate_set_sha256,
    canonical_identity_text,
    canonical_json_bytes,
    canonical_json_line,
    clear_mutable_buffer,
    decode_bytes,
    domain_hash,
    extract_ecf_scalars,
    extract_xml_scalars,
    package_lookup_hashes,
    run_common_self_test,
    sha256_bytes,
    string_set_sha256,
    transform_ecf,
    validate_closed_record,
)


EVIDENCE_REVISION = "P2-20A.3"
P2_05_INVENTORY = "Data/Inventory/p2-05-auxiliary-config-inventory.json"
P2_12_EVIDENCE = "Data/Inventory/p2-12-full-asset-inventory.json"
P2_13_EVIDENCE = "Data/Inventory/p2-13-reference-closure.json"

EXPECTED_BASELINE: Mapping[str, int] = {
    "source_files": 212,
    "source_unique_blobs": 196,
    "source_bytes": 1_909_135,
    "xml_files": 148,
    "ecf_files": 64,
    "parseable_files": 206,
    "malformed_files": 6,
    "scalar_locations": 39_522,
    "nonempty_scalar_locations": 39_498,
    "ecf_repeated_assignments": 9,
    "asset_identity_occurrences": 3_043,
    "package_identity_occurrences": 638,
    "package_unique_occurrences": 218,
    "package_ambiguous_occurrences": 420,
    "package_candidate_edges": 1_136,
    "config_identity_occurrences": 8,
    "resource_identity_occurrences": 3_681,
    "region_resource_identity_occurrences": 3_428,
    "runtime_ecf_resource_identity_occurrences": 253,
    "approved_semantic_roots": 0,
}

FILE_RECORD_FIELDS = frozenset(
    {
        "record",
        "schema_version",
        "closed_record",
        "member_id",
        "source_file_id",
        "source_kind",
        "source_role",
        "adapter_id",
        "adapter_status",
        "parsed",
        "scalar_locations",
        "nonempty_scalar_locations",
        "resource_candidate_occurrences",
        "config_candidate_occurrences",
        "closed_reason",
    }
)
CANDIDATE_RECORD_FIELDS = frozenset(
    {
        "record",
        "schema_version",
        "closed_record",
        "member_id",
        "source_file_id",
        "source_kind",
        "source_role",
        "source_scalar_kind",
        "scalar_location_id",
        "adapter_id",
        "adapter_status",
        "target_kind",
        "resolution",
        "candidate_count",
        "candidate_ids",
        "candidate_set_sha256",
        "semantic_root_approved",
        "closed_reason",
    }
)
BLOCKER_RECORD_FIELDS = frozenset(
    {
        "record",
        "schema_version",
        "closed_record",
        "member_id",
        "source_file_id",
        "source_kind",
        "source_role",
        "adapter_id",
        "adapter_status",
        "blocker_code",
        "closed_reason",
    }
)


@dataclass(frozen=True)
class ExtractionResult:
    summary: Mapping[str, object]
    records: tuple[Mapping[str, object], ...]

    def detail_jsonl_bytes(self) -> bytes:
        return b"".join(canonical_json_line(record) for record in self.records)

    def detail_sha256(self) -> str:
        digest = hashlib.sha256()
        for record in self.records:
            digest.update(canonical_json_line(record))
        return digest.hexdigest()

    def write_detail_jsonl(self, output: BinaryIO) -> tuple[int, int, str]:
        digest = hashlib.sha256()
        size = 0
        for record in self.records:
            encoded = canonical_json_line(record)
            output.write(encoded)
            digest.update(encoded)
            size += len(encoded)
        return len(self.records), size, digest.hexdigest()


def _load_json(path: Path, label: str) -> tuple[dict[str, object], int, str]:
    raw = bytearray(path.read_bytes())
    try:
        digest = sha256_bytes(raw)
        size = len(raw)
        value = json.loads(bytes(raw))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not valid JSON evidence") from error
    finally:
        clear_mutable_buffer(raw)
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be a JSON object")
    return value, size, digest


def _safe_repo_path(repo_root: Path, relative: object, label: str) -> Path:
    if not isinstance(relative, str):
        raise EvidenceError(f"{label} path binding is missing")
    candidate = Path(relative)
    if candidate.is_absolute():
        raise EvidenceError(f"{label} path binding must be repository-relative")
    root = repo_root.resolve(strict=True)
    resolved = (root / candidate).resolve(strict=True)
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise EvidenceError(f"{label} path binding escapes the repository") from error
    return resolved


def _verify_declared_file(
    path: Path,
    declared_bytes: object,
    declared_sha256: object,
    label: str,
) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
            size += len(block)
    actual_sha256 = digest.hexdigest()
    if size != int(declared_bytes) or actual_sha256 != str(declared_sha256):
        raise EvidenceError(f"{label} bytes or SHA-256 does not match tracked evidence")
    return size, actual_sha256


def _load_asset_index(
    repo_root: Path, evidence: Mapping[str, object]
) -> tuple[dict[str, tuple[str, ...]], Mapping[str, object]]:
    catalog = evidence.get("catalog")
    if not isinstance(catalog, dict) or catalog.get("tracked") is not False:
        raise EvidenceError("P2-12 ignored catalog binding is incomplete")
    path = _safe_repo_path(repo_root, catalog.get("path"), "P2-12 catalog")
    declared_size, declared_sha = _verify_declared_file(
        path, catalog.get("bytes"), catalog.get("sha256"), "P2-12 catalog"
    )

    index: dict[str, list[str]] = {}
    line_count = 0
    with path.open("rb") as source:
        for raw in source:
            line_count += 1
            try:
                record = json.loads(raw)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise EvidenceError("P2-12 catalog contains invalid JSONL") from error
            raw_path = record.get("path")
            if not isinstance(raw_path, str):
                raise EvidenceError("P2-12 catalog record lacks an asset identity")
            canonical = canonical_identity_text(raw_path)
            anonymous = domain_hash("g2-aux-asset-target-v1", canonical)
            index.setdefault(canonical, []).append(anonymous)
    if line_count != int(catalog.get("lines")):
        raise EvidenceError("P2-12 catalog line count does not match tracked evidence")
    closed = {key: tuple(sorted(set(value))) for key, value in index.items()}
    return closed, {
        "evidence_sha256": None,
        "catalog_bytes": declared_size,
        "catalog_sha256": declared_sha,
        "catalog_lines": line_count,
        "identity_count": len(closed),
    }


def _load_package_index(
    repo_root: Path, evidence: Mapping[str, object]
) -> tuple[dict[str, tuple[str, ...]], Mapping[str, object]]:
    graph = evidence.get("graph")
    if not isinstance(graph, dict) or graph.get("tracked") is not False:
        raise EvidenceError("P2-13 ignored graph binding is incomplete")
    path = _safe_repo_path(repo_root, graph.get("path"), "P2-13 graph")
    declared_size, declared_sha = _verify_declared_file(
        path, graph.get("bytes"), graph.get("sha256"), "P2-13 graph"
    )

    index: dict[str, list[str]] = {}
    line_count = 0
    package_nodes = 0
    with path.open("rb") as source:
        for raw in source:
            line_count += 1
            try:
                record = json.loads(raw)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise EvidenceError("P2-13 graph contains invalid JSONL") from error
            if record.get("record") != "package_node":
                continue
            package_nodes += 1
            lookup_hash = record.get("logical_name_ascii_lower_sha256")
            node_id = record.get("id")
            if not isinstance(lookup_hash, str) or not isinstance(node_id, str):
                raise EvidenceError("P2-13 package node lacks an anonymous identity")
            anonymous = domain_hash("g2-aux-package-target-v1", node_id)
            index.setdefault(lookup_hash, []).append(anonymous)
    if line_count != int(graph.get("lines")):
        raise EvidenceError("P2-13 graph line count does not match tracked evidence")
    closed = {key: tuple(sorted(set(value))) for key, value in index.items()}
    return closed, {
        "evidence_sha256": None,
        "graph_bytes": declared_size,
        "graph_sha256": declared_sha,
        "graph_lines": line_count,
        "package_nodes": package_nodes,
        "lookup_identities": len(closed),
    }


def _adapter(entry: Mapping[str, object]) -> tuple[str, str]:
    ownership = entry.get("ownership")
    structure = entry.get("structure")
    if not isinstance(ownership, dict) or not isinstance(structure, dict):
        raise EvidenceError("P2-05 entry lacks ownership or structure evidence")
    role = ownership.get("role")
    classification = structure.get("classification")
    if classification == "malformed-xml":
        return "xml-tolerant-adapter-required-v1", "malformed-blocked"
    if role in {"client-region-runtime-data", "client-region-nested-shadow-copy"}:
        return "region-xml-exact-candidate-v1", "candidate-only"
    if role == "client-runtime-or-engine":
        return "runtime-ecf-exact-candidate-v1", "candidate-only"
    if role == "client-editor-tooling":
        return "editor-ecf-scope-review-v1", "editor-undecided"
    if role == "shared-configuration-data":
        return "shared-xml-no-reference-review-v1", "editor-undecided"
    if role == "client-help-data":
        return "help-xml-no-reference-review-v1", "editor-undecided"
    raise EvidenceError("P2-05 role has no fail-closed auxiliary adapter state")


def _candidate_record(
    *,
    source_file_id: str,
    source_kind: str,
    source_role: str,
    scalar: Scalar,
    adapter_id: str,
    adapter_status: str,
    target_kind: str,
    candidate_ids: Sequence[str],
    closed_reason: str,
) -> dict[str, object]:
    candidates = tuple(sorted(set(candidate_ids)))
    if not candidates:
        raise EvidenceError("candidate record cannot have an empty candidate set")
    scalar_location_id = domain_hash(
        "g2-aux-scalar-location-v1", source_file_id, scalar.kind, str(scalar.ordinal)
    )
    member_id = domain_hash(
        "g2-aux-candidate-member-v1", source_file_id, scalar_location_id, target_kind
    )
    record: dict[str, object] = {
        "record": "auxiliary_config_reference_candidate",
        "schema_version": SCHEMA_VERSION,
        "closed_record": True,
        "member_id": member_id,
        "source_file_id": source_file_id,
        "source_kind": source_kind,
        "source_role": source_role,
        "source_scalar_kind": scalar.kind,
        "scalar_location_id": scalar_location_id,
        "adapter_id": adapter_id,
        "adapter_status": adapter_status,
        "target_kind": target_kind,
        "resolution": "unique" if len(candidates) == 1 else "ambiguous",
        "candidate_count": len(candidates),
        "candidate_ids": list(candidates),
        "candidate_set_sha256": candidate_set_sha256(candidates),
        "semantic_root_approved": False,
        "closed_reason": closed_reason,
    }
    validate_closed_record(record, CANDIDATE_RECORD_FIELDS)
    return record


def _file_record(
    *,
    source_file_id: str,
    source_kind: str,
    source_role: str,
    adapter_id: str,
    adapter_status: str,
    parsed: bool,
    scalar_count: int,
    nonempty_count: int,
    resource_count: int,
    config_count: int,
) -> dict[str, object]:
    if not parsed:
        reason = "strict-parser-rejected-and-tolerant-adapter-is-not-approved"
    elif resource_count or config_count:
        reason = "exact-identity-candidates-are-not-semantic-roots"
    else:
        reason = "zero-exact-candidates-does-not-prove-zero-references"
    record: dict[str, object] = {
        "record": "auxiliary_config_file_scope",
        "schema_version": SCHEMA_VERSION,
        "closed_record": True,
        "member_id": domain_hash("g2-aux-file-scope-member-v1", source_file_id),
        "source_file_id": source_file_id,
        "source_kind": source_kind,
        "source_role": source_role,
        "adapter_id": adapter_id,
        "adapter_status": adapter_status,
        "parsed": parsed,
        "scalar_locations": scalar_count,
        "nonempty_scalar_locations": nonempty_count,
        "resource_candidate_occurrences": resource_count,
        "config_candidate_occurrences": config_count,
        "closed_reason": reason,
    }
    validate_closed_record(record, FILE_RECORD_FIELDS)
    return record


def _blocker_record(
    source_file_id: str, source_kind: str, source_role: str, adapter_id: str
) -> dict[str, object]:
    record: dict[str, object] = {
        "record": "auxiliary_config_scope_blocker",
        "schema_version": SCHEMA_VERSION,
        "closed_record": True,
        "member_id": domain_hash("g2-aux-malformed-blocker-v1", source_file_id),
        "source_file_id": source_file_id,
        "source_kind": source_kind,
        "source_role": source_role,
        "adapter_id": adapter_id,
        "adapter_status": "malformed-blocked",
        "blocker_code": "strict-xml-malformed-requires-byte-preserving-adapter",
        "closed_reason": "malformed-input-is-not-repaired-or-treated-as-no-reference",
    }
    validate_closed_record(record, BLOCKER_RECORD_FIELDS)
    return record


def _read_source_scalars(
    source_path: Path, entry: Mapping[str, object]
) -> tuple[list[Scalar], int]:
    raw = bytearray(source_path.read_bytes())
    decoded: bytearray | None = None
    round_trip: bytearray | None = None
    try:
        if len(raw) != int(entry.get("bytes")) or sha256_bytes(raw) != entry.get("sha256"):
            raise EvidenceError("P2-05 source instance bytes or SHA-256 changed")
        encoding = entry.get("encoding")
        structure = entry.get("structure")
        if not isinstance(encoding, dict) or not isinstance(structure, dict):
            raise EvidenceError("P2-05 source entry lacks parse evidence")
        classification = str(encoding.get("classification"))
        source_kind = entry.get("kind")
        if source_kind == "ecf":
            decoded = transform_ecf(raw)
            round_trip = transform_ecf(decoded)
            if round_trip != raw:
                raise EvidenceError("ECF transform failed the self-inverse check")
            text = decode_bytes(decoded, classification)
            scalars, repeated = extract_ecf_scalars(text)
            text = ""
            return scalars, repeated
        if source_kind == "xml":
            text = decode_bytes(raw, classification)
            scalars = extract_xml_scalars(text, str(structure.get("classification")))
            text = ""
            return scalars, 0
        raise EvidenceError("P2-05 source kind is outside XML/ECF scope")
    finally:
        clear_mutable_buffer(raw)
        clear_mutable_buffer(decoded)
        clear_mutable_buffer(round_trip)


def _validate_baseline(measured: Mapping[str, int]) -> None:
    for key, expected in EXPECTED_BASELINE.items():
        if measured.get(key) != expected:
            raise EvidenceError(f"measured aggregate does not match locked baseline: {key}")

def extract_repository(
    repo_root: Path | str, *, enforce_expected_baseline: bool = True
) -> ExtractionResult:
    """Lazy public wrapper for the repository-scale extractor."""

    from aux_extract_runner import extract_repository as implementation

    return implementation(repo_root, enforce_expected_baseline=enforce_expected_baseline)


def build_lexical_evidence(
    root: Path,
    client_root: Path,
    inventory: dict[str, object],
    asset_catalog_path: Path,
    reference_graph_path: Path,
) -> dict[str, object]:
    """Lazy stable integration wrapper used by report-generation callers."""

    from aux_extract_runner import build_lexical_evidence as implementation

    return implementation(root, client_root, inventory, asset_catalog_path, reference_graph_path)


def run_self_test(repo_root: Path | str) -> Mapping[str, object]:
    from aux_extract_runner import run_self_test as implementation

    return implementation(repo_root)


def main(argv: Sequence[str] | None = None) -> int:
    from aux_extract_runner import main as implementation

    return implementation(argv)


if __name__ == "__main__":
    raise SystemExit(main())
