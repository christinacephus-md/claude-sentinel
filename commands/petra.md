---
description: "PETRA — 5-agent parallel PR review with KAIROS pattern learning. Supports review, re-review, and self-review modes."
argument-hint: "<PR number> [--self] [--re-review] [--skip-codex] [--skip-post] [--base <ref>]"
---

# PETRA — Pattern-Extracted Testing & Review Agent

PETRA dispatches 5 specialized review agents in parallel, consolidates findings, filters false positives, and posts results to GitHub. Learns from historical review patterns via KAIROS.

**Modes:**
- `/petra 96` — fresh full review of PR #96
- `/petra 96 --re-review` — find previous PETRA comment, track FIXED/NOT FIXED per finding
- `/petra --self` — review your own uncommitted changes before pushing (no PR needed)
- `/petra` — auto-detect current branch's open PR

## Step 1: Parse Arguments & Detect Repo

Extract from `$ARGUMENTS`:
- **PR number**: a number (e.g., `96`) or blank for auto-detect
- **--self**: self-review mode (review uncommitted changes, no PR needed)
- **--re-review**: re-review mode (track which previous findings are fixed)
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

# Parse flags
SELF_MODE=false
RE_REVIEW=false
echo "$ARGUMENTS" | grep -q "\-\-self" && SELF_MODE=true
echo "$ARGUMENTS" | grep -q "\-\-re-review" && RE_REVIEW=true
BASE=$(echo "$ARGUMENTS" | sed -n 's/.*--base \([^ ]*\).*/\1/p')
BASE="${BASE:-main}"

# Mode: self-review (no PR needed)
if [ "$SELF_MODE" = "true" ]; then
  git diff > /tmp/pr-diff.txt
  if [ ! -s /tmp/pr-diff.txt ]; then
    git diff --staged > /tmp/pr-diff.txt
  fi
  if [ ! -s /tmp/pr-diff.txt ]; then
    echo "No uncommitted or staged changes found. Nothing to self-review."
    exit 0
  fi
  PR_NUM="self"
  echo "Self-review mode: reviewing uncommitted changes"
else
  # Validate PR number
  PR_NUM=$(echo "$ARGUMENTS" | grep -oE '^[0-9]+' | head -1)
  if [ -z "$PR_NUM" ]; then
    PR_NUM=$(gh pr list --head $(git branch --show-current) --repo "$REPO" --state open --json number --jq '.[0].number')
  fi
  if [ -z "$PR_NUM" ] || [ "$PR_NUM" = "null" ]; then
    echo "No PR found. Usage: /petra <PR_NUMBER>, /petra --self, or run from a branch with an open PR."
    exit 0
  fi
fi
```

## Step 2: Gather Context

If in self-review mode, the diff is already in `/tmp/pr-diff.txt` from Step 1.

Otherwise, fetch the PR diff and metadata:
```bash
gh pr diff "$PR_NUM" --repo "$REPO" > /tmp/pr-diff.txt
gh pr view "$PR_NUM" --repo "$REPO" --json title,author,files,body,headRefOid
```

If `--re-review`: find the most recent PETRA review comment on this PR:
```bash
gh api "repos/$REPO/issues/$PR_NUM/comments" --jq '[.[] | select(.body | startswith("## PETRA"))] | last | {id: .id, body: .body, created_at: .created_at}'
```
Extract each numbered finding from the previous review. Then get commits since that comment was posted to identify what changed. For each previous finding, check if the flagged code was modified in the fix commits.

## Step 3: Load Learned Patterns

Read `REVIEW.md` from the repo root if it exists. Extract:
- Developer-specific patterns for the PR author
- Area-specific patterns for the changed files
- Recurring finding types from past reviews

If no REVIEW.md exists, check if `~/.claude/plugins/sentinel/config/review-patterns-seed.md` exists and note that `/petra-rebuild` should be run to generate patterns.

Also check for KAIROS auto-trigger: read `~/.claude/petra-review-count.json`. If 5+ reviews since last rebuild OR 2+ days since last rebuild, run `/petra-rebuild` automatically before proceeding.

## Step 4: Launch 5 Review Agents in Parallel

Use the Agent tool to launch all 5 simultaneously:

1. **petra-code** agent — bugs, logic errors, convention violations, CLAUDE.md compliance
2. **petra-simplify** agent — duplication, dead code, unnecessary complexity, missed shared modules
3. **petra-security** agent — PHI exposure (18 HIPAA identifiers from Sentinel config), injection, auth gaps, infrastructure misconfig
4. **petra-history** agent — git blame for pre-existing issues, file churn analysis, previous PR feedback on the same files
5. **codex review** (unless `--skip-codex`) — run `/codex:review --base <base> --wait` for edge-case correctness and runtime fragility

Each agent receives:
- The PR diff (or self-review diff)
- The REVIEW.md patterns relevant to the changed files/author
- The CLAUDE.md project conventions

In **self-review mode**: agents focus on catching issues before the author pushes. Findings are printed to console only (no GitHub post). The tone is advisory ("consider fixing before push") rather than gating ("must fix before merge").

In **re-review mode**: agents only review the inter-diff (changes since the previous review). Previous findings are tracked as FIXED / NOT FIXED / PARTIALLY FIXED based on whether the flagged code was modified.

## Step 5: Consolidate Findings

Merge all agent outputs into a single report. For each finding:
- Assign severity: `blocker` / `medium` / `low` / `nit`
- Deduplicate — if multiple agents flag the same issue, merge into one finding with the highest severity
- Cross-reference against REVIEW.md patterns — if a pattern matches, note it
- If petra-history identifies a finding as pre-existing (via git blame), classify as `pre-existing` rather than a new finding

## Step 6: Verification Pass

For each `blocker` or `medium` finding:
- Re-read the actual code at the flagged location
- Confirm the issue is real (not a false positive from diff context)
- Check if the issue is pre-existing (from petra-history blame data)
- Drop findings that are linter-catchable or speculative
- Pre-existing findings get their own section (informational, not blocking)

## Step 7: Format and Post

**Fresh review format:**

```markdown
`✦ PETRA v7.0 · 5 agents · KAIROS ✦`

## PETRA Review — #<NUMBER>

**Agents:** petra-code · petra-simplify · petra-security · petra-history · codex
**Files changed:** <count>
**Patterns loaded:** REVIEW.md (KAIROS)
**Reviewed at:** <headRefOid SHA>

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

### Pre-existing (informational)
- `file:line` — description (pre-dates this PR per git blame)

### Strengths
- Notable positives worth calling out

---

*Review powered by PETRA v7.0 (Sentinel). Patterns loaded from REVIEW.md via KAIROS.*
```

**Re-review format:**

```markdown
## PETRA Re-Review — #<NUMBER>

**Mode:** re-review (tracking fixes from previous review)

### Previous Findings

| # | Finding | Status |
|---|---|---|
| 1 | [description] | FIXED / NOT FIXED / PARTIALLY FIXED |
| 2 | [description] | FIXED / NOT FIXED / PARTIALLY FIXED |

### New Findings (from changes since last review)
...

---

*Review powered by PETRA v7.0 (Sentinel). Patterns loaded from REVIEW.md via KAIROS.*
```

**Self-review format** (console only, no GitHub post):

```
PETRA Self-Review — uncommitted changes

Findings:
  [blocker] file:line — description
  [medium]  file:line — description

Recommendation: fix blockers before pushing.
```

Post to GitHub (unless `--skip-post` or self-review mode):
```bash
gh pr comment "$PR_NUM" --repo "$REPO" --body "<review>"
```

## Step 8: Learn

After posting, the review comment itself IS the learning event. Do NOT append to REVIEW.md directly — `/petra-rebuild` is the sole authoritative source for pattern generation.

Increment the review counter in `~/.claude/petra-review-count.json`:
```json
{"count": N, "last_rebuild": "YYYY-MM-DD"}
```
If count >= 5 or last_rebuild is 2+ days ago, run `/petra-rebuild` automatically.

## Important Rules

- Never auto-apply fixes. Report only. (Exception: `/petra --self --fix` may auto-apply in a future version.)
- If Codex is unavailable or times out, continue with the 4-agent results.
- Findings must have specific file paths and line numbers.
- Pre-existing issues get their own section — informational, never blockers.
- When in doubt about severity, downgrade rather than upgrade.
- Include `Reviewed at: <SHA>` in every review comment for re-review anchoring.
