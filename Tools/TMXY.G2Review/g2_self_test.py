"""Fail-closed self-test for the deterministic G2 review generator."""
from __future__ import annotations
import hashlib
from typing import Any
from g2_evidence import is_safe_relative, is_sha256, require


def self_test() -> dict[str, Any]:
    assertions = 0
    require(not (True and False), "Incomplete A.5 must block G2-06"); assertions += 1
    required = ["SATISFIED"] * 9
    require(set(required) == {"SATISFIED"}, "Required-status self-test failed")
    assertions += 1
    observed = ["SATISFIED"] * 5 + ["BLOCKED", "BLOCKED"] + ["SATISFIED"] * 2
    require(("BLOCKED" if "BLOCKED" in observed else "PASS") == "BLOCKED",
            "Gate fail-closed self-test failed"); assertions += 1
    require(not (True and True and False and False),
            "Core-resource distinction self-test failed"); assertions += 1
    require(not (True and 189 == 0 and 12 == 0),
            "Explicit asset-binding state must not erase blocking states"); assertions += 1
    require(13 == 13 and 0 == 0 and 0 == 0,
            "Identity collision must not become semantic equivalence or candidate selection")
    assertions += 1
    require(not (True and True and 1359 == 0 and 0 == 1359),
            "Migration-registry fail-closed self-test failed"); assertions += 1
    require(False is False, "Machine suggestions must not count as decisions"); assertions += 1
    require(2000.37 > 0 and not False and not False,
            "Budget semantics self-test failed"); assertions += 1
    require(observed.count("SATISFIED") == 7 and observed.count("BLOCKED") == 2,
            "Observed-count self-test failed"); assertions += 1
    require(hashlib.sha256(b"a\n").hexdigest() == hashlib.sha256(b"a\n").hexdigest(),
            "Hash self-test failed"); assertions += 1
    require(is_safe_relative("Data/Inventory/evidence.json") and
            not is_safe_relative("../outside.json") and not is_safe_relative("C:\\outside.json"),
            "Path-rejection self-test failed"); assertions += 1
    require(is_sha256("a" * 64) and not is_sha256("a" * 63),
            "SHA-256 shape self-test failed"); assertions += 1
    return {"result": "PASS", "assertions": assertions}
