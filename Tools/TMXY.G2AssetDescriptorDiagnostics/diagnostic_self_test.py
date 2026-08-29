"""Self-tests for the P2-20A.4 descriptor diagnostic classifier."""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any


def run_self_test(classify_probe: Callable[[dict[str, Any], dict[str, Any]], dict[str, Any]],
                  candidate_set_sha256: Callable[[list[str]], str],
                  sha256_lines: Callable[[list[str]], str]) -> dict[str, Any]:
    assertions = 0
    prior = {
        "asset_id": "a" * 64, "family": "qtx", "structure": "PASS",
        "candidate_count": 2, "candidate_set_sha256": sha256_lines(["b" * 64, "c" * 64]),
        "resolution": "AMBIGUOUS", "resolution_basis": "DIVERGENT_DESCRIPTOR_SET",
    }
    candidate = {
        "descriptor": "PARSED", "binding": "PASS", "semantic_sha256": "2" * 64,
        "descriptor_semantic_sha256": "5" * 64,
        "identity_normalized_descriptor_semantic_sha256": "7" * 64,
        "identity_normalized_semantic_sha256": "6" * 64,
        "identity_mirror_ascii_lower_match": False,
    }
    base = {
        "asset_id": "a" * 64, "family": "qtx", "structure": "PASS",
        "candidate_set_sha256": candidate_set_sha256(["b" * 64, "c" * 64]),
        "candidates": [
            candidate | {"candidate_id": "b" * 64, "body_sha256": "1" * 64},
            candidate | {"candidate_id": "c" * 64, "body_sha256": "3" * 64},
        ],
        "counts": {"candidates": 2, "descriptor_parsed": 2, "descriptor_rejected": 0,
                   "binding_pass": 2, "binding_rejected": 0, "semantic_distinct": 1},
    }
    if classify_probe(prior, base)["resolution"] != "RESOLVED":
        raise ValueError("equivalent case")
    assertions += 1
    divergent = json.loads(json.dumps(base))
    divergent["candidates"][1]["semantic_sha256"] = "4" * 64
    divergent["counts"]["semantic_distinct"] = 2
    if classify_probe(prior, divergent)["resolution"] != "AMBIGUOUS":
        raise ValueError("divergent case")
    assertions += 1
    unreadable = json.loads(json.dumps(base))
    unreadable["candidates"][1].update({
        "descriptor": "REJECTED", "binding": "REJECTED", "semantic_sha256": None,
        "descriptor_semantic_sha256": None,
        "identity_normalized_descriptor_semantic_sha256": None,
        "identity_normalized_semantic_sha256": None,
    })
    unreadable["counts"] = {"candidates": 2, "descriptor_parsed": 1,
                            "descriptor_rejected": 1, "binding_pass": 1,
                            "binding_rejected": 1, "semantic_distinct": 1}
    if classify_probe(prior, unreadable)["resolution_basis"] != "UNREADABLE_CANDIDATE_OPEN":
        raise ValueError("unreadable fail-closed case")
    assertions += 1
    rejected = json.loads(json.dumps(base))
    for item in rejected["candidates"]:
        item["binding"] = "REJECTED"
    rejected["counts"].update({"binding_pass": 0, "binding_rejected": 2})
    if classify_probe(prior, rejected)["resolution"] != "UNRESOLVED":
        raise ValueError("zero-compatible case")
    assertions += 1
    missing_normalized = json.loads(json.dumps(base))
    del missing_normalized["candidates"][0]["identity_normalized_semantic_sha256"]
    try:
        classify_probe(prior, missing_normalized)
    except ValueError:
        assertions += 1
    else:
        raise ValueError("missing normalized semantic identity accepted")
    return {"result": "PASS", "assertions": assertions}
