"""Shared deterministic primitives and input validation for P2-19."""

from __future__ import annotations

import hashlib
import json
from decimal import ROUND_CEILING, Decimal
from pathlib import Path
from typing import Any

BASIS_KINDS = (
    "measured_fact", "planning_coefficient", "assumption",
    "risk_reserve", "missing_measurement",
)
ROUTES = (
    "automatic-qualified-interchange", "automatic-standard-audio",
    "semi-automatic-navigation-adaptation", "manual-descriptor-recovery",
    "manual-repair-or-replace",
)
PILOT_FAMILIES = ("qtx", "sm", "skem", "anim", "ter")
PHASES = ("P3", "P4", "P5", "P6", "P7", "P8")
SCENARIOS = ("constrained", "recommended", "accelerated")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def compact_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON root must be an object: {path}")
    return value


def decimal(value: Any) -> Decimal:
    require(not isinstance(value, bool), "boolean is not a budget number")
    result = Decimal(str(value))
    require(result.is_finite(), "budget value must be finite")
    return result


def json_number(value: Decimal, places: str = "0.000001") -> int | float:
    rounded = value.quantize(Decimal(places))
    return int(rounded) if rounded == rounded.to_integral_value() else float(format(rounded.normalize(), "f"))


def ceil_integer(value: Decimal) -> int:
    require(value >= 0, "cannot round a negative budget value")
    return int(value.to_integral_value(rounding=ROUND_CEILING))


def scaled_integer(base: int, basis_points: int) -> int:
    require(base >= 0 and basis_points >= 0, "negative base or reserve")
    return ceil_integer(Decimal(base) * Decimal(basis_points) / Decimal(10_000))


def reserve_decimal(base: Decimal, basis_points: int) -> Decimal:
    require(base >= 0 and basis_points >= 0, "negative base or reserve")
    return base * Decimal(basis_points) / Decimal(10_000)


def metric(metric_id: str, value: int | float, unit: str, ids: list[str]) -> dict[str, Any]:
    return {"basis_ids": ids, "id": metric_id, "unit": unit, "value": value}


def entry(basis_id: str, description: str, unit: str, value: Any, source: str) -> dict[str, Any]:
    return {"description": description, "id": basis_id, "source": source, "unit": unit, "value": value}


def build_basis_catalog(policy: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    return {
        "measured_fact": [
            entry("BAS-MEASURED-INVENTORY", "Hash-bound full-content populations.", "aggregate", "P2-15 and P2-18", "Data/Inventory/p2-15-conversion-routing.json; Data/Inventory/p2-18-content-health.json"),
            entry("BAS-MEASURED-PILOT", "Exporter-process pilot for five interchange families.", "measurement", "median, p80, output ratio", "Data/Performance/p2-19-conversion-pilot.json"),
            entry("BAS-MEASURED-HOST-STORAGE", "Pilot-time host, volume, repository, and generated-directory snapshot.", "bytes", "pilot snapshot", "Data/Performance/p2-19-conversion-pilot.json#environment"),
        ],
        "planning_coefficient": [
            entry("BAS-PLAN-P2-15-HUMAN", "P2-15 route effort; not measured labor time.", "human_hours", "route totals", "Data/Inventory/p2-15-conversion-routing.json#summary.routes"),
            entry("BAS-PLAN-MACHINE-FALLBACK", "P2-15 sequential coefficients for unpiloted routes.", "machine_seconds", "route totals", "Data/Inventory/p2-15-conversion-routing.json#summary.routes"),
            entry("BAS-PLAN-PROGRAM-PHASES", "Original P3-P8 ranges; not commitments.", "weeks", compact_json(policy["program_phase_ranges_weeks"]), "Contracts/data-schema/resource-budget-policy-v1.json#program_phase_ranges_weeks"),
        ],
        "assumption": [
            entry("BAS-ASSUME-PILOT-EXTRAPOLATION", "Selected-case elapsed time and output ratios scale linearly with alias-excluded ready-job bytes; population variance is not measured.", "model", "bytes-proportional", "P2-19 resource-budget model"),
            entry("BAS-ASSUME-WORKFORCE", "Content-specialist staffing and productive FTE hours.", "FTE and hours/week", compact_json(policy["workforce_policy"]), "Contracts/data-schema/resource-budget-policy-v1.json#workforce_policy"),
            entry("BAS-ASSUME-STORAGE", "Unmeasured output, UE, cache, and recovery multipliers.", "basis_points and copies", compact_json(policy["storage_projection"]), "Contracts/data-schema/resource-budget-policy-v1.json#storage_projection"),
            entry("BAS-ASSUME-PROGRAM-SCENARIOS", "Team, overlap, and calendar scenario coefficients.", "FTE and basis_points", compact_json(policy["program_scenarios"]), "Contracts/data-schema/resource-budget-policy-v1.json#program_scenarios"),
        ],
        "risk_reserve": [
            entry("BAS-RISK-HUMAN-ROUTES", "Route-specific reserve separated from base effort.", "basis_points", compact_json(policy["route_risk_reserve_basis_points"]), "Contracts/data-schema/resource-budget-policy-v1.json#route_risk_reserve_basis_points"),
            entry("BAS-RISK-MACHINE", "Reserve on mixed pilot/planning machine base.", "basis_points", policy["machine_projection"]["risk_reserve_basis_points"], "Contracts/data-schema/resource-budget-policy-v1.json#machine_projection"),
            entry("BAS-RISK-STORAGE", "Reserve after recovery-copy storage.", "basis_points", policy["storage_projection"]["total_risk_reserve_basis_points"], "Contracts/data-schema/resource-budget-policy-v1.json#storage_projection"),
            entry("BAS-RISK-PROGRAM", "Calendar reserve after phase overlap.", "basis_points", compact_json({k: v["risk_reserve_basis_points"] for k, v in policy["program_scenarios"].items()}), "Contracts/data-schema/resource-budget-policy-v1.json#program_scenarios"),
        ],
        "missing_measurement": [
            entry("BAS-MISSING-HUMAN-TIME", "No measured conversion or review person-time.", "human_hours", 0, "P2-19 evidence audit"),
            entry("BAS-MISSING-MACHINE-CAPACITY", "CPU time, peak RSS/temp, I/O, cache hits, and parallel scaling are absent.", "measurement", None, "P2-19 pilot boundary"),
            entry("BAS-MISSING-PRICE-RATES", "Currency and rate cards are absent.", "currency", None, "Contracts/data-schema/resource-budget-policy-v1.json#money_budget"),
            entry("BAS-MISSING-G2-DELAY", "G2 blocker resolution time is unbounded.", "weeks", None, "Data/Inventory/p2-18-content-health.json#summary.decisions"),
        ],
    }


def basis_ids(catalog: dict[str, list[dict[str, Any]]]) -> dict[str, str]:
    require(tuple(catalog.keys()) == BASIS_KINDS, "basis catalog must contain five ordered categories")
    result: dict[str, str] = {}
    for kind, entries in catalog.items():
        require(entries, f"empty basis category: {kind}")
        for item in entries:
            item_id = str(item["id"])
            require(item_id not in result, f"duplicate basis id: {item_id}")
            result[item_id] = kind
    return result


def validate_basis_references(value: Any, known: dict[str, str]) -> None:
    if isinstance(value, dict):
        if "basis_ids" in value:
            ids = value["basis_ids"]
            require(isinstance(ids, list) and ids and len(ids) == len(set(ids)), "invalid basis_ids")
            require(all(item in known for item in ids), "unknown basis id")
        for child in value.values():
            validate_basis_references(child, known)
    elif isinstance(value, list):
        for child in value:
            validate_basis_references(child, known)


def input_binding(value: dict[str, Any], contract: dict[str, Any], digest: str) -> dict[str, Any]:
    task = str(contract["task_id"])
    require(str(value.get("task_id")) == task, f"input task differs: {task}")
    require(value.get("result") == "PASS", f"input not PASS: {task}")
    require(value.get("task_status") == "COMPLETE", f"input not COMPLETE: {task}")
    require(bool(value.get("completion_criteria_satisfied")), f"input incomplete: {task}")
    return {"completion_criteria_satisfied": True, "path": str(contract["path"]), "result": "PASS", "sha256": digest, "task_id": task, "task_status": "COMPLETE"}


def load_inputs(root: Path, policy_path: Path, pilot_path: Path) -> tuple[dict[str, Any], ...]:
    policy = load_json(policy_path)
    require(policy["task_id"] == "P2-19", "wrong policy task")
    contracts = policy["input_contracts"]
    p215_path = root / contracts["conversion_routing"]["path"]
    p218_path = root / contracts["content_health"]["path"]
    require(pilot_path.resolve() == (root / contracts["conversion_pilot"]["path"]).resolve(), "pilot path differs")
    p215, p218, pilot = load_json(p215_path), load_json(p218_path), load_json(pilot_path)
    digests = {"conversion_routing": sha256_file(p215_path), "content_health": sha256_file(p218_path), "conversion_pilot": sha256_file(pilot_path)}
    bindings = {key: input_binding(value, contracts[key], digests[key]) for key, value in (("conversion_routing", p215), ("content_health", p218), ("conversion_pilot", pilot))}
    chain = [item for item in p218["input"]["inputs"] if item.get("task_id") == "P2-15"]
    require(len(chain) == 1 and chain[0]["sha256"] == digests["conversion_routing"], "P2-18/P2-15 SHA chain differs")
    require(pilot["input_bindings"]["p2_15"]["evidence_sha256"] == digests["conversion_routing"], "pilot/P2-15 SHA chain differs")
    require(p215["input"]["source_build"] == policy["source_build"] == p218["input"]["source_build"], "source build differs")
    lines = [f"{bindings[k]['task_id']}|{bindings[k]['path']}|{bindings[k]['sha256']}" for k in ("conversion_routing", "content_health", "conversion_pilot")]
    bindings["aggregate_sha256"] = sha256_bytes(("\n".join(lines) + "\n").encode())
    return policy, p215, p218, pilot, bindings


def pilot_case_index(pilot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    cases = {str(item["family"]): item for item in pilot["cases"]}
    require(set(cases) == set(PILOT_FAMILIES), "pilot families differ")
    for family, case in cases.items():
        require(case["output_hash_stable"] and case["output_size_stable"], f"unstable pilot: {family}")
        require(int(case["input_bytes"]) > 0 and len(case["elapsed_ms"]) >= 5, f"invalid pilot: {family}")
    return cases


def routing_index(pilot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result = {str(item["family"]): item for item in pilot["routing_by_family"]}
    require(set(result) == {"qtx", "sm", "skem", "anim", "ter", "wav", "mp3", "zif"}, "routing families differ")
    totals, inv = pilot["routing_totals"], pilot["extrapolation_invariants"]
    require(int(totals["files"]) == int(totals["jobs"]) + int(totals["aliases"]), "alias job accounting differs")
    require(int(totals["ready_job_bytes"]) + int(totals["manual_job_bytes"]) <= int(totals["bytes"]), "job bytes exceed all bytes")
    require(inv["aliases_excluded_from_job_counts"] and inv["aliases_excluded_from_ready_job_bytes"], "aliases enter projections")
    return result
