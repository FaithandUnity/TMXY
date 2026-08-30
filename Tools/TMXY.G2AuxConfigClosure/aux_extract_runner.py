#!/usr/bin/env python3
"""Repository-scale orchestration for the auxiliary-config extractor."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Mapping, Sequence

from aux_common import (
    SCHEMA_VERSION,
    EvidenceError,
    canonical_identity_text,
    canonical_json_bytes,
    canonical_json_line,
    domain_hash,
    package_lookup_hashes,
    run_common_self_test,
    sha256_bytes,
    string_set_sha256,
)
from aux_extract import (
    EVIDENCE_REVISION,
    EXPECTED_BASELINE,
    P2_05_INVENTORY,
    P2_12_EVIDENCE,
    P2_13_EVIDENCE,
    ExtractionResult,
    _adapter,
    _blocker_record,
    _candidate_record,
    _file_record,
    _load_asset_index,
    _load_json,
    _load_package_index,
    _read_source_scalars,
    _safe_repo_path,
    _validate_baseline,
)


def extract_repository(
    repo_root: Path | str, *, enforce_expected_baseline: bool = True
) -> ExtractionResult:
    root = Path(repo_root).resolve(strict=True)
    p205, p205_bytes, p205_sha = _load_json(root / P2_05_INVENTORY, "P2-05")
    p212, p212_bytes, p212_sha = _load_json(root / P2_12_EVIDENCE, "P2-12")
    p213, p213_bytes, p213_sha = _load_json(root / P2_13_EVIDENCE, "P2-13")
    if p205.get("completion_criteria_satisfied") is not True:
        raise EvidenceError("P2-05 evidence is not complete")
    if p212.get("completion_criteria_satisfied") is not True:
        raise EvidenceError("P2-12 evidence is not complete")
    if p213.get("completion_criteria_satisfied") is not True:
        raise EvidenceError("P2-13 evidence is not complete")

    asset_index, asset_binding = _load_asset_index(root, p212)
    package_index, package_binding = _load_package_index(root, p213)
    asset_binding = dict(asset_binding)
    package_binding = dict(package_binding)
    asset_binding["evidence_bytes"] = p212_bytes
    asset_binding["evidence_sha256"] = p212_sha
    package_binding["evidence_bytes"] = p213_bytes
    package_binding["evidence_sha256"] = p213_sha

    files = p205.get("files")
    source = p205.get("source")
    if not isinstance(files, list) or not isinstance(source, dict):
        raise EvidenceError("P2-05 file-instance evidence is incomplete")
    sandbox = _safe_repo_path(root, source.get("sandbox_relative_path"), "P2-05 sandbox")
    config_index: dict[str, list[str]] = {}
    entries: list[tuple[str, Mapping[str, object], str]] = []
    for raw_entry in files:
        if not isinstance(raw_entry, dict):
            raise EvidenceError("P2-05 file entry must be an object")
        relative = raw_entry.get("path")
        if not isinstance(relative, str):
            raise EvidenceError("P2-05 file entry lacks a relative identity")
        source_path = _safe_repo_path(sandbox, relative, "P2-05 source instance")
        try:
            source_path.relative_to(sandbox)
        except ValueError as error:
            raise EvidenceError("P2-05 source instance escapes the frozen sandbox") from error
        canonical = canonical_identity_text(relative)
        source_file_id = domain_hash(
            "g2-aux-source-file-v1", canonical, str(raw_entry.get("sha256"))
        )
        config_target_id = domain_hash("g2-aux-config-target-v1", canonical)
        config_index.setdefault(canonical, []).append(config_target_id)
        entries.append((canonical, raw_entry, source_file_id))
    if len(entries) != len({item[2] for item in entries}):
        raise EvidenceError("P2-05 file-instance anonymous identities are not unique")
    config_index = {key: sorted(set(value)) for key, value in config_index.items()}

    records: list[Mapping[str, object]] = []
    source_file_ids: list[str] = []
    source_blob_hashes: set[str] = set()
    measured = {key: 0 for key in EXPECTED_BASELINE}
    measured["source_files"] = len(entries)
    measured["source_unique_blobs"] = len({str(item[1].get("sha256")) for item in entries})
    measured["source_bytes"] = sum(int(item[1].get("bytes")) for item in entries)
    measured["approved_semantic_roots"] = 0
    resource_files: set[str] = set()
    config_files: set[str] = set()
    overlap_occurrences = 0

    for canonical, entry, source_file_id in sorted(entries, key=lambda item: item[0]):
        del canonical
        source_file_ids.append(source_file_id)
        source_blob_hashes.add(str(entry.get("sha256")))
        source_kind = str(entry.get("kind"))
        ownership = entry.get("ownership")
        structure = entry.get("structure")
        if not isinstance(ownership, dict) or not isinstance(structure, dict):
            raise EvidenceError("P2-05 file entry lacks role or structure")
        source_role = str(ownership.get("role"))
        adapter_id, adapter_status = _adapter(entry)
        if source_kind == "xml":
            measured["xml_files"] += 1
        elif source_kind == "ecf":
            measured["ecf_files"] += 1

        if structure.get("classification") == "malformed-xml":
            measured["malformed_files"] += 1
            records.append(
                _file_record(
                    source_file_id=source_file_id,
                    source_kind=source_kind,
                    source_role=source_role,
                    adapter_id=adapter_id,
                    adapter_status=adapter_status,
                    parsed=False,
                    scalar_count=0,
                    nonempty_count=0,
                    resource_count=0,
                    config_count=0,
                )
            )
            records.append(_blocker_record(source_file_id, source_kind, source_role, adapter_id))
            continue

        relative = entry.get("path")
        source_path = _safe_repo_path(sandbox, relative, "P2-05 source instance")
        scalars, repeated = _read_source_scalars(source_path, entry)
        measured["parseable_files"] += 1
        measured["ecf_repeated_assignments"] += repeated
        measured["scalar_locations"] += len(scalars)
        measured["nonempty_scalar_locations"] += sum(bool(item.value) for item in scalars)
        file_resource_count = 0
        file_config_count = 0
        try:
            for scalar in scalars:
                canonical_scalar = canonical_identity_text(scalar.value)
                asset_candidates = asset_index.get(canonical_scalar, ())
                package_candidates = tuple(
                    sorted(
                        {
                            candidate
                            for lookup_hash in package_lookup_hashes(scalar.value)
                            for candidate in package_index.get(lookup_hash, ())
                        }
                    )
                )
                config_candidates = tuple(config_index.get(canonical_scalar, ()))
                if asset_candidates and package_candidates:
                    overlap_occurrences += 1
                if asset_candidates:
                    measured["asset_identity_occurrences"] += 1
                    measured["resource_identity_occurrences"] += 1
                    file_resource_count += 1
                    records.append(
                        _candidate_record(
                            source_file_id=source_file_id,
                            source_kind=source_kind,
                            source_role=source_role,
                            scalar=scalar,
                            adapter_id=adapter_id,
                            adapter_status=adapter_status,
                            target_kind="asset",
                            candidate_ids=asset_candidates,
                            closed_reason="whole-scalar-exact-asset-identity-candidate",
                        )
                    )
                if package_candidates:
                    measured["package_identity_occurrences"] += 1
                    measured["resource_identity_occurrences"] += 1
                    measured["package_candidate_edges"] += len(package_candidates)
                    if len(package_candidates) == 1:
                        measured["package_unique_occurrences"] += 1
                    else:
                        measured["package_ambiguous_occurrences"] += 1
                    file_resource_count += 1
                    records.append(
                        _candidate_record(
                            source_file_id=source_file_id,
                            source_kind=source_kind,
                            source_role=source_role,
                            scalar=scalar,
                            adapter_id=adapter_id,
                            adapter_status=adapter_status,
                            target_kind="package",
                            candidate_ids=package_candidates,
                            closed_reason="whole-scalar-exact-package-identity-candidate-all-targets-retained",
                        )
                    )
                if config_candidates:
                    measured["config_identity_occurrences"] += 1
                    file_config_count += 1
                    records.append(
                        _candidate_record(
                            source_file_id=source_file_id,
                            source_kind=source_kind,
                            source_role=source_role,
                            scalar=scalar,
                            adapter_id=adapter_id,
                            adapter_status=adapter_status,
                            target_kind="config",
                            candidate_ids=config_candidates,
                            closed_reason="whole-scalar-exact-config-identity-candidate",
                        )
                    )
            if file_resource_count:
                resource_files.add(source_file_id)
            if file_config_count:
                config_files.add(source_file_id)
            if source_role in {"client-region-runtime-data", "client-region-nested-shadow-copy"}:
                measured["region_resource_identity_occurrences"] += file_resource_count
            if source_role == "client-runtime-or-engine":
                measured["runtime_ecf_resource_identity_occurrences"] += file_resource_count
            records.append(
                _file_record(
                    source_file_id=source_file_id,
                    source_kind=source_kind,
                    source_role=source_role,
                    adapter_id=adapter_id,
                    adapter_status=adapter_status,
                    parsed=True,
                    scalar_count=len(scalars),
                    nonempty_count=sum(bool(item.value) for item in scalars),
                    resource_count=file_resource_count,
                    config_count=file_config_count,
                )
            )
        finally:
            scalars.clear()

    if overlap_occurrences:
        raise EvidenceError("asset and package exact-identity populations overlap")
    if len(source_file_ids) != len(set(source_file_ids)):
        raise EvidenceError("file-instance coverage collapsed duplicate content blobs")
    if enforce_expected_baseline:
        _validate_baseline(measured)

    ordered_records = tuple(
        sorted(records, key=lambda record: (str(record["record"]), str(record["member_id"])))
    )
    detail_digest = hashlib.sha256()
    detail_bytes = 0
    for record in ordered_records:
        encoded = canonical_json_line(record)
        detail_digest.update(encoded)
        detail_bytes += len(encoded)

    summary: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "evidence_revision": EVIDENCE_REVISION,
        "result": "BLOCKED",
        "task": "P2-20A",
        "criterion": "G2-06",
        "scope_complete": False,
        "auxiliary_config_reference_scope_complete": False,
        "approved_semantic_roots": 0,
        "input_binding": {
            "p2_05_evidence_bytes": p205_bytes,
            "p2_05_evidence_sha256": p205_sha,
            "p2_12": asset_binding,
            "p2_13": package_binding,
            "source_file_instance_set_sha256": string_set_sha256(source_file_ids),
            "source_content_blob_set_sha256": string_set_sha256(source_blob_hashes),
        },
        "coverage": {
            "source_files": measured["source_files"],
            "source_unique_blobs": measured["source_unique_blobs"],
            "source_bytes": measured["source_bytes"],
            "xml_files": measured["xml_files"],
            "ecf_files": measured["ecf_files"],
            "parseable_files": measured["parseable_files"],
            "malformed_files": measured["malformed_files"],
            "file_instance_coverage_complete": measured["source_files"] == 212,
            "content_blob_deduplication_used_as_coverage": False,
        },
        "scalars": {
            "locations": measured["scalar_locations"],
            "nonempty": measured["nonempty_scalar_locations"],
            "ecf_repeated_assignments": measured["ecf_repeated_assignments"],
            "first_or_last_assignment_selected": False,
        },
        "candidates": {
            "resource_identity_occurrences": measured["resource_identity_occurrences"],
            "asset_identity_occurrences": measured["asset_identity_occurrences"],
            "package_identity_occurrences": measured["package_identity_occurrences"],
            "package_unique_occurrences": measured["package_unique_occurrences"],
            "package_ambiguous_occurrences": measured["package_ambiguous_occurrences"],
            "package_candidate_edges": measured["package_candidate_edges"],
            "config_identity_occurrences": measured["config_identity_occurrences"],
            "region_resource_identity_occurrences": measured[
                "region_resource_identity_occurrences"
            ],
            "runtime_ecf_resource_identity_occurrences": measured[
                "runtime_ecf_resource_identity_occurrences"
            ],
            "resource_files": len(resource_files),
            "config_files": len(config_files),
            "asset_package_overlap_occurrences": overlap_occurrences,
            "heuristic_matches": 0,
            "first_candidate_selections": 0,
        },
        "blockers": {
            "malformed_xml": measured["malformed_files"],
            "semantic_adapter_registry_approved": 0,
            "semantic_adapter_registry_required": True,
            "zero_lexical_match_is_no_reference_authority": False,
        },
        "detail": {
            "records": len(ordered_records),
            "bytes": detail_bytes,
            "sha256": detail_digest.hexdigest(),
            "contains_only_anonymous_closed_records": True,
            "approved_semantic_roots": 0,
        },
    }
    return ExtractionResult(summary=summary, records=ordered_records)


def build_lexical_evidence(
    root: Path,
    client_root: Path,
    inventory: dict[str, object],
    asset_catalog_path: Path,
    reference_graph_path: Path,
) -> dict[str, object]:
    """Stable integration API for the wrapper/report layer.

    The explicit inputs must resolve to the same files bound by the tracked
    P2-05/P2-12/P2-13 evidence.  This prevents a caller from swapping in a
    smaller population while retaining the tracked aggregate.  Returned member
    records remain anonymous and use the same deterministic order as JSONL.
    """

    repo_root = root.resolve(strict=True)
    tracked_inventory, _, _ = _load_json(repo_root / P2_05_INVENTORY, "P2-05")
    if canonical_json_bytes(inventory) != canonical_json_bytes(tracked_inventory):
        raise EvidenceError("provided P2-05 inventory differs from tracked evidence")
    source = tracked_inventory.get("source")
    if not isinstance(source, dict):
        raise EvidenceError("P2-05 sandbox binding is incomplete")
    expected_client_root = _safe_repo_path(
        repo_root, source.get("sandbox_relative_path"), "P2-05 sandbox"
    )
    if client_root.resolve(strict=True) != expected_client_root:
        raise EvidenceError("provided client root differs from the P2-05 binding")

    p212, _, _ = _load_json(repo_root / P2_12_EVIDENCE, "P2-12")
    p213, _, _ = _load_json(repo_root / P2_13_EVIDENCE, "P2-13")
    catalog = p212.get("catalog")
    graph = p213.get("graph")
    if not isinstance(catalog, dict) or not isinstance(graph, dict):
        raise EvidenceError("P2-12/P2-13 ignored input bindings are incomplete")
    expected_catalog = _safe_repo_path(repo_root, catalog.get("path"), "P2-12 catalog")
    expected_graph = _safe_repo_path(repo_root, graph.get("path"), "P2-13 graph")
    if asset_catalog_path.resolve(strict=True) != expected_catalog:
        raise EvidenceError("provided asset catalog differs from the P2-12 binding")
    if reference_graph_path.resolve(strict=True) != expected_graph:
        raise EvidenceError("provided reference graph differs from the P2-13 binding")

    result = extract_repository(repo_root, enforce_expected_baseline=True)
    file_instances = tuple(
        record
        for record in result.records
        if record.get("record") == "auxiliary_config_file_scope"
    )
    occurrences = tuple(
        record
        for record in result.records
        if record.get("record") == "auxiliary_config_reference_candidate"
    )
    blockers = tuple(
        record
        for record in result.records
        if record.get("record") == "auxiliary_config_scope_blocker"
    )
    return {
        "measured": result.summary,
        "file_instances": file_instances,
        "occurrences": occurrences,
        "blockers": blockers,
    }


def run_self_test(repo_root: Path | str) -> Mapping[str, object]:
    assertions = run_common_self_test()
    result = extract_repository(repo_root, enforce_expected_baseline=True)
    assertions += 1
    assert result.detail_sha256() == result.summary["detail"]["sha256"]  # type: ignore[index]
    assertions += 1
    assert all(record.get("closed_record") is True for record in result.records)
    assertions += 1
    candidates = [
        record
        for record in result.records
        if record.get("record") == "auxiliary_config_reference_candidate"
    ]
    assert all(record.get("semantic_root_approved") is False for record in candidates)
    assertions += 1
    assert len([r for r in result.records if r.get("record") == "auxiliary_config_file_scope"]) == 212
    assertions += 1
    assert len([r for r in result.records if r.get("record") == "auxiliary_config_scope_blocker"]) == 6
    assertions += 1
    # Re-sorting must be byte-identical; this guards caller-side ordering drift.
    reversed_records = tuple(reversed(result.records))
    resorted = tuple(sorted(reversed_records, key=lambda r: (str(r["record"]), str(r["member_id"]))))
    assert b"".join(canonical_json_line(r) for r in resorted) == result.detail_jsonl_bytes()
    assertions += 1
    return {
        "result": "PASS",
        "assertions": assertions,
        "evidence_revision": EVIDENCE_REVISION,
        "source_files": result.summary["coverage"]["source_files"],  # type: ignore[index]
        "resource_identity_occurrences": result.summary["candidates"][  # type: ignore[index]
            "resource_identity_occurrences"
        ],
        "config_identity_occurrences": result.summary["candidates"][  # type: ignore[index]
            "config_identity_occurrences"
        ],
        "malformed_xml": result.summary["blockers"]["malformed_xml"],  # type: ignore[index]
        "approved_semantic_roots": 0,
        "scope_complete": False,
        "detail_records": result.summary["detail"]["records"],  # type: ignore[index]
        "detail_sha256": result.summary["detail"]["sha256"],  # type: ignore[index]
    }


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate only redacted, candidate-only G2 auxiliary-config evidence."
    )
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--summary", action="store_true")
    arguments = parser.parse_args(argv)
    try:
        if arguments.self_test:
            output = run_self_test(arguments.repo_root)
        else:
            output = extract_repository(arguments.repo_root).summary
        sys.stdout.buffer.write(canonical_json_bytes(output) + b"\n")
        return 0
    except (EvidenceError, AssertionError, OSError) as error:
        if isinstance(error, OSError):
            message = "filesystem evidence input is unavailable or unreadable"
        elif isinstance(error, AssertionError):
            message = "self-test assertion failed"
        else:
            message = str(error)
        safe = {
            "result": "FAIL_CLOSED",
            "error_type": type(error).__name__,
            "message": message,
        }
        sys.stderr.buffer.write(canonical_json_bytes(safe) + b"\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
