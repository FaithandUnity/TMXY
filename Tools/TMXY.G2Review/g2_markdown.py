"""Human-readable rendering for the deterministic P2-20 G2 review."""
from __future__ import annotations
from typing import Any


def markdown(report: dict[str, Any]) -> str:
    lines = [
        "# P2-20 G2 Data Review", "",
        f"- Review execution: `{report['review_execution_result']}`",
        f"- Gate decision: `{report['gate_decision']}`",
        f"- Task status: `{report['task_status']}`",
        f"- G2 approved: `{str(report['g2_approved']).lower()}`",
        f"- P3 authorized: `{str(report['p3_authorized']).lower()}`",
        f"- Evidence snapshot: `{report['captured_utc']}`", "",
        ("The review procedure completed successfully, but the gate remains fail-closed. "
         "A successful review execution is not a successful G2 decision."
         if not report["g2_approved"] else
         "The review procedure and every policy criterion completed successfully; G2 is approved."),
        "", "## Criterion outcome", "",
        "| Criterion | Status | Interpretation |", "| --- | --- | --- |",
    ]
    for item in report["criteria"]:
        lines.append(f"| {item['id']} | {item['observed_status']} | {item['interpretation']} |")
    lines.extend(["", "## Blocking findings", ""])
    for blocker in report["blockers"]:
        lines.extend([
            f"### {blocker['id']}: {blocker['title']}", "", blocker["reason"], "",
            f"Required closure: {blocker['required_action']}", "",
        ])
    budget = report["budget_interpretation"]
    lines.extend([
        "## Budget interpretation", "",
        f"Manual content is {budget['manual_content_assets']} of {budget['total_content_assets']} assets ({budget['manual_content_rate_ppm']} ppm, floor-rounded). P2-19 records {budget['base_planning_hours']} base planning hours and {budget['risk_adjusted_planning_hours']} risk-adjusted planning hours.",
        "",
        f"The storage budget is {budget['storage_budget_bytes']} bytes, including {budget['incremental_storage_required_bytes']} incremental bytes and a {budget['storage_capacity_gap_bytes']} byte capacity gap. These are planning values, not measured delivery duration, a financial total cost, a price, or a delivery commitment.",
        "", "## Authority boundary", "",
        "This review does not prove a complete playable build, authorize P3, grant release or production authority, recover an unseen official server implementation, or authorize automatic repair/deletion of unlinked or duplicate resources.",
        "", "## Reproduction", "",
        "Run `pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1`, then rerun with `-Check`. Generation uses the locked non-root builder with a read-only repository mount, no network, no Linux capabilities, and no-new-privileges.",
        "",
    ])
    return "\n".join(lines)
