---
description: "PETRA KAIROS — regenerate REVIEW.md from GitHub PR review comment history. Pattern extraction from historical events."
argument-hint: "[--limit N]"
---

# PETRA Rebuild — KAIROS Pattern Extraction

Regenerate `REVIEW.md` by mining all historical PR review comments from GitHub. This is the team sync mechanism — patterns are extracted from real review history, not maintained manually.

## Step 1: Detect Repo

```bash
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]||;s|\.git$||')
if [ -z "$REPO" ]; then
  echo "ERROR: Could not detect GitHub repo. Are you in a git repo with a GitHub remote?"
  exit 1
fi
REPO_NAME=$(echo "$REPO" | sed 's|.*/||')
```

## Step 2: Fetch All Review Comments

```bash
# Note: diff_hunk intentionally excluded — may contain PHI from clinical code context
gh api "repos/$REPO/pulls/comments" --paginate --jq '.[] | {
  pr_number: (.pull_request_url | split("/") | last | tonumber),
  author: .user.login,
  body: .body,
  path: .path,
  line: .line,
  created: .created_at
}' > /tmp/review-comments.json

# Also get PR review bodies (the top-level review summaries)
# Rate-limit safe: pause every 10 requests
LIMIT=$(echo "$ARGUMENTS" | grep -oP '(?<=--limit\s)\d+' || echo "100")
COUNT=0
for pr in $(gh pr list --repo "$REPO" --state merged --limit "$LIMIT" --json number --jq '.[].number'); do
  gh api "repos/$REPO/pulls/$pr/reviews" --jq '.[] | {
    pr_number: '$pr',
    reviewer: .user.login,
    state: .state,
    body: .body
  }' 2>/dev/null
  COUNT=$((COUNT + 1))
  if (( COUNT % 10 == 0 )); then sleep 1; fi
done > /tmp/review-summaries.json

# Cleanup temp files when done
trap 'rm -f /tmp/review-comments.json /tmp/review-summaries.json' EXIT
```

## Step 3: Extract Patterns

Analyze the comments for:

**Developer patterns** — recurring issues by PR author:
- "Author X: tends to [pattern]" (e.g., leave debug functions, miss error handling on tool calls)
- Only extract if the same type of finding appears 2+ times for the same author

**Area patterns** — recurring issues by file path/directory:
- Group by top-level directory of the `path` field
- "directory/: watch for [pattern]"

**Finding type patterns** — what review agents catch most often:
- PHI exposure, shell injection, missing validation, stale references, etc.
- Track which agent type (security, code quality, simplification, Codex) finds each category

**Codex-unique patterns** — things only Codex caught that other agents missed:
- Edge-case correctness, type validation gaps, runtime fragility

## Step 4: Write REVIEW.md

Write the file to the repo root with this structure:

```markdown
# PETRA Review Patterns — {REPO_NAME}

> Auto-generated from GitHub PR review history via KAIROS pattern extraction.
> Last rebuilt: {TODAY}
> Source: {REPO} PRs #{first}–#{last}
> To regenerate: `/petra-rebuild`
> To review a PR: `/petra <PR_NUMBER>`

> Note: Patterns are keyed by GitHub handle for KAIROS matching against PR authors.
> These describe code patterns to watch for, not personal judgments.

## Developer Patterns

### {author}
- [pattern description] (seen in PRs #X, #Y)

## Area Patterns

### {directory}/
- [pattern] (PRs #X, #Y)

## Finding Types (by frequency)

| Finding Type | Count | Typical Agent | Example PR |
|---|---|---|---|
| [type] | N | [agent] | #XX |

## Codex-Unique Findings

Patterns where Codex caught issues other agents missed:
- [description] (PR #XX)
```

## Step 5: Report

Output a summary of:
- Total review comments analyzed
- New patterns discovered vs previous REVIEW.md (if it existed)
- Top 5 most frequent finding types
- Recommendation: commit REVIEW.md or review first

## When To Run

- After a batch of PRs are merged (e.g., end of sprint)
- When a new team member joins (to onboard their patterns)
- Anytime — it's idempotent, always rebuilds from scratch

## Sync Strategy

REVIEW.md lives in the repo root. It gets committed like any other file. Because it's auto-generated from GitHub history:
- No manual edits needed (they'll be overwritten on next rebuild)
- Everyone gets the same patterns on `git pull`
- `/petra` loads it automatically before each review
- The rebuild is cheap to run — just API calls + pattern extraction
