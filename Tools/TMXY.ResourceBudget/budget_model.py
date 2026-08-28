"""Human, machine, and storage projections for P2-19."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

from budget_common import (
    PILOT_FAMILIES, ROUTES, decimal, json_number, metric, require,
    reserve_decimal, scaled_integer,
)


def output_ratio_bp(case: dict[str, Any]) -> int:
    from budget_common import ceil_integer
    return ceil_integer(Decimal(int(case["output_bytes"])) * 10_000 / Decimal(int(case["input_bytes"])))


def pilot_measurements(cases: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    return [{
        "basis_ids": ["BAS-MEASURED-PILOT"],
        "family": family,
        "median_seconds": json_number(decimal(cases[family]["median_ms"]) / 1000),
        "output_ratio_basis_points": output_ratio_bp(cases[family]),
        "p80_seconds": json_number(decimal(cases[family]["p80_ms"]) / 1000),
        "sample_count": len(cases[family]["elapsed_ms"]),
    } for family in PILOT_FAMILIES]


def measured_facts(p218: dict[str, Any], cases: dict[str, dict[str, Any]]) -> dict[str, Any]:
    capacity = p218["summary"]["capacity"]
    conversion = p218["summary"]["conversion"]
    unknown = p218["summary"]["unknown_or_opaque"]
    refs = p218["summary"]["references"]
    measured = ["BAS-MEASURED-INVENTORY"]
    return {
        "assets": [
            metric("assets", int(capacity["assets"]), "files", measured),
            metric("asset_bytes", int(capacity["asset_bytes"]), "bytes", measured),
            metric("normalized_table_bytes", int(capacity["normalized_table_bytes"]), "bytes", measured),
            metric("package_graph_bytes", int(capacity["package_graph_bytes"]), "bytes", measured),
            metric("reference_closure_bytes", int(capacity["reference_closure_bytes"]), "bytes", measured),
        ],
        "conversion": [
            metric("conversion_jobs", int(capacity["conversion_jobs"]), "jobs", measured),
            metric("ready_assets", int(conversion["assets_with_ready_key"]), "assets", measured),
            metric("ready_unique_jobs", int(conversion["distinct_ready_keys"]), "jobs", measured),
            metric("alias_assignments", int(conversion["alias_assignments"]), "aliases", measured),
            metric("blocked_manual_jobs", int(conversion["blocked_manual_jobs"]), "jobs", measured),
            metric("measured_human_hours", 0, "human_hours", ["BAS-MISSING-HUMAN-TIME"]),
        ],
        "content_risks": [
            metric("asset_structure_unresolved", int(unknown["asset_structure_unresolved"]), "assets", measured),
            metric("asset_corrupt", int(p218["summary"]["damage"]["asset_corrupt"]), "assets", measured),
            metric("package_reference_unresolved", int(refs["package_unresolved"]), "package_edges", measured),
            metric("package_reference_ambiguous", int(refs["package_ambiguous"]), "package_edges", measured),
            metric("table_object_reference_unresolved", int(refs["table_object_unresolved"]), "references", measured),
            metric("table_object_reference_ambiguous", int(refs["table_object_ambiguous"]), "references", measured),
            metric("package_object_payloads_opaque_not_parse_failures", int(unknown["package_object_payloads_opaque"]), "payloads", measured),
            metric("core_foreign_key_dangling", int(refs["core_foreign_key_dangling"]), "edges", measured),
        ],
        "pilot": pilot_measurements(cases),
    }


def human_budget(policy: dict[str, Any], p215: dict[str, Any]) -> dict[str, Any]:
    reserves = policy["route_risk_reserve_basis_points"]
    require(set(reserves) == set(ROUTES), "human reserve routes differ")
    rows, base_total, reserve_total = [], Decimal(0), Decimal(0)
    for route in ROUTES:
        base = decimal(p215["summary"]["routes"][route]["planning_human_hours"])
        reserve = reserve_decimal(base, int(reserves[route]))
        rows.append({"base_hours": json_number(base), "basis_ids": ["BAS-PLAN-P2-15-HUMAN", "BAS-RISK-HUMAN-ROUTES", "BAS-MISSING-HUMAN-TIME"], "risk_reserve_basis_points": int(reserves[route]), "risk_reserve_hours": json_number(reserve), "route": route, "total_hours": json_number(base + reserve)})
        base_total, reserve_total = base_total + base, reserve_total + reserve
    require(base_total == decimal(p215["summary"]["estimates"]["planning_human_hours"]), "human route total differs")
    productive = int(policy["workforce_policy"]["productive_hours_per_fte_week"])
    workforce = []
    for fte in sorted(int(v) for v in policy["workforce_policy"]["content_specialist_fte"].values()):
        divisor = Decimal(fte * productive)
        workforce.append({"base_weeks": json_number(base_total / divisor), "basis_ids": ["BAS-PLAN-P2-15-HUMAN", "BAS-RISK-HUMAN-ROUTES", "BAS-ASSUME-WORKFORCE", "BAS-MISSING-HUMAN-TIME"], "content_specialist_fte": fte, "productive_hours_per_fte_week": productive, "risk_adjusted_weeks": json_number((base_total + reserve_total) / divisor), "risk_reserve_weeks": json_number(reserve_total / divisor)})
    return {"base_planning_hours": json_number(base_total), "basis_ids": ["BAS-PLAN-P2-15-HUMAN", "BAS-RISK-HUMAN-ROUTES", "BAS-ASSUME-WORKFORCE", "BAS-MISSING-HUMAN-TIME", "BAS-MISSING-PRICE-RATES"], "by_route": rows, "money_budget": policy["money_budget"], "risk_reserve_hours": json_number(reserve_total), "total_planning_hours": json_number(base_total + reserve_total), "unit": "human_hours", "workforce_scenarios": workforce}


def project_seconds(ms: Any, population_bytes: int, sample_bytes: int) -> Decimal:
    require(population_bytes >= 0 and sample_bytes > 0, "invalid throughput operands")
    return decimal(ms) * Decimal(population_bytes) / Decimal(sample_bytes) / 1000


def machine_budget(policy: dict[str, Any], p215: dict[str, Any], pilot: dict[str, Any], cases: dict[str, dict[str, Any]], routing: dict[str, dict[str, Any]]) -> dict[str, Any]:
    median, p80, samples = Decimal(0), Decimal(0), 0
    for family in PILOT_FAMILIES:
        population = int(routing[family]["ready_job_bytes"])
        require(population > 0, f"missing ready job bytes: {family}")
        median += project_seconds(cases[family]["median_ms"], population, int(cases[family]["input_bytes"]))
        p80 += project_seconds(cases[family]["p80_ms"], population, int(cases[family]["input_bytes"]))
        samples += len(cases[family]["elapsed_ms"])
    require(p80 >= median, "p80 below median")
    reserve_bp = int(policy["machine_projection"]["risk_reserve_basis_points"])
    rows, base_total, reserve_total = [], Decimal(0), Decimal(0)
    for route in ROUTES:
        if route == ROUTES[0]:
            base, count = p80, samples
            ids = ["BAS-MEASURED-PILOT", "BAS-MEASURED-INVENTORY", "BAS-ASSUME-PILOT-EXTRAPOLATION", "BAS-RISK-MACHINE", "BAS-MISSING-MACHINE-CAPACITY"]
        else:
            base, count = decimal(p215["summary"]["routes"][route]["machine_seconds"]), 0
            ids = ["BAS-PLAN-MACHINE-FALLBACK", "BAS-RISK-MACHINE", "BAS-MISSING-MACHINE-CAPACITY"]
        reserve = reserve_decimal(base, reserve_bp)
        rows.append({"base_seconds": json_number(base), "basis_ids": ids, "pilot_sample_count": count, "risk_reserve_seconds": json_number(reserve), "route": route, "total_seconds": json_number(base + reserve)})
        base_total, reserve_total = base_total + base, reserve_total + reserve
    host, container = pilot["environment"]["host"], pilot["environment"]["container"]
    requirements = [
        {"basis_ids": ["BAS-MEASURED-PILOT", "BAS-MISSING-MACHINE-CAPACITY"], "id": "pilot-reference-host", "profile": f"{host['logical_processors']} logical processors; {host['physical_memory_bytes']} memory bytes", "purpose": "Reproduce single-process pilot; not a fleet claim.", "quantity": 1},
        {"basis_ids": ["BAS-MEASURED-PILOT", "BAS-MISSING-MACHINE-CAPACITY"], "id": "locked-builder-container", "profile": f"{container['visible_logical_processors']} visible processors; {container['visible_memory_bytes']} visible memory bytes", "purpose": "Preserve measured toolchain visibility.", "quantity": 1},
    ]
    return {"base_sequential_seconds": json_number(base_total), "basis_ids": ["BAS-MEASURED-PILOT", "BAS-PLAN-MACHINE-FALLBACK", "BAS-ASSUME-PILOT-EXTRAPOLATION", "BAS-RISK-MACHINE", "BAS-MISSING-MACHINE-CAPACITY"], "by_route": rows, "projection_status": "PARTIALLY_PILOT_CALIBRATED", "requirements": requirements, "risk_reserve_basis_points": reserve_bp, "risk_reserve_seconds": json_number(reserve_total), "total_sequential_seconds": json_number(base_total + reserve_total), "unit": "machine_seconds"}


def component(item_id: str, base: int, bp: int, ids: list[str]) -> dict[str, Any]:
    return {"base_bytes": base, "basis_ids": ids, "expansion_basis_points": bp, "id": item_id, "projected_bytes": scaled_integer(base, bp)}


def storage_budget(policy: dict[str, Any], p215: dict[str, Any], p218: dict[str, Any], pilot: dict[str, Any], cases: dict[str, dict[str, Any]], routing: dict[str, dict[str, Any]], duplicate_savings: int = 0) -> dict[str, Any]:
    require(duplicate_savings == 0, "review-only duplicate bytes cannot be deducted")
    storage_policy = policy["storage_projection"]
    parts = [component(f"intermediate-{family}", int(routing[family]["ready_job_bytes"]), output_ratio_bp(cases[family]), ["BAS-MEASURED-INVENTORY", "BAS-MEASURED-PILOT", "BAS-ASSUME-PILOT-EXTRAPOLATION"]) for family in PILOT_FAMILIES]
    audio = int(routing["wav"]["ready_job_bytes"]) + int(routing["mp3"]["ready_job_bytes"])
    parts.append(component("intermediate-audio", audio, int(storage_policy["output_expansion_basis_points"]["audio"]), ["BAS-MEASURED-INVENTORY", "BAS-ASSUME-STORAGE"]))
    parts.append(component("intermediate-zif", int(routing["zif"]["ready_job_bytes"]), int(storage_policy["output_expansion_basis_points"]["zif"]), ["BAS-MEASURED-INVENTORY", "BAS-ASSUME-STORAGE"]))
    manual = sum(int(p215["summary"]["routes"][r]["bytes"]) for r in ROUTES if r.startswith("manual-"))
    require(manual == int(pilot["routing_totals"]["manual_job_bytes"]), "manual job bytes differ")
    parts.append(component("intermediate-manual", manual, int(storage_policy["output_expansion_basis_points"]["manual"]), ["BAS-MEASURED-INVENTORY", "BAS-ASSUME-STORAGE"]))
    intermediate = sum(int(item["projected_bytes"]) for item in parts)
    ue = component("ue-content", intermediate, int(storage_policy["ue_content_per_intermediate_basis_points"]), ["BAS-ASSUME-STORAGE"])
    build = component("build-cache", int(ue["projected_bytes"]), int(storage_policy["build_cache_per_ue_content_basis_points"]), ["BAS-ASSUME-STORAGE"])
    parts += [ue, build]
    capacity = p218["summary"]["capacity"]
    source = int(capacity["asset_bytes"])
    metadata = sum(int(capacity[k]) for k in ("normalized_table_bytes", "package_graph_bytes", "reference_closure_bytes"))
    parts[0:0] = [component("source-retained", source, 10_000, ["BAS-MEASURED-INVENTORY"]), component("metadata-retained", metadata, 10_000, ["BAS-MEASURED-INVENTORY"])]
    ue_bytes, build_bytes = int(ue["projected_bytes"]), int(build["projected_bytes"])
    one_copy = source + metadata + intermediate + ue_bytes + build_bytes
    copies = int(storage_policy["recovery_copy_count"])
    recovery = one_copy * copies
    parts.append(component("durable-recovery", one_copy, copies * 10_000, ["BAS-ASSUME-STORAGE"]))
    base_incremental = intermediate + ue_bytes + build_bytes + recovery
    reserve_bp = int(storage_policy["total_risk_reserve_basis_points"])
    reserve = scaled_integer(base_incremental, reserve_bp)
    incremental = base_incremental + reserve
    observed = pilot["environment"]["storage"]
    existing, disk_total, disk_free = int(observed["rebuild_bytes"]), int(observed["workspace_volume_total_bytes"]), int(observed["workspace_volume_available_bytes"])
    gap = max(0, incremental - disk_free)
    return {"basis_ids": ["BAS-MEASURED-INVENTORY", "BAS-MEASURED-PILOT", "BAS-MEASURED-HOST-STORAGE", "BAS-ASSUME-PILOT-EXTRAPOLATION", "BAS-ASSUME-STORAGE", "BAS-RISK-STORAGE"], "build_cache_estimated_bytes": build_bytes, "by_component": parts, "capacity_gap_bytes": gap, "capacity_sufficient": gap == 0, "deduplication_savings_assumed": False, "disk_free_bytes": disk_free, "disk_total_bytes": disk_total, "duplicate_redundant_review_only_bytes": int(capacity["exact_duplicate_redundant_bytes_review_only"]), "existing_workspace_bytes": existing, "incremental_required_bytes": incremental, "intermediate_estimated_bytes": intermediate, "one_copy_bytes": one_copy, "recovery_bytes": recovery, "recovery_copy_count": copies, "risk_reserve_basis_points": reserve_bp, "risk_reserve_bytes": reserve, "source_retained_bytes": source, "total_budget_bytes": existing + incremental, "ue_content_estimated_bytes": ue_bytes, "unit": "bytes"}
