# V22 Finalization Evidence — Superseded

> This report is historical. V23 review found that per-node block-opening capture was defined but not wired into `_treeUpdate`. Do not use the V22 result as current release evidence. See `V23_FINAL_AUDIT_REPORT.md`.

This file records reproducible test evidence only. The security verdict and audited commit are in `V22_FINAL_AUDIT_REPORT.md`.

## Clean run

- `forge build`: success with solc 0.8.26 (`test_logs/forge_build.log`)
- Full suite: 174 passed, 0 failed, 0 skipped (`test_logs/forge_test.log`)
- V18: 12 passed, 0 failed, 0 skipped
- V20: 6 passed, 0 failed, 0 skipped
- V21: 7 passed, 0 failed, 0 skipped
- V22: 26 passed, 0 failed, 0 skipped
- Deep simulation: 1 passed, 0 failed, 0 skipped
- Hook-focused suites: 59 passed, 0 failed, 0 skipped

Any source change invalidates these results and requires every affected log to be regenerated.
