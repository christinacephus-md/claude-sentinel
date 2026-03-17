# Claude Model Router v4.0.1

<p align="center">
  <img src="model-router-v4.png" alt="Claude Model Router v4.0 - Intelligent Routing and Cost Optimization" width="700">
</p>

<p align="center">
  <strong>The full Claude Code discipline layer.</strong><br>
  Model routing, git hygiene enforcement, commit quality gates, session telemetry, and DX automation hooks — installed with one command.
</p>

<p align="center">
  <a href="#install">Install</a> &bull;
  <a href="#what-you-get">Features</a> &bull;
  <a href="#git-hygiene">Git Hygiene</a> &bull;
  <a href="#claude-code-hooks">Hooks</a> &bull;
  <a href="#cost-tracking">Cost Tracking</a>
</p>

---

## The Problem

1. Running Opus for "yes" and "looks good" burns 60x more than Haiku
2. Long conversations silently rack up cache write costs ($2-4/prompt on Opus at 100K+ context)
3. Claude Code injects `Co-Authored-By` and `Generated with Claude Code` into your git history
4. No visibility into where tokens are going across projects
5. No guardrails on commit message quality
6. No session-level telemetry for async team handoffs

## The Fix

v4 is a single install that covers all six. Model routing uses tiered keyword weights, word boundary matching, and downgrade signals to aggressively route simple tasks to Haiku. Git hooks strip AI trailers before they hit your history. Conventional commit gates enforce message quality. Session summaries log what happened. All of it stacks with `/fast` mode.

---

## Install

```bash
git clone https://github.com/christinacephus-md/claude-model-router.git
cd claude-model-router

# Core install (routing + Claude Code hooks)
./install.sh --force

# Full install (add git hooks too)
./install.sh --all

# Update existing install (preserves your config)
./install.sh --update --force
```

---

## What You Get

### 1. Model Routing (UserPromptSubmit)

Every prompt scored across 5 factors with tiered keyword weights, word boundary matching, and downgrade signal detection. Short follow-ups auto-route to Haiku. v4.0 adds savings tracking vs an all-Opus baseline.

```
+---------------------------------------------------------+
|  Model Router v4.0 - Cost Optimization                  |
+---------------------------------------------------------+

  Analysis:
    Keywords: Simple=2 Complex=0 Downgrade=3
    Tool Complexity: LOW
    File Context: no_files
    Inference Depth: SHALLOW
    Conversation: CONTINUATION
    Score: -7

  Recommendation: /model haiku
    Reason: Short follow-up

  Cost (per 1M input tokens):
    Haiku:  $0.25   Sonnet: $3.00   Opus: $15.00

  Today: 23 prompts | H:16 S:5 O:2 | Est: $1.12
  Saved vs all-Opus: $4.38
  Session: 8 prompts (~40K context)
```

At deeper sessions, cache cost alerts appear automatically:

```
  WARNING: Session depth: 25 prompts (~125K context)
    Cache write/prompt: Opus=$2.34  Sonnet=$0.47
    -> Cache costs growing — try /compact or start fresh
```

### 2. Git Hygiene (commit-msg, prepare-commit-msg, pre-push)

Three git hooks working together to keep your history clean:

**prepare-commit-msg** — strips AI trailers before the editor opens:
- `Co-Authored-By: Claude Code <noreply@anthropic.com>` — removed
- `Generated with [Claude Code]` — removed
- Developer never sees them

**commit-msg** — conventional commit enforcement:
- Blocks commits that don't match `feat|fix|chore|docs|refactor|test|style|ci|perf|build|revert:`
- Warns on subject lines >72 chars
- Hints when past tense is used ("Added" -> use imperative)
- Bypass with `--no-verify` when needed

**pre-push** — last line of defense:
- Scans outgoing commits for leaked AI trailers (scoped to `origin/{default-branch}..HEAD` on new branches)
- Blocks the push with a clear message showing which commits are dirty
- Bypass with `--no-verify`

Install git hooks globally or per-repo:
```bash
# Global (all repos)
git config --global core.hooksPath ~/.claude/plugins/model-router/git-hooks

# Per-repo
ln -sf ~/.claude/plugins/model-router/hooks/commit-msg .git/hooks/commit-msg
ln -sf ~/.claude/plugins/model-router/hooks/prepare-commit-msg .git/hooks/prepare-commit-msg
ln -sf ~/.claude/plugins/model-router/hooks/pre-push .git/hooks/pre-push
```

### 3. PreToolUse Hook — Git Command Interception

Fires before Bash tool calls. Catches `git commit`, `gh pr create`, and `git push` commands:
- Warns when AI markers are present in commit messages or PR bodies
- Logs git push operations for audit trail

### 4. PostToolUse Hook — DX Feedback

Fires after Write, Edit, and Bash tool calls:
- Tracks all file changes to a log for session summary
- Detects when a source file is modified that has a corresponding test file — reminds you to update tests
- Logs all bash commands for session replay

### 5. Stop Hook — Session Summary

When Claude Code finishes a turn, auto-generates:
```
+---------------------------------------------------------+
|  Session Summary                                        |
+---------------------------------------------------------+

  Routing:  47 prompts (H:28 S:15 O:4)
  Est cost: $3.42 today
  Files:    12 changes tracked
  Git ops:  3 operations
```

Appends to `~/.claude/plugins/model-router/logs/session_summary.log` for async handoffs.

### 6. Session Depth Tracking + Cache Cost Alerts

Tracks prompt count per session and warns when cache write costs are growing. Based on real billing data showing cache writes as 47% of total spend.

| Threshold | Level | Action |
|-----------|-------|--------|
| 15 prompts (~75K context) | TIP | Suggest `/compact` |
| 25 prompts (~125K context) | WARNING | Cache costs growing, shows $/prompt |
| 40 prompts (~200K context) | ALERT | Start a new conversation |

Shows estimated cache write cost per prompt for Opus vs Sonnet so you can see the real cost of staying in a long session.

### 7. Cost Tracking + Budget Alerts

```bash
# Today
python3 ~/.claude/plugins/model-router/hooks/cost_report.py

# This week by project
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --week --project

# All time
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --all
```

Budget alerts at 80% of daily/weekly limits. Configure in `config/budget.json`.

### 8. Router Advisor Agent + Slash Commands

Symlink into any project:
```bash
mkdir -p .claude/agents .claude/commands
ln -s ~/.claude/plugins/model-router/agents/router-advisor.md .claude/agents/
ln -s ~/.claude/plugins/model-router/commands/cost-report.md .claude/commands/
ln -s ~/.claude/plugins/model-router/commands/budget-check.md .claude/commands/
```

---

## Works With /fast Mode

The routing hook runs on `UserPromptSubmit` (before model processing). `/fast` controls output speed. They operate on different layers and stack cleanly.

---

## Project-Specific Patterns

Drop `.claude/router-patterns.json` in any project:
```json
{
  "haiku_keywords": ["lookup patient", "check appointment"],
  "opus_keywords": ["hipaa", "phi audit", "compliance review"]
}
```

---

## settings.json Reference

Full hooks block that `--force` installs:
```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "python3 ~/.claude/plugins/model-router/hooks/model_router.py" }] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "bash ~/.claude/plugins/model-router/hooks/pre_tool_use.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|Bash", "hooks": [{ "type": "command", "command": "bash ~/.claude/plugins/model-router/hooks/post_tool_use.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/plugins/model-router/hooks/stop_hook.sh" }] }
    ]
  }
}
```

---

## Testing

```bash
./test_hook.sh
```

21 tests covering routing accuracy, cost reports, git trailer stripping, conventional commit enforcement, past tense detection, and all Claude Code hooks.

---

## Structure

```
claude-model-router/
├── install.sh                     # One-command install (--force, --git-hooks, --update, --all)
├── uninstall.sh                   # Clean removal (preserves logs)
├── test_hook.sh                   # 21-test suite
├── plugin/
│   ├── plugin.json
│   ├── hooks/
│   │   ├── model_router.py        # 6-factor routing engine + session tracking
│   │   ├── cost_report.py         # Cost report generator
│   │   ├── pre_tool_use.sh        # Git command interception
│   │   ├── post_tool_use.sh       # File change tracking + test reminders
│   │   └── stop_hook.sh           # Session summary generator
│   └── config/
│       ├── patterns.json          # Routing keywords (with healthcare)
│       └── budget.json            # Daily/weekly limits
├── git-hooks/
│   ├── prepare-commit-msg         # Strip AI trailers before editor
│   ├── commit-msg                 # Conventional commit + final trailer strip
│   └── pre-push                   # Block pushes with leaked AI trailers
├── agents/
│   └── router-advisor.md          # Model selection subagent
├── commands/
│   ├── cost-report.md             # /cost-report slash command
│   └── budget-check.md            # /budget-check slash command
├── examples/
│   ├── custom_patterns.json
│   └── healthcare_patterns.json
└── docs/
```

## Version History

- **v4.0.1** - Fix pre-push hook scanning entire git history on new branches — now scopes to `origin/{main,master}..HEAD` instead of walking all reachable commits; fix awk SHA parsing in blocked-commit listing
- **v4.0.0** - Tiered keyword weights (1-4 pts by signal strength), word boundary regex matching, downgrade signals ("just", "quickly", "trivial"), stricter opus threshold (10 vs 7), wider haiku band (score <= -1), short prompt cap (<60 chars can't trigger opus), expanded continuation detection (35+ phrases), savings tracking vs all-opus baseline, session depth tracking with cache cost alerts at 15/25/40 prompt thresholds
- **v3.1.0** - Token-weighted cost estimates (prompt length / 4 + context overhead), per-row Opus baseline calculation, backward-compatible CSV format, honest savings metrics
- **v3.0.0** - Git hygiene (3 hooks), PreToolUse/PostToolUse/Stop Claude Code hooks, conventional commit enforcement, session telemetry, restructured install with --update/--git-hooks/--all, JSON validation
- **v2.0.0** - Cost tracking, budget alerts, conversation depth, agents, commands
- **v1.0.0** - Multi-factor keyword routing

## Author

Christina Cephus

## License

MIT
