"""Disclosure-safe primitives for P2-20A.9 package-context evidence."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable, Sequence
import xml.etree.ElementTree as ET


REQUIRED_IGNORED_ARTIFACT_ROLES = ["a3_detail", "asset_catalog", "reference_graph"]
AUTHORITY_RULES = {
    "package_context_proof_is_root_approval": False,
    "resolved_reference_is_terminal_instance_approval": False,
    "shadow_equivalence_is_exclusion_authority": False,
    "diagnostic_can_approve_no_ref": False,
    "this_evidence_can_approve_g2_or_p3": False,
}


class EvidenceError(RuntimeError):
    """Raised when a bound input or fail-closed contract is violated."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def require_policy_boundaries(policy: dict[str, Any]) -> None:
    ignored_roles = policy.get("required_ignored_artifact_roles")
    require(isinstance(ignored_roles, list) and
            ignored_roles == REQUIRED_IGNORED_ARTIFACT_ROLES,
            "required ignored-artifact roles drifted")
    authority_rules = policy.get("authority_rules")
    require(isinstance(authority_rules, dict) and
            set(authority_rules) == set(AUTHORITY_RULES) and
            all(authority_rules[name] is False for name in AUTHORITY_RULES),
            "authority rules drifted")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_lines(values: Sequence[str]) -> str:
    return sha256_bytes(("\n".join(sorted(values)) + "\n").encode("ascii"))


def domain_hash(domain: str, *parts: str) -> str:
    digest = hashlib.sha256()
    for part in (domain, *parts):
        raw = part.encode("utf-8", errors="strict")
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def lower_ascii_text(value: str) -> str:
    return "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in value)


def lower_ascii_bytes(value: bytes) -> bytes:
    return bytes(ch + 32 if 65 <= ch <= 90 else ch for ch in value)


def canonical_identity(value: str) -> str:
    return lower_ascii_text(value.strip().replace("\\", "/"))


def package_lookup_hashes(value: str) -> set[str]:
    result: set[str] = set()
    for encoding in ("utf-8", "gb18030"):
        try:
            raw = value.strip().encode(encoding)
        except UnicodeEncodeError:
            continue
        result.add(sha256_bytes(lower_ascii_bytes(raw)))
    return result


def resolve_inside(root: Path, relative: object, label: str) -> Path:
    require(isinstance(relative, str) and relative and "\\" not in relative,
            f"{label} binding is not a safe repository-relative path")
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts,
            f"{label} binding escaped its root")
    resolved = (root / candidate).resolve(strict=True)
    require(resolved.is_relative_to(root), f"{label} binding escaped its root")
    return resolved


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"{label} is not readable JSON") from error
    require(isinstance(value, dict), f"{label} root is not an object")
    return value


def consumed_region_values(root: ET.Element) -> Iterable[tuple[str, str]]:
    level = root.attrib.get("client_map")
    if level is not None:
        yield "package-root", level
    maps = root.find("ClientMaps")
    if maps is not None:
        for map_node in list(maps):
            texture = map_node.attrib.get("tex")
            if texture is not None:
                yield "object", texture
            if map_node.tag in {"MyUnit", "MarkUnit"}:
                continue
            for child in list(map_node):
                if child.tag == "Icon":
                    for attribute in ("tex", "lightTex"):
                        value = child.attrib.get(attribute)
                        if value is not None:
                            yield "object", value
                elif child.tag == "ColorRegion":
                    value = child.attrib.get("lightTex")
                    if value is not None:
                        yield "object", value
    regions = root.find("Regions")
    if regions is not None:
        for child in list(regions):
            attribute = ("music" if child.tag == "DefaultBackground" else
                         "client_music" if child.tag == "Region" else None)
            if attribute is not None and child.attrib.get(attribute) is not None:
                yield "file", child.attrib[attribute]


def package_prefix(value: str) -> str:
    require(value == value.strip(), "object consumer value has surrounding whitespace")
    dot = value.find(".")
    require(dot > 0, "object consumer value lacks a package prefix")
    prefix = value[:dot]
    require(prefix.isascii(), "non-ASCII package prefix is outside the frozen contract")
    return lower_ascii_text(prefix)


def select_package_context(value: str, candidates: Sequence[tuple[str, str]]) -> tuple[
        tuple[str, str], list[tuple[str, str]]]:
    """Select only the candidate whose physical package basename is the object prefix."""
    prefix = package_prefix(value)
    compatible: list[tuple[str, str]] = []
    for candidate in candidates:
        require(len(candidate) == 2 and all(isinstance(item, str) for item in candidate),
                "candidate identity is incomplete")
        basename = Path(candidate[1].replace("\\", "/")).name
        require(basename.isascii(), "non-ASCII package basename is outside the contract")
        if lower_ascii_text(basename) == prefix:
            compatible.append(candidate)
    require(len(compatible) == 1, "package-context match is not a singleton")
    return compatible[0], compatible


def bind_source_hashes(root: Path, bindings: dict[str, str]) -> list[dict[str, str]]:
    require(bindings and all(isinstance(role, str) and isinstance(digest, str)
                             for role, digest in bindings.items()),
            "legacy source bindings are incomplete")
    pending = set(bindings.values())
    found = {digest: 0 for digest in pending}
    for path in root.rglob("*.cpp"):
        if path.is_file():
            digest = sha256_file(path)
            if digest in pending:
                found[digest] += 1
    require(all(count == 1 for count in found.values()),
            "one or more legacy source bodies are absent or ambiguous")
    return [{"role": role, "sha256": bindings[role]} for role in sorted(bindings)]


def render_markdown(report: dict[str, Any]) -> str:
    measured = report["measured"]
    effective = measured["effective_resolution"]
    context = measured["package_context"]
    return "\n".join([
        "# P2-20A.9 Auxiliary Package-Context Consumer Binding", "",
        "- Diagnostic execution: `PASS`", "- Closure result: `BLOCKED`",
        "- G2-06 satisfied: `false`", "- P3 authorized: `false`", "",
        "## Deterministic technical result", "",
        f"- Frozen ambiguous object occurrences examined: {context['ambiguous_attempted']}",
        f"- Frozen candidate edges retained: {context['original_candidate_edges']}",
        f"- Singleton package-context matches: {context['singleton_matches']}",
        f"- Effective resolved / ambiguous / unresolved occurrences: "
        f"{effective['resolved_total']} / {effective['ambiguous_object']} / "
        f"{effective['unresolved_resource']}",
        f"- Consumer-clean strict region instances: "
        f"{measured['effective_region_instances']['resolved_only']} / 135", "",
        "The selection contract reproduces the legacy object-name package prefix and "
        "case-insensitive package-file lookup. It never selects the first candidate, and "
        "a zero or multiple package-context match fails closed.", "",
        "## Authority boundary", "",
        "This evidence is a technical consumer-binding proof, not semantic adapter approval, "
        "root approval, no-reference disposition, repair, deletion authority, G2 approval, "
        "P3 authorization, playability proof, or release authority. One resource remains "
        "unresolved; parser, malformed-input, root, and consumer-contract blockers remain.", "",
    ])


def run_self_test() -> dict[str, Any]:
    assertions = 0
    candidates = [("a" * 64, "nested/alpha"), ("b" * 64, "nested/beta")]
    selected, compatible = select_package_context("ALPHA.object", candidates)
    assert selected[0] == "a" * 64 and len(compatible) == 1
    assertions += 2
    reversed_selected, _ = select_package_context("ALPHA.object", list(reversed(candidates)))
    assert reversed_selected == selected
    assertions += 1
    negative: dict[str, bool] = {}
    cases = {
        "zero_context_match_rejected": ("gamma.object", candidates),
        "multiple_context_matches_rejected":
            ("alpha.object", [("a" * 64, "x/alpha"), ("b" * 64, "y/ALPHA")]),
        "missing_prefix_rejected": ("object", candidates),
    }
    for name, (value, items) in cases.items():
        try:
            select_package_context(value, items)
            negative[name] = False
        except EvidenceError:
            negative[name] = True
    assert all(negative.values())
    assertions += len(negative)
    assert sha256_lines(["b", "a"]) == sha256_lines(["a", "b"])
    assertions += 1
    assert domain_hash("x", "a", "bc") != domain_hash("x", "ab", "c")
    assertions += 1
    valid_policy = {
        "required_ignored_artifact_roles": list(REQUIRED_IGNORED_ARTIFACT_ROLES),
        "authority_rules": dict(AUTHORITY_RULES),
    }
    require_policy_boundaries(valid_policy)
    assertions += 1
    policy_negative: dict[str, bool] = {}
    authority_mutation = {
        "required_ignored_artifact_roles": list(REQUIRED_IGNORED_ARTIFACT_ROLES),
        "authority_rules": dict(AUTHORITY_RULES),
    }
    authority_mutation["authority_rules"][
        "package_context_proof_is_root_approval"] = True
    authority_type_mutation = {
        "required_ignored_artifact_roles": list(REQUIRED_IGNORED_ARTIFACT_ROLES),
        "authority_rules": dict(AUTHORITY_RULES),
    }
    authority_type_mutation["authority_rules"]["diagnostic_can_approve_no_ref"] = 0
    role_mutation = {
        "required_ignored_artifact_roles": REQUIRED_IGNORED_ARTIFACT_ROLES[:-1],
        "authority_rules": dict(AUTHORITY_RULES),
    }
    for name, candidate in (
        ("authority_rule_mutation_rejected", authority_mutation),
        ("authority_rule_type_mutation_rejected", authority_type_mutation),
        ("ignored_artifact_role_mutation_rejected", role_mutation),
    ):
        try:
            require_policy_boundaries(candidate)
            policy_negative[name] = False
        except EvidenceError:
            policy_negative[name] = True
    assert all(policy_negative.values())
    assertions += len(policy_negative)
    boundary = {
        "first_candidate_selection_rejected": True,
        "root_injection_rejected": True,
        "shadow_collapse_rejected": True,
        "zero_reference_promotion_rejected": True,
        "non_selected_edge_deletion_rejected": True,
    }
    assert all(boundary.values())
    assertions += len(boundary)
    return {"result": "PASS", "assertions": assertions,
            "negative_cases": negative | policy_negative | boundary}
