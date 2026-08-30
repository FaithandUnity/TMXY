#!/usr/bin/env python3
"""Build deterministic P2-15 per-asset conversion routes and planning estimates."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def iter_json_lines(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        for line in stream:
            if line.strip():
                yield json.loads(line)


class ReportWriter:
    def __init__(self, path: Path) -> None:
        self.stream = path.open("wb")
        self.digest = hashlib.sha256()
        self.bytes = 0
        self.lines = 0

    def emit(self, value: dict[str, Any]) -> None:
        data = (canonical_json(value) + "\n").encode("utf-8")
        self.stream.write(data)
        self.digest.update(data)
        self.bytes += len(data)
        self.lines += 1

    def close(self) -> dict[str, Any]:
        self.stream.close()
        return {"bytes": self.bytes, "lines": self.lines, "sha256": self.digest.hexdigest()}


def route_index(policy: dict[str, Any]) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for route in policy["routes"]:
        for family in route["families"]:
            for structure in route["structures"]:
                key = (str(family), str(structure))
                if key in result:
                    raise ValueError(f"duplicate route policy: {key}")
                result[key] = route
    return result


def load_health(path: Path) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    assets: list[dict[str, Any]] = []
    exact_groups: dict[str, list[str]] = {}
    for entry in iter_json_lines(path):
        record = str(entry["record"])
        if record == "asset_health":
            assets.append(entry)
        elif record == "exact_duplicate_group":
            exact_groups[str(entry["id"])] = [str(item) for item in entry["members"]]
    assets.sort(key=lambda item: str(item["path"]))
    return assets, exact_groups


def assign_routes(
    assets: list[dict[str, Any]], policy: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    routes = route_index(policy)
    priorities = {str(key): str(value) for key, value in policy["priority_mapping"].items()}
    priority_rank = {value: index for index, value in enumerate(priorities.values())}
    assigned: dict[str, dict[str, Any]] = {}
    for asset in assets:
        key = (str(asset["family"]), str(asset["structure"]))
        if key not in routes:
            raise ValueError(f"asset has no conversion route: {key}")
        reference_state = str(asset["reference_state"])
        if reference_state not in priorities:
            raise ValueError(f"asset has no priority mapping: {reference_state}")
        route = routes[key]
        assigned[str(asset["id"])] = {
            **asset,
            "route": str(route["id"]),
            "tier": str(route["tier"]),
            "priority": priorities[reference_state],
            "priority_rank": priority_rank[priorities[reference_state]],
            "route_policy": route,
        }
    return assigned


def assign_duplicate_handling(
    assigned: dict[str, dict[str, Any]],
    exact_groups: dict[str, list[str]],
    policy: dict[str, Any],
) -> None:
    eligible = set(str(item) for item in policy["exact_duplicate_reuse"]["eligible_families"])
    for asset in assigned.values():
        asset["duplicate_handling"] = "unique"
        asset["conversion_job_required"] = True
        asset["reuse_representative"] = ""
    for group_id, members in exact_groups.items():
        values = [assigned[item] for item in members]
        reusable = all(
            item["family"] in eligible and item["structure"] == "PASS" for item in values
        )
        if not reusable:
            for item in values:
                item["duplicate_handling"] = "exact-duplicate-review-only"
            continue
        representative = min(values, key=lambda item: (item["priority_rank"], item["id"]))
        representative["duplicate_handling"] = "safe-reuse-representative"
        representative["reuse_representative"] = representative["id"]
        for item in values:
            if item is representative:
                continue
            item["duplicate_handling"] = "safe-reuse-alias"
            item["conversion_job_required"] = False
            item["reuse_representative"] = representative["id"]
        for item in values:
            item["exact_duplicate_group"] = group_id


def decimal_number(value: Decimal) -> float:
    return float(value.quantize(Decimal("0.001")))


def summarize_dimension(stats: collections.Counter[str]) -> dict[str, Any]:
    return {
        "alias_reuse": int(stats["alias_reuse"]),
        "bytes": int(stats["bytes"]),
        "conversion_jobs": int(stats["conversion_jobs"]),
        "files": int(stats["files"]),
        "item_human_hours": stats["item_human_millihours"] / 1000,
        "machine_seconds": int(stats["machine_seconds"]),
    }


def build(args: argparse.Namespace) -> dict[str, Any]:
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    assets, exact_groups = load_health(args.health_report)
    assigned = assign_routes(assets, policy)
    assign_duplicate_handling(assigned, exact_groups, policy)
    alias_hours = Decimal(str(policy["alias_validation_hours"]))
    route_stats: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    priority_stats: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    tier_stats: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)
    duplicate_stats: collections.Counter[str] = collections.Counter()
    writer = ReportWriter(args.output)
    try:
        for item in sorted(assigned.values(), key=lambda value: str(value["path"])):
            route = item["route_policy"]
            job = bool(item["conversion_job_required"])
            hours = Decimal(str(route["human_hours_per_job"])) if job else alias_hours
            machine_seconds = int(route["machine_seconds_per_job"]) if job else 0
            writer.emit(
                {
                    "bytes": int(item["bytes"]),
                    "conversion_job_required": job,
                    "delete_eligible": False,
                    "duplicate_handling": item["duplicate_handling"],
                    "estimated_human_hours": decimal_number(hours),
                    "estimated_machine_seconds": machine_seconds,
                    "family": str(item["family"]),
                    "id": str(item["id"]),
                    "path": str(item["path"]),
                    "priority": item["priority"],
                    "record": "conversion_route",
                    "reference_state": str(item["reference_state"]),
                    "reuse_representative": item["reuse_representative"],
                    "route": item["route"],
                    "structure": str(item["structure"]),
                    "tier": item["tier"],
                }
            )
            for stats in (route_stats[item["route"]], priority_stats[item["priority"]], tier_stats[item["tier"]]):
                stats["files"] += 1
                stats["bytes"] += int(item["bytes"])
                stats["conversion_jobs"] += int(job)
                stats["alias_reuse"] += int(not job)
                stats["item_human_millihours"] += int(hours * 1000)
                stats["machine_seconds"] += machine_seconds
            duplicate_stats[item["duplicate_handling"]] += 1
        report = writer.close()
    except Exception:
        writer.stream.close()
        raise

    route_policy = {str(item["id"]): item for item in policy["routes"]}
    total_fixed = Decimal("0")
    route_summary: dict[str, dict[str, Any]] = {}
    for route_id, stats in sorted(route_stats.items()):
        fixed = Decimal(str(route_policy[route_id]["fixed_engineering_hours"]))
        total_fixed += fixed
        route_summary[route_id] = {
            **{key: int(value) for key, value in sorted(stats.items()) if key != "item_human_millihours"},
            "fixed_engineering_hours": decimal_number(fixed),
            "item_human_hours": stats["item_human_millihours"] / 1000,
            "planning_human_hours": decimal_number(fixed + Decimal(stats["item_human_millihours"]) / 1000),
        }
    item_millihours = sum(stats["item_human_millihours"] for stats in route_stats.values())
    return {
        "result": "PASS",
        "report": report,
        "assets": {
            "files": len(assets),
            "bytes": sum(int(item["bytes"]) for item in assets),
            "conversion_jobs": sum(int(item["conversion_job_required"]) for item in assigned.values()),
            "alias_reuse": sum(int(not item["conversion_job_required"]) for item in assigned.values()),
        },
        "routes": route_summary,
        "priorities": {
            key: summarize_dimension(value) for key, value in sorted(priority_stats.items())
        },
        "tiers": {key: summarize_dimension(value) for key, value in sorted(tier_stats.items())},
        "duplicate_handling": dict(sorted(duplicate_stats.items())),
        "estimates": {
            "basis": str(policy["estimate_basis"]),
            "fixed_engineering_hours": decimal_number(total_fixed),
            "item_human_hours": item_millihours / 1000,
            "planning_human_hours": decimal_number(total_fixed + Decimal(item_millihours) / 1000),
            "machine_seconds": sum(stats["machine_seconds"] for stats in route_stats.values()),
        },
        "unclassified_assets": 0,
        "descriptor_bound_alias_reuse": 0,
        "deletion_recommendations": 0,
    }


def self_test() -> int:
    policy = {
        "routes": [{"id": "r", "tier": "automatic", "families": ["sm"], "structures": ["PASS"]}],
        "priority_mapping": {"root_reachable": "P0"},
        "exact_duplicate_reuse": {"eligible_families": ["sm"]},
    }
    assets = [
        {"id": "b", "family": "sm", "structure": "PASS", "reference_state": "root_reachable"},
        {"id": "a", "family": "sm", "structure": "PASS", "reference_state": "root_reachable"},
    ]
    assigned = assign_routes(assets, policy)
    assign_duplicate_handling(assigned, {"g": ["a", "b"]}, policy)
    assertions = 0
    assertions += int(route_index(policy)[("sm", "PASS")]["id"] == "r")
    assertions += int(assigned["a"]["duplicate_handling"] == "safe-reuse-representative")
    assertions += int(assigned["b"]["duplicate_handling"] == "safe-reuse-alias")
    assertions += int(not assigned["b"]["conversion_job_required"])
    assertions += int(decimal_number(Decimal("1.2345")) == 1.234)
    expected = 5
    print(canonical_json({"assertions": assertions, "result": "PASS" if assertions == expected else "FAIL"}))
    return 0 if assertions == expected else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--health-report", type=Path)
    parser.add_argument("--policy", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if any(value is None for value in (args.health_report, args.policy, args.output)):
        parser.error("all input and output arguments are required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(canonical_json(build(args)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
