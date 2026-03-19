# Access Security & Role Matrix

**ITGC-SDLC-12: Access Security**

This document defines the access roles, permissions, and segregation of duties for the Claude Model Router system.

---

## System Architecture — Access Points

The model router operates across four access layers:

```
Layer 1: Claude Code Hooks (settings.json)
  └─ UserPromptSubmit  → model_router.py   [read-only: analyzes prompt, logs decision]
  └─ PreToolUse        → pre_tool_use.sh   [modify: can alter git commands]
  └─ PostToolUse       → post_tool_use.sh  [read-only: logs activity, displays warnings]
  └─ Stop              → stop_hook.sh      [read-only: generates summary]

Layer 2: Git Hooks (core.hooksPath)
  └─ prepare-commit-msg  [modify: strips AI trailers from commit message]
  └─ commit-msg          [gate: blocks non-conventional commits]
  └─ pre-push            [gate: blocks pushes with AI trailers or oversized diffs]

Layer 3: Log Files (~/.claude/plugins/model-router/logs/)
  └─ cost_log.csv         [append-only: routing decisions]
  └─ file_changes.log     [append-only: file edit tracking]
  └─ session_commands.log  [append-only: bash command log]
  └─ git_operations.log    [append-only: git push log]
  └─ session_summary.log   [append-only: session summaries]
  └─ test_results.log      [append-only: test sign-off log]
  └─ sessions/             [read-write: per-session state files]

Layer 4: Configuration (~/.claude/plugins/model-router/config/)
  └─ patterns.json   [read: keyword routing weights]
  └─ budget.json     [read: spending limits]
```

---

## Role Matrix

| Role | Install / Uninstall | Modify Config | Modify Hooks | View Logs | Run Tests | Push Code | Bypass Hooks |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Maintainer** (repo owner) | Y | Y | Y | Y | Y | Y | Y (--no-verify) |
| **Contributor** (PR author) | Y (local) | Y (local) | N (PR required) | Y (local) | Y | Y (to fork) | Y (local only) |
| **User** (end user) | Y | Y (local config) | N | Y (own logs) | Y | N/A | Y (--no-verify) |
| **Claude Code** (AI agent) | N | N | N | Read-only | N | Via user approval | N |

---

## Segregation of Duties

### Principle: AI agent cannot self-approve changes to production

| Action | Who Initiates | Who Approves | Control |
|--------|:---:|:---:|---------|
| Code change | Claude Code | User (tool approval) | Claude Code requires user approval for Write/Edit |
| Commit | Claude Code | commit-msg hook | Conventional commit format enforced |
| Push | Claude Code | pre-push hook + user | AI trailers blocked; user must approve Bash tool |
| PR creation | Claude Code | User + reviewers | PreToolUse logs; GitHub review required |
| Config change | User | User | Direct file edit; no hook intercept needed |
| Hook modification | Maintainer | Maintainer | Changes require git commit + push through hooks |
| Budget change | User | User | budget.json is local-only config |

### Principle: Hooks cannot be silently disabled

| Bypass Method | Visibility | Audit Trail |
|---------------|------------|-------------|
| `--no-verify` on commit | Visible in terminal | No commit-msg cleanup applied; pre-push will still catch on push |
| `--no-verify` on push | Visible in terminal | Bypasses all pre-push gates; logged if done via Claude Code (PreToolUse) |
| Remove from settings.json | Visible in file diff | `git diff` shows removal; install.sh `--update` will flag missing hooks |
| Delete plugin directory | Visible (hooks fail silently) | Next Claude Code session shows no router output |

---

## Access Provisioning

### New Installation

1. Run `./install.sh --all` (installs all hooks + git hooks)
2. Verify with `VALIDATION.md` checklist
3. Run `./test_hook.sh` — confirm all tests pass
4. Review `docs/ACCESS.md` (this document) for role understanding

### Upgrade

1. Run `./install.sh --update --force` (preserves config, updates hooks)
2. Re-run `VALIDATION.md` checklist items 5-26
3. Run `./test_hook.sh` — confirm no regressions

### Offboarding / Removal

1. Run `./uninstall.sh` (removes hooks, preserves logs)
2. Verify: `grep model_router ~/.claude/settings.json` returns nothing
3. Logs retained at `~/.claude/plugins/model-router/logs/` for audit

---

## Permissions Summary

| Resource | Claude Code Agent | User | Hook Scripts |
|----------|:---:|:---:|:---:|
| Read source files | Y (with approval) | Y | N/A |
| Write source files | Y (with approval) | Y | N/A |
| Read logs | Y | Y | Y |
| Write logs | N | Y | Y (append-only) |
| Modify settings.json | N | Y | N |
| Modify patterns.json | N | Y | N |
| Execute git commit | Y (with approval) | Y | N/A |
| Execute git push | Y (with approval) | Y | N/A |
| Strip AI trailers | N/A | N/A | Y (automatic) |
| Block non-conventional commits | N/A | N/A | Y (automatic) |
| Block oversized PRs | N/A | N/A | Y (automatic) |
