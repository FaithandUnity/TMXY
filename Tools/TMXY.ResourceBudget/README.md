# TMXY.ResourceBudget

`TMXY.ResourceBudget` produces the deterministic P2-19 conditional resource
budget. The report binds the P2-15 routing evidence, P2-18 content-health
evidence, and the sanitized P2-19 conversion pilot by exact SHA-256.

The tool deliberately separates five basis categories: measured facts,
planning coefficients, assumptions, risk reserves, and missing measurements.
Exporter elapsed time and output size are measured only for the selected pilot
cases. Scaling those observations to the full alias-excluded ready-job byte
population is the explicit `BAS-ASSUME-PILOT-EXTRAPOLATION` assumption, not a
measurement.

Run the isolated wrapper from the Rebuild root:

```powershell
.\Tools\TMXY.ResourceBudget\New-ResourceBudgetReport.ps1
.\Tools\TMXY.ResourceBudget\New-ResourceBudgetReport.ps1 -Check
```

The wrapper requires the locked non-root builder, a read-only repository mount,
no network, and a writable temporary output mount. `-Check` regenerates both
reports byte-for-byte and compares the complete frozen P2-19 evidence object
after preserving its captured timestamp.

The Python implementation is split to satisfy repository size limits:

- `resource_budget.py`: CLI and output orchestration;
- `budget_common.py`: deterministic arithmetic, basis catalog, and SHA chain;
- `budget_model.py`: human, machine, and storage calculations;
- `budget_program.py`: program scenarios, risks, and report assembly;
- `budget_render.py`: Markdown rendering and negative self-tests.

`--self-test` includes failure cases for a missing basis category, negative
reserve, alias double-counting, review-only duplicate deduction, forged
authority, and a mismatched input task.

The result `PASS_WITH_OPEN_MEASUREMENT_GAPS` means budget accounting is complete
enough for a conditional planning baseline. It does not provide a price,
delivery commitment, playable build, G2 approval, or release authority.
