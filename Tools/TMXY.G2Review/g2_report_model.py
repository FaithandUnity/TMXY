"""Report-model constructors for the deterministic P2-20 G2 review."""
from __future__ import annotations
from typing import Any


def metric(name: str, value: Any, unit: str) -> dict[str, Any]:
    return {"name": name, "value": value, "unit": unit}


def criterion(
    policy_item: dict[str, Any],
    satisfied: bool,
    metrics: list[dict[str, Any]],
    interpretation: str,
    blockers: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "id": policy_item["id"],
        "statement": policy_item["statement"],
        "required_status": policy_item["required_status"],
        "observed_status": "SATISFIED" if satisfied else "BLOCKED",
        "satisfied": satisfied,
        "evidence_task_ids": policy_item["evidence_task_ids"],
        "metrics": metrics,
        "interpretation": interpretation,
        "blocker_ids": blockers or [],
    }
