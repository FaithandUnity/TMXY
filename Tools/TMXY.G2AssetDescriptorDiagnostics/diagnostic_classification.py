"""Closed effective-binding classification for P2-20A.4."""

from __future__ import annotations

from typing import Any, Callable


PROBE_FIELDS = {"asset_id", "family", "structure", "candidate_set_sha256",
                "candidates", "counts"}
CANDIDATE_FIELDS = {
    "candidate_id", "body_sha256", "descriptor", "binding", "effective_binding",
    "recovery_applied", "recovery_kind", "semantic_sha256", "effective_semantic_sha256",
    "descriptor_semantic_sha256", "identity_normalized_descriptor_semantic_sha256",
    "identity_normalized_semantic_sha256", "identity_mirror_ascii_lower_match",
}
COUNT_FIELDS = {
    "candidates", "descriptor_parsed", "descriptor_rejected", "binding_pass",
    "binding_rejected", "effective_binding_pass", "effective_binding_rejected",
    "recovery_applied", "semantic_distinct", "effective_semantic_distinct",
}


def validate_candidate(candidate: dict[str, Any], require: Callable[[bool, str], None]) -> None:
    require(set(candidate) == CANDIDATE_FIELDS, "Probe candidate record is not closed")
    require(candidate["descriptor"] in {"PARSED", "REJECTED"},
            "Unknown descriptor disposition")
    require(candidate["binding"] in {"PASS", "REJECTED"},
            "Unknown strict binding disposition")
    require(candidate["effective_binding"] in {"PASS", "REJECTED"},
            "Unknown effective binding disposition")
    for key in ("candidate_id", "body_sha256"):
        value = candidate[key]
        require(isinstance(value, str) and len(value) == 64,
                f"Candidate {key} is not a SHA-256 identity")
    exact = [candidate[name] for name in
             ("semantic_sha256", "descriptor_semantic_sha256")]
    normalized = [candidate[name] for name in
                  ("identity_normalized_descriptor_semantic_sha256",
                   "identity_normalized_semantic_sha256")]
    effective = candidate["effective_semantic_sha256"]
    require(all(value is None or (isinstance(value, str) and len(value) == 64)
                for value in exact + normalized + [effective]),
            "Candidate semantic identity is invalid")
    require((candidate["descriptor"] == "PARSED") == all(x is not None for x in exact),
            "Descriptor disposition and strict semantic identities disagree")
    require(all(x is None for x in normalized) or all(x is not None for x in normalized),
            "Normalized semantic identities are partially populated")
    require(isinstance(candidate["identity_mirror_ascii_lower_match"], bool),
            "Candidate identity mirror flag is invalid")
    require(not candidate["identity_mirror_ascii_lower_match"] or
            all(x is not None for x in normalized),
            "Matching identity mirror has no normalized semantic identities")
    require(candidate["descriptor"] == "PARSED" or candidate["binding"] == "REJECTED",
            "Rejected descriptor cannot pass strict binding")
    require((candidate["effective_binding"] == "PASS") == (effective is not None),
            "Effective binding and semantic identity disagree")
    require(isinstance(candidate["recovery_applied"], bool),
            "Recovery-applied flag is invalid")
    kind = candidate["recovery_kind"]
    require(kind in {"none", "qtx_complete_mip_chain", "anim_payload_frame_counts"},
            "Recovery kind is invalid")
    if candidate["recovery_applied"]:
        require(candidate["binding"] == "REJECTED" and
                candidate["effective_binding"] == "PASS" and kind != "none",
                "Applied recovery did not perform a rejected-to-pass transition")
    if kind == "none":
        require(not candidate["recovery_applied"] and
                candidate["binding"] == candidate["effective_binding"],
                "Unplanned candidate changed effective binding")


def classify_probe(prior: dict[str, Any], probe: dict[str, Any],
                   require: Callable[[bool, str], None],
                   sha256_lines: Callable[[Any], str],
                   probe_candidate_set_sha256: Callable[[list[str]], str]) -> dict[str, Any]:
    require(set(probe) == PROBE_FIELDS, "Probe asset record is not closed")
    require(probe["asset_id"] == prior["asset_id"] and
            probe["family"] == prior["family"] and
            probe["structure"] == prior["structure"],
            "Probe asset identity or metadata disagrees with the prior workset")
    candidates = probe["candidates"]
    require(isinstance(candidates, list) and candidates, "Probe candidate set is empty")
    for candidate in candidates:
        validate_candidate(candidate, require)
    ids = [str(item["candidate_id"]) for item in candidates]
    require(ids == sorted(ids) and len(ids) == len(set(ids)),
            "Probe candidate set is unordered or duplicated")
    require(len(ids) == int(prior["candidate_count"]) and
            sha256_lines(ids) == prior["candidate_set_sha256"],
            "Probe candidate identity set disagrees with P2-13")
    require(probe["candidate_set_sha256"] == probe_candidate_set_sha256(ids),
            "Probe candidate-set canonical digest is invalid")
    measured = {
        "candidates": len(candidates),
        "descriptor_parsed": sum(x["descriptor"] == "PARSED" for x in candidates),
        "descriptor_rejected": sum(x["descriptor"] == "REJECTED" for x in candidates),
        "binding_pass": sum(x["binding"] == "PASS" for x in candidates),
        "binding_rejected": sum(x["binding"] == "REJECTED" for x in candidates),
        "effective_binding_pass": sum(x["effective_binding"] == "PASS" for x in candidates),
        "effective_binding_rejected": sum(x["effective_binding"] == "REJECTED"
                                          for x in candidates),
        "recovery_applied": sum(bool(x["recovery_applied"]) for x in candidates),
        "semantic_distinct": len({x["semantic_sha256"] for x in candidates
                                  if x["semantic_sha256"] is not None}),
        "effective_semantic_distinct": len({x["effective_semantic_sha256"]
                                            for x in candidates
                                            if x["effective_semantic_sha256"] is not None}),
    }
    require(set(probe["counts"]) == COUNT_FIELDS and probe["counts"] == measured,
            "Probe candidate aggregates disagree with detail")
    strict_signatures = {x["semantic_sha256"] for x in candidates if x["binding"] == "PASS"}
    effective_signatures = {x["effective_semantic_sha256"] for x in candidates
                            if x["effective_binding"] == "PASS"}
    if not strict_signatures:
        strict_resolution, strict_basis = "UNRESOLVED", "NO_PRODUCTION_COMPATIBLE_CANDIDATE"
    elif measured["descriptor_rejected"] or measured["binding_rejected"]:
        strict_resolution, strict_basis = "AMBIGUOUS", "OPEN_REJECTED_CANDIDATE"
    elif len(strict_signatures) == 1:
        strict_resolution, strict_basis = "RESOLVED", "SINGLE_COMPATIBLE_SEMANTIC_CLASS"
    else:
        strict_resolution, strict_basis = "AMBIGUOUS", "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"
    if not effective_signatures:
        resolution, basis = "UNRESOLVED", "NO_PRODUCTION_COMPATIBLE_CANDIDATE"
    elif measured["descriptor_rejected"] or measured["effective_binding_rejected"]:
        resolution, basis = "AMBIGUOUS", "OPEN_REJECTED_CANDIDATE"
    elif len(effective_signatures) == 1:
        resolution, basis = "RESOLVED", "SINGLE_COMPATIBLE_SEMANTIC_CLASS"
    else:
        resolution, basis = "AMBIGUOUS", "MULTIPLE_COMPATIBLE_SEMANTIC_CLASSES"
    return {
        "asset_id": prior["asset_id"], "family": prior["family"],
        "structure": prior["structure"], "prior_resolution": prior["resolution"],
        "prior_resolution_basis": prior["resolution_basis"],
        "candidate_count": len(candidates), "candidate_set_sha256": prior["candidate_set_sha256"],
        "candidate_identity_exact": True, "production_binder_used": True,
        "heuristic_selection": False, "candidate_selected": False, "candidates": candidates,
        "counts": measured, "strict_compatible_semantic_variants": len(strict_signatures),
        "compatible_semantic_variants": len(effective_signatures),
        "strict_resolution": strict_resolution, "strict_resolution_basis": strict_basis,
        "resolution": resolution, "resolution_basis": basis,
    }
