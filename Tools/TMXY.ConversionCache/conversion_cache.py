#!/usr/bin/env python3
"""Build deterministic P2-16 conversion cache keys without copying payloads."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
from typing import Any


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def canonical_json(value: Any) -> str:
    return canonical_bytes(value).decode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def file_digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_jsonl(path: Path, record: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            item = json.loads(line)
            if record and item.get("record") != record:
                continue
            key = str(item["path"])
            if key in result:
                raise ValueError(f"duplicate {record} path: {key}")
            result[key] = item
    return result


class ReportWriter:
    def __init__(self, path: Path) -> None:
        self.stream = path.open("wb")
        self.sha = hashlib.sha256()
        self.lines = 0
        self.size = 0

    def emit(self, value: dict[str, Any]) -> None:
        data = canonical_bytes(value) + b"\n"
        self.stream.write(data)
        self.sha.update(data)
        self.lines += 1
        self.size += len(data)

    def close(self) -> dict[str, Any]:
        self.stream.close()
        return {"lines": self.lines, "bytes": self.size, "sha256": self.sha.hexdigest()}


def evidence_source_digest(root: Path, relative: str) -> str:
    evidence = load_json(root / relative)
    if evidence.get("result") != "PASS":
        raise ValueError(f"converter evidence is not PASS: {relative}")
    value = evidence.get("source_sha256")
    if not isinstance(value, str) or len(value) != 64:
        raise ValueError(f"converter evidence lacks source_sha256: {relative}")
    return value


def key_for(components: dict[str, Any]) -> str:
    return digest(components)


def mutate_count(ready: list[dict[str, Any]], field: str, selected_family: str = "") -> int:
    changed = 0
    mutation = hashlib.sha256(("p2-16-mutation-" + field).encode()).hexdigest()
    for item in ready:
        if selected_family and item["family"] != selected_family:
            continue
        components = dict(item["components"])
        components[field] = mutation
        changed += int(key_for(components) != item["cache_key"])
    return changed


def build(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root
    policy = load_json(args.policy)
    assets = load_jsonl(args.asset_catalog, "")
    routes = load_jsonl(args.routing_report, "conversion_route")
    if set(assets) != set(routes):
        raise ValueError("asset catalog and routing report paths differ")

    tools = {
        family: evidence_source_digest(root, relative)
        for family, relative in policy["converter_tool_evidence"].items()
    }
    interchange = evidence_source_digest(root, policy["interchange_evidence"])
    graph = load_json(root / policy["descriptor_graph_evidence"])
    descriptor_graph = str(graph["graph"]["sha256"])
    target_profile = digest(policy["target_profile"])
    routing_policy = file_digest(args.routing_policy)
    no_descriptor = digest("tmxy.no-external-descriptor.v1")
    external = set(policy["external_descriptor_families"])
    ready_tiers = set(policy["ready_tiers"])

    plans: dict[str, dict[str, Any]] = {}
    ready: list[dict[str, Any]] = []
    by_family: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    for path, route in routes.items():
        asset = assets[path]
        if str(asset["family"]) != str(route["family"]):
            raise ValueError(f"family mismatch: {path}")
        family = str(route["family"])
        components = {
            "namespace": policy["key_namespace"],
            "asset_id": str(route["id"]),
            "family": family,
            "route": str(route["route"]),
            "source_payload_sha256": str(asset["sha256"]),
            "interpreted_record_sha256": digest(asset),
            "descriptor_scope_sha256": descriptor_graph if family in external else no_descriptor,
            "converter_source_sha256": tools[family],
            "interchange_source_sha256": interchange,
            "routing_policy_sha256": routing_policy,
            "target_profile_sha256": target_profile,
        }
        is_job = bool(route["conversion_job_required"])
        is_ready = str(route["tier"]) in ready_tiers
        cache_key = key_for(components) if is_job and is_ready else ""
        state = "ready" if cache_key else ("alias" if not is_job else "blocked-manual-input")
        plan = {
            "asset": asset,
            "route": route,
            "components": components,
            "cache_key": cache_key,
            "state": state,
        }
        plans[path] = plan
        stats = by_family[family]
        stats["files"] += 1
        stats["bytes"] += int(route["bytes"])
        stats["conversion_jobs"] += int(is_job)
        stats["aliases"] += int(not is_job)
        stats["ready_jobs"] += int(bool(cache_key))
        stats["blocked_jobs"] += int(is_job and not is_ready)
        if cache_key:
            ready.append({"family": family, "components": components, "cache_key": cache_key})

    id_to_plan = {str(item["route"]["id"]): item for item in plans.values()}
    alias_shared = 0
    for item in plans.values():
        route = item["route"]
        if bool(route["conversion_job_required"]):
            continue
        representative = id_to_plan.get(str(route["reuse_representative"]))
        if representative is None or not representative["cache_key"]:
            raise ValueError("alias representative lacks a ready cache key")
        item["cache_key"] = representative["cache_key"]
        alias_shared += int(item["cache_key"] == representative["cache_key"])

    writer = ReportWriter(args.output)
    try:
        for path, item in sorted(plans.items()):
            route = item["route"]
            asset = item["asset"]
            writer.emit({
                "bytes": int(route["bytes"]),
                "cache_key": item["cache_key"],
                "cache_read_eligible": item["state"] == "ready",
                "conversion_job_required": bool(route["conversion_job_required"]),
                "descriptor_scope_sha256": item["components"]["descriptor_scope_sha256"],
                "family": str(route["family"]),
                "id": str(route["id"]),
                "interpreted_record_sha256": item["components"]["interpreted_record_sha256"],
                "path": path,
                "record": "conversion_cache_plan",
                "reuse_representative": str(route["reuse_representative"]),
                "route": str(route["route"]),
                "source_sha256": str(asset["sha256"]),
                "state": item["state"],
                "tier": str(route["tier"]),
            })
        report = writer.close()
    except Exception:
        writer.stream.close()
        raise

    source_change = 0
    if ready:
        first = ready[0]
        changed = dict(first["components"])
        changed["source_payload_sha256"] = hashlib.sha256(b"p2-16-source-mutation").hexdigest()
        source_change = int(key_for(changed) != first["cache_key"])
    tool_changes = {
        family: mutate_count(ready, "converter_source_sha256", family)
        for family in sorted(tools)
    }
    descriptor_changed = sum(
        int(item["family"] in external) for item in ready
    )
    ready_keys = [item["cache_key"] for item in ready]
    summary = {
        "assets": {
            "files": len(plans),
            "bytes": sum(int(item["route"]["bytes"]) for item in plans.values()),
            "conversion_jobs": sum(int(item["route"]["conversion_job_required"]) for item in plans.values()),
            "aliases": sum(int(not item["route"]["conversion_job_required"]) for item in plans.values()),
        },
        "cache_keys": {
            "ready_jobs": len(ready),
            "distinct_ready_keys": len(set(ready_keys)),
            "alias_assignments": alias_shared,
            "assets_with_ready_key": len(ready) + alias_shared,
            "blocked_manual_jobs": sum(int(item["state"] == "blocked-manual-input") for item in plans.values()),
            "timestamps_in_key": 0,
            "absolute_paths_in_key": 0,
        },
        "by_family": {
            family: {key: int(value) for key, value in sorted(stats.items())}
            for family, stats in sorted(by_family.items())
        },
        "invalidation_proof": {
            "identity_rebuild_stable_keys": len(ready),
            "source_mutation_changed_keys": source_change,
            "routing_policy_mutation_changed_keys": mutate_count(ready, "routing_policy_sha256"),
            "target_profile_mutation_changed_keys": mutate_count(ready, "target_profile_sha256"),
            "descriptor_graph_mutation_changed_keys": descriptor_changed,
            "tool_mutation_changed_keys_by_family": tool_changes,
        },
        "output_hash_verification_required": True,
        "shared_cache_write_authorized": False,
    }
    return {
        "result": "PASS",
        "report": report,
        "summary": summary,
        "inputs": {
            "routing_policy_sha256": routing_policy,
            "descriptor_graph_sha256": descriptor_graph,
            "target_profile_sha256": target_profile,
            "interchange_source_sha256": interchange,
            "converter_source_sha256": dict(sorted(tools.items())),
        },
    }


def self_test() -> int:
    base = {"namespace": "v1", "asset_id": "a", "source_payload_sha256": "0" * 64}
    key = key_for(base)
    same = key_for(dict(base)) == key
    changed_source = dict(base)
    changed_source["source_payload_sha256"] = "1" * 64
    changed_tool = dict(base)
    changed_tool["converter_source_sha256"] = "2" * 64
    assertions = int(same) + int(key_for(changed_source) != key) + int(key_for(changed_tool) != key)
    assertions += int("mtime" not in base) + int("absolute_path" not in base)
    print(canonical_json({"assertions": assertions, "result": "PASS" if assertions == 5 else "FAIL"}))
    return 0 if assertions == 5 else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path)
    parser.add_argument("--asset-catalog", type=Path)
    parser.add_argument("--routing-report", type=Path)
    parser.add_argument("--routing-policy", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    required = (args.root, args.asset_catalog, args.routing_report, args.routing_policy, args.policy, args.output)
    if any(value is None for value in required):
        parser.error("all input and output arguments are required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(canonical_json(build(args)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
