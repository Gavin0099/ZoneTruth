# Knowledge Base

## Gotchas

- Record troubleshooting notes, anti-patterns, and fixes here.
- The latest PLAN.md narrows MVP scope to Zone 2 judgment plus basic activity review.
- VO2 / Interval and Strength are intentionally deferred because heart rate alone is not trusted enough for first-pass verdicts.
- The useful core signals for MVP are zone distribution, Zone 3 leakage, HR stability, and HR drift.
- Analysis should stay session-level and explainable; avoid pretending heart rate is ground truth.
- This environment does not have a Swift toolchain, so code structure was updated but local `swift test` verification is still pending.
