# VALIDATION.md — User Acceptance Testing Checklist

**ITGC-SDLC-6: User Acceptance Testing**

This checklist validates that the Claude Sentinel is functioning correctly after installation or upgrade. Complete all items and sign off at the bottom.

---

## Pre-Validation

| # | Check | Status |
|---|-------|--------|
| 1 | Python 3 installed: `python3 --version` | [ ] |
| 2 | Claude Code installed: `claude --version` | [ ] |
| 3 | Plugin files present: `ls ~/.claude/plugins/sentinel/hooks/` | [ ] |
| 4 | Settings wired: `grep sentinel ~/.claude/settings.json` | [ ] |

## Core Routing Validation

Open a new Claude Code session and verify each scenario:

| # | Prompt to Test | Expected Result | Actual | Pass? |
|---|---------------|-----------------|--------|-------|
| 5 | "yes" | Haiku (short follow-up) | | [ ] |
| 6 | "show me the version" | Haiku (simple task) | | [ ] |
| 7 | "Add error handling to auth.go" | Sonnet (balanced) | | [ ] |
| 8 | "this is crashing with a stack trace, debug it" | Sonnet (debug floor) | | [ ] |
| 9 | "review this PR for the auth refactor" | Sonnet (review floor) | | [ ] |
| 10 | "Architect a distributed system from the ground up with HIPAA compliance" | Opus (complex) | | [ ] |

## v5.0 Feature Validation

| # | Feature | How to Verify | Pass? |
|---|---------|---------------|-------|
| 11 | Debug routing | Router output shows `Debug=` score in Analysis | [ ] |
| 12 | Review routing | Router output shows `Review=` score in Analysis | [ ] |
| 13 | Subagent tracking | After using Agent tool, check session file for `subagent_spawns` | [ ] |
| 14 | TDD nudge | Edit a `.py` file without a test file — should see "TDD Nudge" | [ ] |
| 15 | Session depth | After 15+ prompts, should see TIP with compaction suggestion | [ ] |
| 16 | Smart compaction | With high subagent/file-read count, should see COMPACT advisory | [ ] |

## Git Hook Validation

| # | Hook | How to Verify | Pass? |
|---|------|---------------|-------|
| 17 | prepare-commit-msg | Commit with AI trailer — should be stripped silently | [ ] |
| 18 | commit-msg | Commit "bad message" — should be blocked | [ ] |
| 19 | commit-msg | Commit "feat: valid message" — should pass | [ ] |
| 20 | pre-push | Push with AI trailer in history — should be blocked | [ ] |
| 21 | pre-push (v5.0) | Push with 2000+ line diff — should warn about PR size | [ ] |

## Cost Tracking Validation

| # | Check | How to Verify | Pass? |
|---|-------|---------------|-------|
| 22 | Cost log populates | `wc -l ~/.claude/plugins/sentinel/logs/cost_log.csv` | [ ] |
| 23 | Cost report runs | `python3 ~/.claude/plugins/sentinel/hooks/cost_report.py` | [ ] |
| 24 | Budget alerts | Set low daily_limit in budget.json, verify alert appears | [ ] |

## Automated Test Suite

| # | Check | Status |
|---|-------|--------|
| 25 | Run `./test_hook.sh` — all tests pass | [ ] |
| 26 | Test sign-off log created at `logs/test_results.log` | [ ] |

---

## Sign-Off

| Field | Value |
|-------|-------|
| **Tester** | |
| **Date** | |
| **Version** | v5.0.0 |
| **All checks passed?** | [ ] Yes / [ ] No |
| **Notes** | |

**If any checks fail**, document the failure in `docs/ISSUES.md` before signing off.
