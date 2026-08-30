"""P2-20A.4 descriptor diagnostic binding for the G2 review."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable


def bind_descriptor_diagnostics(
    root: Path,
    policy: dict[str, Any],
    load_json: Callable[[Path], dict[str, Any]],
    resolve_inside: Callable[[Path, str], Path],
    sha256: Callable[[Path], str],
    require: Callable[[bool, str], None],
) -> tuple[dict[str, Any], dict[str, Any], str]:
    spec = policy["descriptor_diagnostics"]
    relative = spec["path"]
    path = resolve_inside(root, relative)
    descriptor = load_json(path)
    require(descriptor.get("task_id") == spec["task_id"] and
            descriptor.get("criterion_id") == spec["criterion_id"] and
            descriptor.get("evidence_revision") == spec["evidence_revision"] and
            descriptor.get("source_build") == policy["source_build"],
            "P2-20A.4 descriptor diagnostic identity mismatch")
    require(descriptor.get("result") == "BLOCKED" and
            descriptor.get("review_execution_result") == "PASS" and
            descriptor.get("task_status") == "BLOCKED" and
            descriptor.get("completion_criteria_satisfied") is False and
            descriptor.get("diagnostic_scope_complete") is True and
            descriptor.get("g2_06_satisfied") is False and
            descriptor.get("p3_authorized") is False,
            "P2-20A.4 descriptor diagnostic state is inconsistent")
    require(not any(bool(descriptor.get("disclosure", {}).get(name)) for name in
                    ("private_source_paths", "exact_primary_keys", "raw_table_rows",
                     "decoded_confidential_payloads", "legacy_source_lines")),
            "P2-20A.4 descriptor diagnostic disclosure boundary failed")
    inputs = {item["path"]: item for item in descriptor["input_bindings"]}
    for contract in ("Contracts/data-schema/g2-asset-descriptor-diagnostics-policy-v1.json",
                     "Contracts/data-schema/g2-asset-descriptor-diagnostics-v1.schema.json"):
        contract_path = resolve_inside(root, contract)
        require(contract in inputs and inputs[contract]["sha256"] == sha256(contract_path),
                "P2-20A.4 descriptor contract is not hash-bound")
    detail = descriptor["detail_export"]
    detail_path = resolve_inside(root, detail["path"])
    require(detail["tracked"] is False and detail["lines"] == 3651 and
            detail["sha256"] == sha256(detail_path) and
            detail["bytes"] == detail_path.stat().st_size,
            "P2-20A.4 descriptor detail export is not hash-bound")
    digest = sha256(path)
    binding = {
        "task_id": spec["task_id"], "criterion_id": spec["criterion_id"],
        "evidence_revision": spec["evidence_revision"], "path": relative,
        "sha256": digest, "result": descriptor["result"],
        "review_execution_result": descriptor["review_execution_result"],
        "task_status": descriptor["task_status"],
        "completion_criteria_satisfied": descriptor["completion_criteria_satisfied"],
        "diagnostic_scope_complete": descriptor["diagnostic_scope_complete"],
        "g2_06_satisfied": descriptor["g2_06_satisfied"],
    }
    aggregate = (f"DESCRIPTOR|{spec['task_id']}|{spec['criterion_id']}|"
                 f"{spec['evidence_revision']}|{relative}|{digest}")
    return binding, descriptor, aggregate
