"""Deterministic anonymous package-to-asset binding evidence for P2-20A."""

from __future__ import annotations

import collections
import hashlib
import json
from pathlib import Path
from typing import Any

from core_common import canonical_json, require, sha256_lines, write_text


FIELDS = {
    "asset_id", "candidate_count", "candidate_set_sha256", "descriptor_variants",
    "family", "heuristic_selection", "resolution", "resolution_basis", "structure",
    "valid_variants",
}
RESOLUTIONS = {"RESOLVED", "AMBIGUOUS", "UNRESOLVED"}
BASES = {
    "UNIQUE_VALID_DESCRIPTOR",
    "EQUIVALENT_VALID_DESCRIPTOR_SET",
    "SELF_DESCRIBING_RULE",
    "DIVERGENT_DESCRIPTOR_SET",
    "DESCRIPTOR_VALIDATION_FAILED",
    "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES",
    "NO_PRODUCTION_COMPATIBLE_CANDIDATE",
    "OPEN_REJECTED_CANDIDATE",
    "SINGLE_COMPATIBLE_SEMANTIC_CLASS",
}


def stable_id(namespace: str, *parts: str) -> str:
    payload = namespace + "\0" + "\0".join(parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_asset_binding_workset(policy: dict[str, Any], catalog_path: Path,
                                graph: dict[str, Any], effective_detail_path: Path,
                                base_output: Path, output: Path,
                                expected_base_sha256: str) -> dict[str, Any]:
    reachable_assets = {
        identity for identity in graph["reachable"]
        if graph["node_kind"].get(identity) == "asset_node"
    }
    catalog_assets: dict[str, dict[str, Any]] = {}
    with catalog_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            asset = json.loads(line)
            identity = stable_id("asset", str(asset["path"]), str(asset["sha256"]))
            if identity in reachable_assets:
                require(identity not in catalog_assets,
                        "Reachable asset identity is duplicated in the catalog")
                catalog_assets[identity] = asset

    require(set(catalog_assets) == reachable_assets,
            "Reachable asset set is not exactly reproduced from P2-12")
    effective: dict[str, dict[str, Any]] = {}
    with effective_detail_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            item = json.loads(line)
            identity = str(item["asset_id"])
            require(identity not in effective and identity in reachable_assets,
                    "P2-20A.4 effective target is duplicated or unreachable")
            require(item["resolution"] in RESOLUTIONS and
                    item["candidate_selected"] is False and
                    item["heuristic_selection"] is False and
                    item["production_binder_used"] is True,
                    "P2-20A.4 effective target state is not fail closed")
            effective[identity] = item
    require(len(effective) == 3651,
            "P2-20A.4 effective specialized target set is incomplete")
    allowed_families = set(policy["asset_binding_scope"]["families"])
    base_records: list[dict[str, Any]] = []
    records: list[dict[str, Any]] = []
    by_family: dict[str, collections.Counter[str]] = collections.defaultdict(
        collections.Counter
    )
    candidate_edges = 0
    for identity in sorted(reachable_assets):
        asset = catalog_assets[identity]
        family = str(asset["family"])
        structure = str(asset["structure"])
        require(family in allowed_families, "Reachable asset family is outside policy")
        require(graph["asset_family"].get(identity) == family and
                graph["asset_structure"].get(identity) == structure,
                "P2-12 and P2-13 asset metadata disagree")
        candidates = sorted(graph["asset_candidates"].get(identity, set()))
        require(candidates, "Reachable asset has no package binding candidate")
        if family in {"qtx", "sm", "skem", "anim"} and structure != "FAIL":
            require(len(candidates) == int(asset["package_candidates"]),
                    "Reachable asset candidate count disagrees with P2-12")
        descriptor_variants = int(asset["descriptor_variants"])
        valid_variants = int(asset["valid_variants"])
        package_state = str(asset["package_state"])
        if family in {"ter", "wav"}:
            resolution, basis = "RESOLVED", "SELF_DESCRIBING_RULE"
        elif package_state == "unique" and valid_variants > 0:
            resolution, basis = "RESOLVED", "UNIQUE_VALID_DESCRIPTOR"
        elif package_state == "ambiguous_equivalent" and valid_variants > 0:
            resolution, basis = "RESOLVED", "EQUIVALENT_VALID_DESCRIPTOR_SET"
        elif package_state == "ambiguous_divergent":
            resolution, basis = "AMBIGUOUS", "DIVERGENT_DESCRIPTOR_SET"
        elif package_state == "no_valid_variant":
            resolution, basis = "UNRESOLVED", "DESCRIPTOR_VALIDATION_FAILED"
        else:
            raise ValueError("Reachable asset has an unclassified binding state")
        base_records.append({
            "asset_id": identity,
            "candidate_count": len(candidates),
            "candidate_set_sha256": sha256_lines(candidates),
            "descriptor_variants": descriptor_variants,
            "family": family,
            "heuristic_selection": False,
            "resolution": resolution,
            "resolution_basis": basis,
            "structure": structure,
            "valid_variants": valid_variants,
        })
        if identity in effective:
            observed = effective[identity]
            require(int(observed["candidate_count"]) == len(candidates) and
                    observed["candidate_set_sha256"] == sha256_lines(candidates),
                    "P2-20A.4 effective candidate set drifted from core closure")
            resolution = str(observed["resolution"])
            basis = str(observed["resolution_basis"])
        record = {
            "asset_id": identity,
            "candidate_count": len(candidates),
            "candidate_set_sha256": sha256_lines(candidates),
            "descriptor_variants": descriptor_variants,
            "family": family,
            "heuristic_selection": False,
            "resolution": resolution,
            "resolution_basis": basis,
            "structure": structure,
            "valid_variants": valid_variants,
        }
        require(set(record) == FIELDS and resolution in RESOLUTIONS and basis in BASES,
                "Asset binding workset record is not closed")
        records.append(record)
        candidate_edges += len(candidates)
        by_family[family]["assets"] += 1
        by_family[family][resolution.lower()] += 1
        by_family[family]["candidate_edges"] += len(candidates)

    base_lines = [canonical_json(item) for item in base_records]
    base_targets = collections.Counter(item["resolution"].lower()
                                       for item in base_records)
    base_edges = collections.Counter()
    for item in base_records:
        base_edges[item["resolution"].lower()] += item["candidate_count"]
    require(base_targets == {"resolved": 21292, "ambiguous": 183, "unresolved": 19} and
            base_edges == {"resolved": 38793, "ambiguous": 534, "unresolved": 24} and
            sha256_lines(base_lines) == expected_base_sha256,
            "Strict base asset-binding workset drifted from A.4 input evidence")
    write_text(base_output, "\n".join(base_lines) + "\n")

    lines = [canonical_json(item) for item in records]
    require(len(records) == len(reachable_assets) and
            len({item["asset_id"] for item in records}) == len(records),
            "Asset binding workset is incomplete or duplicated")
    write_text(output, "\n".join(lines) + "\n")
    target_counts = collections.Counter(item["resolution"].lower() for item in records)
    edge_counts = collections.Counter()
    basis_targets = collections.Counter()
    basis_edges = collections.Counter()
    for item in records:
        edge_counts[item["resolution"].lower()] += item["candidate_count"]
        basis_targets[item["resolution_basis"]] += 1
        basis_edges[item["resolution_basis"]] += item["candidate_count"]
    require(target_counts == {"resolved": 21293, "ambiguous": 189, "unresolved": 12} and
            edge_counts == {"resolved": 38790, "ambiguous": 546, "unresolved": 15},
            "Asset binding classification drifted from the frozen evidence")
    return {
        "resolution_explicit": True,
        "reachable_assets": len(records),
        "resolved_targets": target_counts["resolved"],
        "ambiguous_targets": target_counts["ambiguous"],
        "unresolved_targets": target_counts["unresolved"],
        "unknown_targets": 0,
        "candidate_edges": candidate_edges,
        "resolved_edges": edge_counts["resolved"],
        "ambiguous_edges": edge_counts["ambiguous"],
        "unresolved_edges": edge_counts["unresolved"],
        "unknown_edges": 0,
        "by_resolution_basis_targets": dict(sorted(basis_targets.items())),
        "by_resolution_basis_edges": dict(sorted(basis_edges.items())),
        "workset_exported": True,
        "workset_count": len(records),
        "workset_sha256": sha256_lines(lines),
        "by_family": {
            family: dict(sorted(counts.items()))
            for family, counts in sorted(by_family.items())
        },
        "first_candidate_selection_used": False,
    }
