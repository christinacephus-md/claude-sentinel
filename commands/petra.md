---
description: "PETRA — 4-agent parallel PR review with KAIROS pattern learning. Posts consolidated findings to GitHub."
argument-hint: "<PR number> [--skip-codex] [--skip-post] [--base <ref>]"
---

# PETRA — Pattern-Extracted Testing & Review Agent

PETRA dispatches 4 specialized review agents in parallel, consolidates findings, filters false positives, and posts results to GitHub. Learns from historical review patterns via KAIROS.

## Step 1: Parse Arguments & Detect Repo

Extract from `$ARGUMENTS`:
- **PR number**: a number (e.g., `96`) or blank for auto-detect
- **--skip-codex**: skip the Codex review pass
- **--skip-post**: don't post to GitHub, output locally only
- **--base <ref>**: base branch for diff (default: `main`)

```bash
# Auto-detect repo from git remote
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]||;s|\.git$||')
if [ -z "$REPO" ]; then
  echo "ERROR: Could not detect GitHub repo. Are you in a git repo with a GitHub remote?"
  exit 1
fi

# Validate PR number
PR_NUM=$(echo "$ARGUMENTS" | grep -oE '^[0-9]+' | head -1)
if [ -z "$PR_NUM" ]; then
  PR_NUM=$(gh pr list --head $(git branch --show-current) --repo "$REPO" --state open --json number --jq '.[0].number')
fi
if [ -z "$PR_NUM" ] || [ "$PR_NUM" = "null" ]; then
  echo "No PR found. Usage: /petra <PR_NUMBER> or run from a branch with an open PR."
  exit 1
fi

# Parse flags
BASE=$(echo "$ARGUMENTS" | grep -oP '(?<=--base\s)\S+' || echo "main")
```

## Step 2: Gather Context

```bash
gh pr diff "$PR_NUM" --repo "$REPO" > /tmp/pr-diff.txt
gh pr view "$PR_NUM" --repo "$REPO" --json title,author,files,body
```

## Step 3: Load Learned Patterns

Read `REVIEW.md` from the repo root if it exists. Extract:
- Developer-specific patterns for the PR author
- Area-specific patterns for the changed files
- Recurring finding types from past reviews

If no REVIEW.md exists, check if `~/.claude/plugins/sentinel/config/review-patterns-seed.md` exists and note that `/petra-rebuild` should be run to generate patterns.

## Step 4: Launch 4 Review Agents in Parallel

Use the Agent tool to launch all 4 simultaneously:

1. **petra-code** agent — bugs, logic errors, convention violations, CLAUDE.md compliance
2. **petra-simplify** agent — duplication, dead code, unnecessary complexity, missed shared modules
3. **petra-security** agent — PHI exposure (18 HIPAA identifiers from Sentinel config), injection, auth gaps, infrastructure misconfig
4. **codex review** (unless `--skip-codex`) — run `/codex:review --base <base> --wait` for edge-case correctness and runtime fragility

Each agent receives:
- The PR diff
- The REVIEW.md patterns relevant to the changed files/author
- The CLAUDE.md project conventions

## Step 5: Consolidate Findings

Merge all agent outputs into a single report. For each finding:
- Assign severity: `blocker` / `medium` / `low` / `nit`
- Deduplicate — if multiple agents flag the same issue, merge into one finding with the highest severity
- Cross-reference against REVIEW.md patterns — if a pattern matches, note it

## Step 6: Verification Pass

For each `blocker` or `medium` finding:
- Re-read the actual code at the flagged location
- Confirm the issue is real (not a false positive from diff context)
- Check if the issue is pre-existing (from `git blame`) vs introduced in this PR
- Drop findings that are pre-existing, linter-catchable, or speculative

## Step 7: Format and Post

Format the consolidated review as:

```markdown
## PETRA Review — #<NUMBER>

**Agents:** petra-code · petra-simplify · petra-security · codex
**Files changed:** <count>
**Patterns loaded:** REVIEW.md (KAIROS)

---

### Security Audit

| Check | Result |
|---|---|
| PHI/PII | PASS or FAIL |
| Credentials | PASS or FAIL |
| Injection | PASS or FAIL |

---

### Blockers (must fix)
- **[blocker]** `file:line` — description
  - *Found by:* <agent(s)>
  - *Pattern:* <REVIEW.md pattern if matched>

### Medium (should fix)
...

### Low / Nits
...

### Strengths
- Notable positives worth calling out

---

*Review powered by PETRA (Pattern-Extracted Testing & Review Agent). Patterns loaded from REVIEW.md via KAIROS.*
```

Unless `--skip-post`, post to GitHub:
```bash
gh pr comment "$PR_NUM" --repo "$REPO" --body "<review>"
```

## Step 8: Learn

After posting, the review comment itself IS the learning event. Do NOT append to REVIEW.md directly — `/petra-rebuild` is the sole authoritative source for pattern generation. It reads all past review comments and extracts patterns from them.

## Important Rules

- Never auto-apply fixes. Report only.
- If Codex is unavailable or times out, continue with the 3-agent results.
- Findings must have specific file paths and line numbers.
- Pre-existing issues (from git blame) are informational only, not blockers.
- When in doubt about severity, downgrade rather than upgrade.
