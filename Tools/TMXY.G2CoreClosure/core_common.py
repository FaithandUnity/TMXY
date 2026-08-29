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


def validate_auxiliary_evidence(document: dict[str, Any], source_build: str) -> None:
    """Validate the intentionally BLOCKED P2-20A.3 supplemental evidence."""
    require(document.get("evidence_revision") == "P2-20A.3" and
            document.get("task_id") == "P2-20A" and
            document.get("criterion_id") == "G2-06" and
            document.get("source_build") == source_build,
            "Wrong auxiliary-reference evidence identity")
    require(document.get("result") == "BLOCKED" and
            document.get("review_execution_result") == "PASS" and
            document.get("task_status") == "BLOCKED" and
            document.get("completion_criteria_satisfied") is False and
            document.get("scope_complete") is False and
            document.get("g2_06_satisfied") is False and
            document.get("p3_authorized") is False,
            "Auxiliary-reference evidence did not remain fail closed")
    measured = document["measured_lexical_candidates"]
    require(measured["measurement_authority"] == "LEXICAL_ONLY" and
            measured["file_instances"] == 212 and
            measured["unique_content_bodies"] == 196 and
            measured["parsed_file_instances"] == 206 and
            measured["malformed_file_instances"] == 6 and
            measured["scalar_positions"] == 39522 and
            measured["nonempty_scalar_positions"] == 39498 and
            measured["asset_exact_occurrences"] == 3043 and
            measured["package_exact_occurrences"] == 638 and
            measured["package_unique_occurrences"] == 218 and
            measured["package_ambiguous_occurrences"] == 420 and
            measured["package_ambiguous_candidate_edges"] == 1136 and
            measured["config_exact_edges"] == 8,
            "Auxiliary lexical measurement baseline mismatch")
    controls = document["parser_and_matching_controls"]
    require(controls["exact_complete_scalar_matching"] is True and
            controls["substring_matching"] is False and
            controls["basename_matching"] is False and
            controls["extension_only_matching"] is False and
            controls["first_candidate_selection"] is False and
            controls["ambiguous_candidates_all_retained"] is True and
            controls["malformed_implies_zero_references"] is False,
            "Auxiliary matching controls were weakened")
    states = document["adapter_state_summary"]
    require(states["file_instances"] == measured["file_instances"] and
            states["terminal_file_instances"] == 0 and
            states["nonterminal_file_instances"] == 212 and
            states["semantic_approved"] == 0 and
            states["no_ref_approved"] == 0 and
            states["candidate_only"] == 171 and
            states["malformed_blocked"] == 6 and
            states["editor_undecided"] == 35 and
            states["approved_roots"] == 0,
            "Auxiliary adapter-state baseline mismatch")
    file_instances = document["file_instances"]
    state_counts: dict[str, int] = {}
    parser_counts: dict[str, int] = {}
    instance_ids: set[str] = set()
    approved_root_sum = 0
    for item in file_instances:
        state = str(item["adapter_state"])
        parser = str(item["parser_state"])
        state_counts[state] = state_counts.get(state, 0) + 1
        parser_counts[parser] = parser_counts.get(parser, 0) + 1
        instance_ids.add(str(item["instance_sha256"]))
        approved_root_sum += int(item["approved_root_count"])
    require(len(file_instances) == 212 and len(instance_ids) == 212 and
            parser_counts == {"parsed": 206, "malformed": 6} and
            state_counts == {"candidate-only": 171, "editor-undecided": 35,
                             "malformed-blocked": 6} and
            sum(state_counts.values()) == states["file_instances"] and
            states["terminal_file_instances"] + states["nonterminal_file_instances"] == 212 and
            approved_root_sum == states["approved_roots"],
            "Auxiliary file-instance partition is incomplete or inconsistent")
    semantic = document["semantic_resolution"]
    require(semantic["status"] == "UNASSESSED" and
            all(semantic[name] is None for name in
                ("unknown_occurrences", "ambiguous_occurrences",
                 "unresolved_occurrences", "resolved_occurrences")) and
            semantic["first_candidate_selections"] == 0 and
            semantic["heuristic_target_selections"] == 0 and
            semantic["all_ambiguous_candidates_retained"] is True,
            "Auxiliary semantic state was inferred without approval")
    config_closure = document["config_closure"]
    require(config_closure["lexical_edges"] == measured["config_exact_edges"] and
            config_closure["approved_root_count"] == states["approved_roots"] and
            config_closure["approved_root_set_sha256"] is None and
            config_closure["semantic_edge_set_sha256"] is None and
            config_closure["closure_set_sha256"] is None and
            config_closure["closure_complete"] is False and
            config_closure["cycle_detection_complete"] is False and
            config_closure["cycle_count"] is None and
            config_closure["unresolved_cycle_count"] is None and
            config_closure["reason_code"] ==
            "APPROVED_ROOTS_AND_SEMANTIC_EDGES_UNAVAILABLE",
            "Auxiliary configuration closure was falsely completed")
    completion = document["completion"]
    require(completion["file_coverage_complete"] is True and
            completion["duplicate_file_instances_preserved"] is True and
            completion["duplicate_ecf_assignment_order_preserved"] is True and
            completion["all_inputs_hash_bound"] is True and
            completion["first_candidate_selection_absent"] is True and
            completion["semantic_adapters_terminal"] is False and
            completion["malformed_disposition_complete"] is False and
            completion["semantic_resolution_complete"] is False and
            completion["config_closure_complete"] is False and
            completion["cycle_detection_complete"] is False and
            completion["scope_complete"] is False and
            completion["satisfied"] is False,
            "Auxiliary completion boundary was weakened")
    authority = document["authority_boundaries"]
    require(authority["machine_candidate_is_approval"] is False and
            authority["approved_semantic_adapters"] == 0 and
            authority["approved_no_ref_files"] == 0 and
            authority["approved_roots"] == 0 and
            authority["g2_06_satisfied"] is False and
            authority["g2_approved"] is False and
            authority["p3_authorized"] is False and
            authority["release_authority"] is False,
            "Auxiliary evidence claimed unavailable authority")
    disclosure = document["disclosure"]
    require(disclosure["anonymous_hash_count_reason_only"] is True and
            all(disclosure[name] is False for name in
                ("raw_scalar_values", "key_names", "file_names", "private_source_paths",
                 "source_line_numbers", "exact_primary_keys", "exact_observed_extrema",
                 "raw_table_rows", "legacy_source_lines", "decoded_payloads")),
            "Auxiliary evidence disclosure boundary was weakened")


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
        ("auxiliary-reference-policy", "auxiliary_reference_policy", False),
        ("auxiliary-reference-schema", "auxiliary_reference_schema", False),
        ("P2-20A.3-AUX", "auxiliary_reference_evidence", False),
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
    auxiliary = documents["auxiliary_reference_evidence"]
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
    validate_auxiliary_evidence(auxiliary, policy["source_build"])
    require(auxiliary["contracts"]["policy_sha256"] ==
            sha256_file(documents["auxiliary_reference_policy_path"]),
            "Auxiliary-reference policy hash mismatch")
    require(auxiliary["contracts"]["schema_sha256"] ==
            sha256_file(documents["auxiliary_reference_schema_path"]),
            "Auxiliary-reference schema hash mismatch")
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
