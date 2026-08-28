# TMXY G2 review generator

`New-G2Review.ps1` regenerates the P2-20 G2 review inside the locked non-root
builder. The repository is mounted read-only and the container runs without a
network, Linux capabilities, or privilege escalation.

`g2_review.py` assembles the gate report. `g2_evidence.py` independently binds
the prerequisite, P2-20A supplemental, P2-20B remediation, and quality inputs,
then recomputes G2-06 and G2-07 from their full machine evidence instead of
trusting reported completion flags or machine suggestions.

```powershell
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1
pwsh -File Tools/TMXY.G2Review/New-G2Review.ps1 -Check
```

The command returning successfully means the review procedure and contracts
worked. It does not convert a `BLOCKED` gate decision into a pass.
