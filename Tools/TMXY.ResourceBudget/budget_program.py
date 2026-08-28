"""Program scenarios, open risks, and report assembly for P2-19."""

from __future__ import annotations

from decimal import Decimal
from pathlib import Path
from typing import Any

from budget_common import (
    BASIS_KINDS, PHASES, SCENARIOS, basis_ids, build_basis_catalog, decimal,
    json_number, load_inputs, pilot_case_index, require, routing_index,
    validate_basis_references,
)
from budget_model import human_budget, machine_budget, measured_facts, storage_budget


def week_range(minimum: Decimal, maximum: Decimal) -> dict[str, int | float]:
    require(Decimal(0) <= minimum <= maximum, "invalid week range")
    return {"maximum": json_number(maximum), "minimum": json_number(minimum)}


def program_forecast(policy: dict[str, Any]) -> dict[str, Any]:
    phases, sequential_min, sequential_max = [], Decimal(0), Decimal(0)
    for phase in PHASES:
        values = policy["program_phase_ranges_weeks"][phase]
        minimum, maximum = decimal(values["minimum"]), decimal(values["maximum"])
        require(minimum <= maximum, f"phase range inverted: {phase}")
        sequential_min, sequential_max = sequential_min + minimum, sequential_max + maximum
        phases.append({"basis_ids": ["BAS-PLAN-PROGRAM-PHASES"], "maximum_weeks": json_number(maximum), "minimum_weeks": json_number(minimum), "phase": phase})
    scenarios = []
    for scenario_id in SCENARIOS:
        values = policy["program_scenarios"][scenario_id]
        overlap = Decimal(int(values["phase_overlap_basis_points"])) / 10_000
        reserve_rate = Decimal(int(values["risk_reserve_basis_points"])) / 10_000
        base_min, base_max = sequential_min * overlap, sequential_max * overlap
        reserve_min, reserve_max = base_min * reserve_rate, base_max * reserve_rate
        scenarios.append({
            "base_weeks": week_range(base_min, base_max),
            "basis_ids": ["BAS-PLAN-PROGRAM-PHASES", "BAS-ASSUME-PROGRAM-SCENARIOS", "BAS-RISK-PROGRAM", "BAS-MISSING-G2-DELAY"],
            "core_fte": values["core_fte"], "id": scenario_id,
            "phase_overlap_basis_points": int(values["phase_overlap_basis_points"]),
            "risk_reserve_basis_points": int(values["risk_reserve_basis_points"]),
            "risk_reserve_weeks": week_range(reserve_min, reserve_max),
            "shared_fte": values["shared_fte"],
            "total_weeks": week_range(base_min + reserve_min, base_max + reserve_max),
        })
    return {"basis_ids": ["BAS-PLAN-PROGRAM-PHASES", "BAS-ASSUME-PROGRAM-SCENARIOS", "BAS-RISK-PROGRAM", "BAS-MISSING-G2-DELAY"], "delivery_commitment": False, "g2_blocking_delay_weeks": None, "g2_delay_status": "unbounded", "phase_ranges": phases, "scenarios": scenarios, "scope": "P3-P8"}


def team_plan(policy: dict[str, Any]) -> dict[str, Any]:
    workforce = policy["workforce_policy"]
    specialists = {"constrained": int(workforce["content_specialist_fte"]["minimum"]), "recommended": int(workforce["content_specialist_fte"]["recommended"]), "accelerated": int(workforce["content_specialist_fte"]["maximum"])}
    scenarios = []
    for scenario_id in SCENARIOS:
        program = policy["program_scenarios"][scenario_id]
        scenarios.append({"basis_ids": ["BAS-ASSUME-WORKFORCE", "BAS-ASSUME-PROGRAM-SCENARIOS"], "content_specialist_fte": specialists[scenario_id], "core_fte": program["core_fte"], "id": scenario_id, "productive_hours_per_week": int(workforce["productive_hours_per_fte_week"]), "shared_fte": program["shared_fte"]})
    return {"basis_ids": ["BAS-ASSUME-WORKFORCE", "BAS-ASSUME-PROGRAM-SCENARIOS"], "content_specialist_fte": workforce["content_specialist_fte"], "productive_hours_per_fte_week": int(workforce["productive_hours_per_fte_week"]), "scenarios": scenarios}


def missing(item_id: str, description: str, impact: str, required_for: str, next_step: str, blocking: bool = True) -> dict[str, Any]:
    return {"blocking": blocking, "description": description, "id": item_id, "impact": impact, "next_measurement": next_step, "required_for": required_for}


def missing_measurements() -> list[dict[str, Any]]:
    return [
        missing("MIS-001", "Measured human handling time is zero across all routes.", "Human effort remains a risk-adjusted planning coefficient.", "delivery staffing commitment", "Run role-tagged time studies for review, adaptation, recovery, and repair."),
        missing("MIS-002", "The pilot has one deterministic case per measured family.", "Repeat-run p80 does not measure population variance.", "high-confidence bulk throughput", "Run deterministic family and size-stratified pilots."),
        missing("MIS-003", "CPU time is not measured.", "Processor demand cannot be sized.", "machine fleet sizing", "Capture process CPU seconds for cold and warm runs."),
        missing("MIS-004", "Peak RSS is not measured.", "Safe concurrent worker count is unknown.", "parallel capacity", "Capture process and aggregate peak resident memory."),
        missing("MIS-005", "Peak temporary storage is not measured.", "Safe disk concurrency is unknown.", "parallel capacity", "Measure per-family temporary-space high-water marks."),
        missing("MIS-006", "I/O throughput and saturation are not measured.", "Parallel scaling may be storage-bound.", "machine fleet sizing", "Measure bytes read/written and fixed-worker scaling."),
        missing("MIS-007", "Cold/warm cache hit rates are not measured.", "Incremental rebuild duration is unknown.", "incremental schedule", "Replay unchanged and controlled-mutation verified-cache workloads."),
        missing("MIS-008", "Parallel scaling efficiency is not measured.", "Sequential seconds cannot become elapsed wall time.", "calendar schedule", "Benchmark 1, 2, 4, and 8 workers."),
        missing("MIS-009", "Audio, navigation, manual, UE, and build-cache ratios are assumptions.", "Storage retains model uncertainty.", "storage procurement", "Measure outputs and temporary bytes for missing routes."),
        missing("MIS-010", "Currency and labor, machine, storage, license, and vendor rates are absent.", "No monetary budget exists.", "price budget", "Supply approved currency and dated rate cards."),
        missing("MIS-011", "G2 blocker resolution duration is unbounded.", "P3-P8 scenarios exclude G2 delay.", "delivery date", "Resolve P2-20 evidence queues and approve G2."),
    ]


def risk(risk_id: str, severity: str, state: str, category: str, description: str, impact: str, control: str, ids: list[str]) -> dict[str, Any]:
    return {"basis_ids": ids, "category": category, "control": control, "description": description, "id": risk_id, "impact": impact, "severity": severity, "state": state}


def risk_register(storage: dict[str, Any]) -> list[dict[str, Any]]:
    storage_state = "scenario-covered" if storage["capacity_sufficient"] else "open"
    return [
        risk("RBR-001", "high", "open", "human", "No route has measured person-time.", "Staffing weeks may change materially.", "Keep coefficients and route reserves separate; run time studies.", ["BAS-PLAN-P2-15-HUMAN", "BAS-RISK-HUMAN-ROUTES", "BAS-MISSING-HUMAN-TIME"]),
        risk("RBR-002", "high", "open", "machine", "Pilot omits population variance, CPU, memory, temp, I/O, cache, and scaling.", "No elapsed duration or fleet size is proven.", "Keep byte-linear extrapolation explicit and the projection partially calibrated.", ["BAS-MEASURED-PILOT", "BAS-ASSUME-PILOT-EXTRAPOLATION", "BAS-RISK-MACHINE", "BAS-MISSING-MACHINE-CAPACITY"]),
        risk("RBR-003", "high", "open", "scope", "Eight hundred manual jobs remain blocked.", "Content is not fully conversion-ready.", "Preserve the queue and prohibit guessed repairs.", ["BAS-MEASURED-INVENTORY", "BAS-MISSING-HUMAN-TIME"]),
        risk("RBR-004", "medium", storage_state, "storage", "Pilot output ratios are byte-linearly extrapolated and other storage multipliers are assumptions.", "Actual peak space can exceed the model.", "Keep the extrapolation explicit, two recovery copies, separate reserve, and capacity gap.", ["BAS-MEASURED-HOST-STORAGE", "BAS-ASSUME-PILOT-EXTRAPOLATION", "BAS-ASSUME-STORAGE", "BAS-RISK-STORAGE"]),
        risk("RBR-005", "high", "open", "schedule", "G2 blocking delay is unbounded.", "Scenarios cannot become dates.", "Keep delay null and commitment false.", ["BAS-MISSING-G2-DELAY"]),
        risk("RBR-006", "medium", "scenario-covered", "schedule", "Team, overlap, and productivity are assumptions.", "Ranges vary by skills and dependencies.", "Publish three scenarios and separate reserves.", ["BAS-ASSUME-WORKFORCE", "BAS-ASSUME-PROGRAM-SCENARIOS", "BAS-RISK-PROGRAM"]),
        risk("RBR-007", "high", "open", "cost", "No currency or rate cards exist.", "A price total would be fabricated.", "Keep currency and amount null.", ["BAS-MISSING-PRICE-RATES"]),
        risk("RBR-008", "medium", "controlled-open", "scope", "Reference queues use different units and may share causes.", "Raw edge addition would double-count work.", "Measure resolution clusters before estimating labor.", ["BAS-MEASURED-INVENTORY", "BAS-MISSING-HUMAN-TIME"]),
    ]


EXPECTED_DECISIONS = {
    "all_numeric_outputs_are_non_price_planning_values": True,
    "g2_approved": False, "money_budget_estimated": False,
    "playable_experience_proven": False, "release_authority": False,
    "schedule_is_delivery_commitment": False,
}


def validate_authority(decisions: dict[str, Any]) -> None:
    require(decisions == EXPECTED_DECISIONS, "budget authority boundary differs")


def build_report(root: Path, policy_path: Path, pilot_path: Path) -> dict[str, Any]:
    policy, p215, p218, pilot, bindings = load_inputs(root, policy_path, pilot_path)
    require(policy["basis_categories"] == list(BASIS_KINDS), "policy basis categories differ")
    require(p215["summary"]["estimates"]["basis"] == "planning coefficient, not benchmark or schedule commitment", "P2-15 authority differs")
    for key in ("g2_approved", "playable_experience_proven", "release_authority"):
        require(p218["summary"]["decisions"][key] is False, f"P2-18 unexpectedly grants {key}")
    require(pilot["measurement_complete"] is True and pilot["task_completion_claimed"] is False, "pilot boundary differs")
    cases, routing = pilot_case_index(pilot), routing_index(pilot)
    catalog = build_basis_catalog(policy)
    human = human_budget(policy, p215)
    machine = machine_budget(policy, p215, pilot, cases, routing)
    storage = storage_budget(policy, p215, p218, pilot, cases, routing)
    validate_authority(EXPECTED_DECISIONS)
    report = {
        "schema_version": 1, "task_id": "P2-19",
        "result": "PASS_WITH_OPEN_MEASUREMENT_GAPS",
        "budget_status": "CONDITIONAL_PLANNING_BASELINE",
        "source_build": policy["source_build"], "input_bindings": bindings,
        "basis_catalog": catalog, "measured_facts": measured_facts(p218, cases),
        "human_budget": human, "machine_budget": machine, "storage_budget": storage,
        "program_forecast": program_forecast(policy), "team_plan": team_plan(policy),
        "risk_register": risk_register(storage), "missing_measurements": missing_measurements(),
        "decisions": dict(EXPECTED_DECISIONS),
        "disclosure": {"decoded_confidential_payloads": False, "exact_observed_extrema": False, "exact_primary_keys": False, "legacy_source_lines": False, "prices": False, "private_source_paths": False, "raw_table_rows": False, "schedule_commitments": False},
    }
    validate_basis_references(report, basis_ids(catalog))
    return report
