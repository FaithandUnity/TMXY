"""Human-readable rendering and negative self-tests for P2-19."""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path
from typing import Any, Callable

from budget_common import (
    BASIS_KINDS, basis_ids, input_binding, json_number, reserve_decimal,
    routing_index, scaled_integer, sha256_bytes,
)
from budget_model import project_seconds, storage_budget
from budget_program import validate_authority, week_range


def number(value: Any) -> str:
    if isinstance(value, int):
        return f"{value:,}"
    if isinstance(value, float):
        return f"{value:,.3f}".rstrip("0").rstrip(".")
    return str(value)


def render_markdown(report: dict[str, Any]) -> str:
    human, machine = report["human_budget"], report["machine_budget"]
    storage, program = report["storage_budget"], report["program_forecast"]
    lines = [
        "# P2-19 Resource Budget", "",
        f"Result: `{report['result']}`; status: `{report['budget_status']}`.", "",
        "This is a conditional, non-price planning baseline. It is not a delivery commitment, playable-build claim, G2 approval, or release authority.", "",
        "## Input bindings", "", "| Input | Task | SHA-256 |", "|---|---|---|",
    ]
    for name in ("conversion_routing", "content_health", "conversion_pilot"):
        item = report["input_bindings"][name]
        lines.append(f"| {name} | {item['task_id']} | `{item['sha256']}` |")
    lines += ["", "## Human budget", "", "Measured human hours: **0**. Route values remain P2-15 planning coefficients plus separate reserves.", "", "| Route | Base h | Reserve bp | Reserve h | Risk-adjusted h |", "|---|---:|---:|---:|---:|"]
    for item in human["by_route"]:
        lines.append(f"| {item['route']} | {number(item['base_hours'])} | {item['risk_reserve_basis_points']:,} | {number(item['risk_reserve_hours'])} | {number(item['total_hours'])} |")
    lines += ["", f"Total: {number(human['base_planning_hours'])} base h + {number(human['risk_reserve_hours'])} reserve h = {number(human['total_planning_hours'])} planning h.", "", "| Content specialists | Productive h/FTE-week | Base weeks | Reserve weeks | Risk-adjusted weeks |", "|---:|---:|---:|---:|---:|"]
    for item in human["workforce_scenarios"]:
        lines.append(f"| {item['content_specialist_fte']} | {item['productive_hours_per_fte_week']} | {number(item['base_weeks'])} | {number(item['risk_reserve_weeks'])} | {number(item['risk_adjusted_weeks'])} |")
    lines += ["", "Money budget: **not estimated**; currency and all required rate cards are missing.", "", "## Machine budget", "", f"Projection status: `{machine['projection_status']}`. Sequential seconds do not establish wall time or fleet size.", "", "| Route | Pilot runs | Base s | Reserve s | Total s |", "|---|---:|---:|---:|---:|"]
    for item in machine["by_route"]:
        lines.append(f"| {item['route']} | {item['pilot_sample_count']} | {number(item['base_seconds'])} | {number(item['risk_reserve_seconds'])} | {number(item['total_seconds'])} |")
    lines += ["", f"Total: {number(machine['base_sequential_seconds'])} base s + {number(machine['risk_reserve_seconds'])} reserve s = {number(machine['total_sequential_seconds'])} sequential s.", "", "Five interchange families use a **planning assumption** that selected-case p80 scales linearly with alias-excluded ready-job bytes. Audio/navigation retain planning coefficients. CPU time, peak RSS/temp, I/O, cache hits, and parallel scaling are missing.", "", "## Storage budget", "", "Pilot output ratios are also **planning-assumption byte-linear extrapolations**. Review-only duplicate bytes are not deducted.", "", "| Item | Bytes |", "|---|---:|", f"| Existing workspace | {storage['existing_workspace_bytes']:,} |", f"| Source retained | {storage['source_retained_bytes']:,} |", f"| Intermediate | {storage['intermediate_estimated_bytes']:,} |", f"| UE content | {storage['ue_content_estimated_bytes']:,} |", f"| Build cache | {storage['build_cache_estimated_bytes']:,} |", f"| Two recovery copies | {storage['recovery_bytes']:,} |", f"| Storage reserve | {storage['risk_reserve_bytes']:,} |", f"| Incremental required | {storage['incremental_required_bytes']:,} |", f"| Current volume free | {storage['disk_free_bytes']:,} |", f"| Capacity gap | {storage['capacity_gap_bytes']:,} |", "", "## Conditional P3-P8 scenarios", "", "G2 blocking delay is **unbounded** and `null`; every range excludes it.", "", "| Scenario | Core/shared FTE | Base weeks | Reserve weeks | Conditional total |", "|---|---:|---:|---:|---:|"]
    for item in program["scenarios"]:
        base, reserve, total = item["base_weeks"], item["risk_reserve_weeks"], item["total_weeks"]
        lines.append(f"| {item['id']} | {item['core_fte']}/{item['shared_fte']} | {number(base['minimum'])}–{number(base['maximum'])} | {number(reserve['minimum'])}–{number(reserve['maximum'])} | {number(total['minimum'])}–{number(total['maximum'])} |")
    lines += ["", "Team composition, productive hours, overlap, and reserve are assumptions.", "", "## Open measurements", ""]
    lines += [f"- `{item['id']}`: {item['description']} Next: {item['next_measurement']}" for item in report["missing_measurements"]]
    lines += ["", "## Decision boundary", "", "Budget accounting supports a conditional baseline only. Price, G2, playability, schedule commitment, and release authority remain unavailable.", ""]
    return "\n".join(lines)


def describe(path: Path) -> dict[str, Any]:
    payload = path.read_bytes()
    return {"bytes": len(payload), "lines": len(payload.splitlines()), "sha256": sha256_bytes(payload)}


def fails(action: Callable[[], Any]) -> bool:
    try:
        action()
    except (KeyError, TypeError, ValueError):
        return True
    return False


def self_test() -> dict[str, Any]:
    count = 0
    count += int(scaled_integer(3, 2500) == 1)
    count += int(reserve_decimal(Decimal("392.25"), 2500) == Decimal("98.0625"))
    count += int(project_seconds(250, 1000, 100) == Decimal("2.5"))
    count += int(week_range(Decimal("1.25"), Decimal("2.5")) == {"minimum": 1.25, "maximum": 2.5})
    count += int(fails(lambda: basis_ids({kind: [] for kind in BASIS_KINDS})))
    count += int(fails(lambda: reserve_decimal(Decimal(1), -1)))
    bad_alias = {"routing_by_family": [], "routing_totals": {"files": 2, "jobs": 2, "aliases": 1, "ready_job_bytes": 2, "manual_job_bytes": 0, "bytes": 2}, "extrapolation_invariants": {"aliases_excluded_from_job_counts": False, "aliases_excluded_from_ready_job_bytes": False}}
    count += int(fails(lambda: routing_index(bad_alias)))
    count += int(fails(lambda: storage_budget({}, {}, {}, {}, {}, {}, duplicate_savings=1)))
    count += int(fails(lambda: validate_authority({"g2_approved": True})))
    count += int(fails(lambda: input_binding({"task_id": "x", "result": "PASS", "task_status": "COMPLETE", "completion_criteria_satisfied": True}, {"task_id": "y", "path": "p"}, "0" * 64)))
    count += int(json_number(Decimal("1068.695") + Decimal(336)) == 1404.695)
    count += int(tuple(BASIS_KINDS)[-1] == "missing_measurement")
    return {"assertions": count, "result": "PASS" if count == 12 else "FAIL"}
