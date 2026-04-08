# PETRA Review — Claude Sentinel v6.0

> Reviewed: 2026-04-07
> Agents: code-reviewer · simplify · petra-security
> Codex: skipped (not a PR, local codebase review)

---

## Security Audit

| Check | Result |
|---|---|
| PHI pattern coverage | **FAIL** — only 6 of 18 HIPAA Safe Harbor identifiers |
| Secret detection | **WARN** — missing Slack, Stripe, npm, JWT, DB connection patterns |
| Log file PHI exposure | **FAIL** — raw Bash commands + subagent descriptions logged in plaintext |
| Prompt audit trail | **WARN** — SHA-256 without salt, reversible for short prompts |
| Enforcement mode | **FAIL** — all PHI/secret detections warn-only, never block |
| File write protection | **WARN** — pre-write doesn't check path, only content |
| Log file permissions | **WARN** — default umask, no 0600 enforcement |

---

## Blockers (must fix for v7.0)

**B1. `hooks.json` only registers UserPromptSubmit — PreToolUse, PostToolUse, Stop are missing**
`plugin/hooks/hooks.json`

The `plugin.json` manifest declares all 4 hooks, but `hooks.json` (which Claude Code actually reads for registration) only has `UserPromptSubmit`. This means PHI scanning on Bash commands, post-tool tracking, subagent cost warnings, and stop summaries may never fire depending on which file Claude Code reads.

**B2. Session ID mismatch between Python and shell hooks**
`sentinel.py:528` vs `post_tool_use.sh:19` vs `stop_hook.sh:47`

Python uses `os.getppid()`, shell hooks use `$$`. These produce different IDs for the same session, fragmenting session tracking data. The compaction advisor, subagent tracking, and session summaries all operate on separate files.

**B3. PHI scanner covers only 6 of 18 HIPAA Safe Harbor identifiers**
`sentinel.py:49-56`

Missing: standalone names, geographic data, non-DOB dates, fax numbers, account numbers, health plan IDs, certificate/license numbers, vehicle/device IDs, URLs, IP addresses, biometrics, photos. For a SOC 2 compliance plugin at a healthcare company, this is a blocker.

**B4. Raw Bash commands logged to `session_commands.log` in plaintext**
`post_tool_use.sh:153`

Every `Bash` tool call is logged verbatim — secrets, PHI, everything. This directly contradicts the SHA-256 prompt audit trail design that exists specifically to avoid storing raw content.

**B5. Subagent descriptions logged verbatim to `file_changes.log`**
`post_tool_use.sh:50`

`$DESCRIPTION` from Agent tool calls contains user prompt fragments, which can include PHI.

**B6. `plugin.json` references non-existent `git-hooks/` directory inside `plugin/`**
`plugin/plugin.json:13-16`

The `git_hooks` paths are relative to `plugin/` but the actual hooks live at repo root `git-hooks/`.

---

## Medium (should fix)

**M1. PHI patterns duplicated between sentinel.py and pre_tool_use.sh with drift**
`sentinel.py:49-56` vs `pre_tool_use.sh:95-101`

Python version has 6 patterns, shell version has 5 (missing `patient_medical`, `dob` lacks `born on`). Extract to shared `config/phi_patterns.json`.

**M2. Secret patterns duplicated between pre_tool_use.sh and pre_tool_use_write.sh**
`pre_tool_use.sh:108-115` vs `pre_tool_use_write.sh:44-50`

Write hook missing `bearer` pattern. Same fix: shared config.

**M3. AI-trailer stripping logic triplicated**
`pre_tool_use.sh:31-38`, `git-hooks/prepare-commit-msg:20-24`, `git-hooks/commit-msg:14-18`

commit-msg even calls itself "redundant" in a comment. Extract to shared shell function.

**M4. `patterns.json` loaded but never used for keyword matching**
`sentinel.py:136-161`

`load_patterns()` returns data that's passed to `analyze_keywords()` but never read. The function only uses hardcoded `HAIKU_KEYWORDS`/`OPUS_KEYWORDS`. Dead parameter.

**M5. Weekly budget check is dead code**
`sentinel.py:491-498`

`weekly_limit_usd` is loaded from config but never compared against any weekly total. `monthly_target_usd` and `alert_threshold_pct` in `budget.json` are also never read.

**M6. `cost_report.py` pricing missing `cache_read` field**
`cost_report.py:30-34`

The PRICING dict doesn't match `sentinel.py`'s version. Systematically undercounts costs for cache-heavy sessions.

**M7. PHI scanner warn-only, never blocks**
`sentinel.py:738`, `pre_tool_use.sh:131`

For SOC 2 compliance, there should be at least an option to hard-block when PHI is detected in outbound commands.

**M8. Secret scanner missing common formats**
`pre_tool_use.sh:108-115`

Missing: Slack tokens (`xoxb-`), Stripe keys (`sk_live_`), npm tokens, JWT, DB connection strings with embedded passwords, Azure/GCP service account keys.

**M9. No file permissions on log files**
All hooks using `mkdir -p`

PHI detection logs, prompt audit trail, Bash command logs — all created with default umask. Should be `0600`.

**M10. PHI phone regex high false-positive rate**
`sentinel.py:53`

`\b\d{3}-?\d{3}-?\d{4}\b` matches port numbers, IP fragments, version strings in code-heavy prompts. Alert fatigue risk.

**M11. `stop_hook.sh` grep-based model counting is unreliable**
`stop_hook.sh:18-20`

`grep -c "haiku"` searches entire CSV lines, not just the model column. Project paths or reason text containing "haiku" inflate counts.

**M12. `hooks.json` is disconnected from `plugin.json`**
Should be removed or updated to match `plugin.json` hook declarations.

---

## Low

- **L1.** `patterns.json` version says "5.0", `cost_report.py` docstring says "v3.1" — stale version refs
- **L2.** `sentinel_config.json` has `phi_scanner.enabled` toggle that is never checked — only `scan_prompts` is read
- **L3.** PRICING dict duplicated between `sentinel.py` and `cost_report.py` — extract to shared config
- **L4.** `pre_tool_use_write.sh` could merge into `pre_tool_use.sh` — same hook point, same patterns
- **L5.** `stop_hook.sh` spawns 3 separate Python processes to read 3 keys from the same JSON — consolidate to 1
- **L6.** Broad `except Exception: pass` throughout `sentinel.py` — add `SENTINEL_DEBUG` env var for logging
- **L7.** SHA-256 prompt hash without salt — reversible for short prompts via rainbow table. Use HMAC-SHA256.
- **L8.** `cleanup_stale_sessions` fires when `session_depth % 20 == 0` — fires on 0 (error case)
- **L9.** Sensitive file glob misses: `terraform.tfvars`, `kubeconfig`, `.npmrc`, `.pypirc`, `htpasswd`

---

## Nits

- Box-drawing width mismatch in output banner (`sentinel.py:759`)
- `pre_tool_use.sh` sed uses `[^\n]` which matches "not n", not "not newline"
- Inconsistent output destinations: some hooks use stdout, others stderr

---

## Summary

| Severity | Count |
|---|---|
| Blocker | 6 |
| Medium | 12 |
| Low | 9 |
| Nit | 3 |

### Top 5 Priorities for v7.0

1. **Fix hook registration** — `hooks.json` must declare all 4 hooks or be removed in favor of `plugin.json`
2. **Fix session ID fragmentation** — use a single consistent fallback across Python and shell hooks
3. **Expand PHI coverage** to all 18 HIPAA Safe Harbor identifiers
4. **Stop logging raw Bash commands** — hash or scrub before writing to disk
5. **Extract shared patterns** (PHI, secrets, AI trailers) into a single config file loaded by all hooks

### Strengths

- Non-blocking design — hooks never break the user's workflow
- Cost tracking and model routing are genuinely useful (when session IDs align)
- SOC 2 feature set is ambitious and directionally correct
- Clean separation of concerns: routing (Python), tool gates (shell), git hygiene (git hooks)
- The ITGC-SDLC compliance mapping is thorough documentation
