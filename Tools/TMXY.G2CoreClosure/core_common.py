"""Deterministic primitives and input binding for P2-20A."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_lines(values: set[str] | list[str]) -> str:
    payload = ("\n".join(sorted(values)) + "\n").encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def count_lines(path: Path) -> int:
    with path.open("rb") as stream:
        return sum(1 for _ in stream)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = json.load(stream)
    require(isinstance(value, dict), f"JSON root must be an object: {path.name}")
    return value


def resolve_inside(root: Path, relative: str) -> Path:
    require(bool(relative) and "\\" not in relative, "Input path is not portable")
    candidate_path = Path(relative)
    require(not candidate_path.is_absolute() and ".." not in candidate_path.parts,
            "Input path is not repository-relative")
    candidate = (root / candidate_path).resolve()
    require(candidate.is_relative_to(root), "Input path escaped repository root")
    require(candidate.is_file(), f"Required input is missing: {relative}")
    return candidate


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = value.replace("\r\n", "\n").replace("\r", "\n")
    path.write_text(normalized, encoding="utf-8", newline="\n")


def validate_task(document: dict[str, Any], task_id: str) -> None:
    observed = document.get("task_id", document.get("task"))
    require(observed == task_id, f"Wrong task identity for {task_id}")
    require(document.get("result") == "PASS", f"Prerequisite {task_id} did not pass")
    require(document.get("task_status") == "COMPLETE", f"Prerequisite {task_id} is incomplete")
    require(document.get("completion_criteria_satisfied") is True,
            f"Prerequisite {task_id} did not satisfy completion criteria")


def bind_inputs(root: Path, policy: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    specifications = [
        ("P2-05", "p2_05", True),
        ("P2-06", "p2_06", True),
        ("P2-08", "p2_08", True),
        ("ownership-registry", "ownership_registry", False),
        ("core-registry", "core_registry", False),
        ("P2-12", "p2_12", True),
        ("asset-catalog", "asset_catalog", False),
        ("reference-policy", "reference_policy", False),
        ("P2-13", "p2_13", True),
        ("reference-graph", "reference_graph", False),
        ("P2-18", "p2_18", True),
        ("g2-policy", "g2_policy", False),
    ]
    documents: dict[str, Any] = {}
    artifacts: list[dict[str, Any]] = []
    aggregate: list[str] = []
    for artifact_id, policy_key, is_task in specifications:
        relative = str(policy["inputs"][policy_key])
        path = resolve_inside(root, relative)
        digest = sha256_file(path)
        if path.suffix == ".json":
            document = load_json(path)
            documents[policy_key] = document
            if is_task:
                validate_task(document, artifact_id)
        binding: dict[str, Any] = {
            "id": artifact_id,
            "path": relative,
            "sha256": digest,
            "bytes": path.stat().st_size,
        }
        if path.suffix == ".jsonl":
            binding["lines"] = count_lines(path)
        artifacts.append(binding)
        aggregate.append(f"{artifact_id}|{relative}|{digest}")
        documents[policy_key + "_path"] = path

    p208 = documents["p2_08"]
    p206 = documents["p2_06"]
    p212 = documents["p2_12"]
    p213 = documents["p2_13"]
    p218 = documents["p2_18"]
    reference_policy_path = documents["reference_policy_path"]
    require(p208["output"]["registry_sha256"] == sha256_file(documents["ownership_registry_path"]),
            "P2-08 ownership registry hash mismatch")
    require(p206["output"]["git_ignored"] is True and
            p206["output"]["local_root"] == "Data/Exports/P2-06",
            "P2-06 normalized source authority is not the frozen ignored export")
    require(p213["input"]["core_registry_sha256"] == sha256_file(documents["core_registry_path"]),
            "P2-13 core registry hash mismatch")
    require(p212["catalog"]["sha256"] == sha256_file(documents["asset_catalog_path"]),
            "P2-12 catalog hash mismatch")
    require(p212["catalog"]["lines"] == count_lines(documents["asset_catalog_path"]),
            "P2-12 catalog line count mismatch")
    require(p213["contracts"]["policy_sha256"] == sha256_file(reference_policy_path),
            "P2-13 reference policy hash mismatch")
    require(p213["graph"]["sha256"] == sha256_file(documents["reference_graph_path"]),
            "P2-13 graph hash mismatch")
    require(p213["graph"]["lines"] == count_lines(documents["reference_graph_path"]),
            "P2-13 graph line count mismatch")
    require(p218["summary"]["references"]["package_unresolved"] ==
            p213["health"]["package_unresolved_edges"], "P2-18 package unresolved mismatch")
    require(p218["summary"]["references"]["table_object_unresolved"] ==
            p213["health"]["nullable_object_unresolved"], "P2-18 table unresolved mismatch")
    require(all(document.get("source", {}).get("build", policy["source_build"]) ==
                policy["source_build"] for document in
                (documents["p2_05"], documents["p2_08"])), "Source build mismatch")

    g2_policy = documents["g2_policy"]
    g2_criterion = next(item for item in g2_policy["criteria"] if item["id"] == "G2-06")
    require(g2_criterion["required_status"] == "SATISFIED", "G2-06 exit status was weakened")
    require(g2_policy["thresholds"]["core_resource_unresolved"] == 0 and
            g2_policy["thresholds"]["core_resource_ambiguous"] == 0,
            "G2-06 zero thresholds were weakened")
    fail_rules = g2_policy["fail_closed_rules"]
    require(fail_rules["core_foreign_key_zero_does_not_prove_core_resource_reference_zero"] is True,
            "G2 core-foreign-key distinction was weakened")
    require(fail_rules["core_resource_subset_and_explicit_metrics_are_required"] is True,
            "G2 explicit core subset requirement was weakened")

    aggregate_sha = hashlib.sha256(("\n".join(aggregate) + "\n").encode("utf-8")).hexdigest()
    return {"aggregate_sha256": aggregate_sha, "artifacts": artifacts}, documents
