"""Self-tests for the P2-20A.4 strict/effective classifier."""

from __future__ import annotations

import copy
from collections.abc import Callable
from typing import Any


def run_self_test(classify_probe: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]],
                  candidate_set_sha256: Callable[[list[str]], str],
                  sha256_lines: Callable[[list[str]], str]) -> dict[str, Any]:
    assertions = 0
    ids = ["b" * 64, "c" * 64]
    prior = {
        "asset_id": "a" * 64, "family": "qtx", "structure": "PASS",
        "candidate_count": 2, "candidate_set_sha256": sha256_lines(ids),
        "resolution": "AMBIGUOUS", "resolution_basis": "DIVERGENT_DESCRIPTOR_SET",
    }

    def candidate(candidate_id: str, body: str) -> dict[str, Any]:
        return {
            "candidate_id": candidate_id, "body_sha256": body * 64,
            "descriptor": "PARSED", "binding": "PASS", "effective_binding": "PASS",
            "recovery_applied": False, "recovery_kind": "none",
            "semantic_sha256": "2" * 64, "effective_semantic_sha256": "2" * 64,
            "descriptor_semantic_sha256": "5" * 64,
            "identity_normalized_descriptor_semantic_sha256": "7" * 64,
            "identity_normalized_semantic_sha256": "6" * 64,
            "identity_mirror_ascii_lower_match": False,
        }

    def counts(items: list[dict[str, Any]]) -> dict[str, int]:
        return {
            "candidates": len(items),
            "descriptor_parsed": sum(x["descriptor"] == "PARSED" for x in items),
            "descriptor_rejected": sum(x["descriptor"] == "REJECTED" for x in items),
            "binding_pass": sum(x["binding"] == "PASS" for x in items),
            "binding_rejected": sum(x["binding"] == "REJECTED" for x in items),
            "effective_binding_pass": sum(x["effective_binding"] == "PASS" for x in items),
            "effective_binding_rejected": sum(x["effective_binding"] == "REJECTED"
                                              for x in items),
            "recovery_applied": sum(bool(x["recovery_applied"]) for x in items),
            "semantic_distinct": len({x["semantic_sha256"] for x in items
                                      if x["semantic_sha256"] is not None}),
            "effective_semantic_distinct": len({x["effective_semantic_sha256"] for x in items
                                                if x["effective_semantic_sha256"] is not None}),
        }

    def probe(items: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "asset_id": prior["asset_id"], "family": "qtx", "structure": "PASS",
            "candidate_set_sha256": candidate_set_sha256(ids),
            "candidates": items, "counts": counts(items),
        }

    base = probe([candidate(ids[0], "1"), candidate(ids[1], "3")])
    if classify_probe(prior, base)["resolution"] != "RESOLVED":
        raise ValueError("equivalent case")
    assertions += 1

    divergent = copy.deepcopy(base)
    divergent["candidates"][1]["effective_semantic_sha256"] = "4" * 64
    divergent["counts"] = counts(divergent["candidates"])
    if classify_probe(prior, divergent)["resolution"] != "AMBIGUOUS":
        raise ValueError("divergent case")
    assertions += 1

    partial = copy.deepcopy(base)
    partial["candidates"][1].update({"binding": "REJECTED", "effective_binding": "REJECTED",
                                      "semantic_sha256": "4" * 64,
                                      "effective_semantic_sha256": None,
                                      "recovery_kind": "qtx_complete_mip_chain"})
    partial["counts"] = counts(partial["candidates"])
    if classify_probe(prior, partial)["resolution_basis"] != "OPEN_REJECTED_CANDIDATE":
        raise ValueError("partial effective pass was not fail-closed")
    assertions += 1

    recovered = copy.deepcopy(base)
    for item in recovered["candidates"]:
        item.update({"binding": "REJECTED", "effective_binding": "PASS",
                     "recovery_applied": True, "recovery_kind": "qtx_complete_mip_chain",
                     "effective_semantic_sha256": "9" * 64})
    recovered["counts"] = counts(recovered["candidates"])
    classified = classify_probe(prior, recovered)
    if classified["strict_resolution"] != "UNRESOLVED" or classified["resolution"] != "RESOLVED":
        raise ValueError("verified recovery transition case")
    assertions += 1

    rejected = copy.deepcopy(base)
    for item in rejected["candidates"]:
        item.update({"binding": "REJECTED", "effective_binding": "REJECTED",
                     "effective_semantic_sha256": None,
                     "recovery_kind": "qtx_complete_mip_chain"})
    rejected["counts"] = counts(rejected["candidates"])
    if classify_probe(prior, rejected)["resolution"] != "UNRESOLVED":
        raise ValueError("zero-compatible case")
    assertions += 1

    malformed = copy.deepcopy(base)
    del malformed["candidates"][0]["effective_binding"]
    try:
        classify_probe(prior, malformed)
    except ValueError:
        assertions += 1
    else:
        raise ValueError("open candidate record accepted")
    return {"result": "PASS", "assertions": assertions}
