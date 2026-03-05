# Claude Model Router v2.0

Intelligent model routing and cost tracking for Claude Code CLI.

Analyzes every prompt you submit and recommends the optimal Claude model (Haiku/Sonnet/Opus) based on task complexity. Logs all routing decisions so you can see exactly where your tokens are going.

## Why

Running Opus for everything costs 60x more than Haiku. Most prompts ("yes", "show me the file", "looks good") don't need Opus. This hook catches those and tells you to downshift, saving 30-50% on API billing.

| Model | Input/1M | Output/1M | Best For |
|---|---|---|---|
| Haiku | $0.25 | $1.25 | Reads, lookups, follow-ups |
| Sonnet | $3.00 | $15.00 | Standard code gen, moderate edits |
| Opus | $15.00 | $75.00 | Architecture, security, deep reasoning |

## Install

```bash
git clone https://github.com/christinacephus-md/claude-model-router.git
cd claude-model-router
chmod +x install.sh
./install.sh
```

This copies the hook to `~/.claude/plugins/model-router/` and prints instructions for wiring it into your `~/.claude/settings.json`.

To auto-merge into an existing settings file:

```bash
./install.sh --force
```

## What You Get

### 1. Prompt Analysis Hook

Every prompt gets scored across 5 factors:
- **Keywords** - simple vs complex task indicators
- **Tool complexity** - single file vs multi-file vs planning
- **File context** - how many files referenced
- **Inference depth** - prompt length, multi-step indicators
- **Conversation depth** - follow-ups and continuations auto-route to Haiku

Output before each response:
```
+---------------------------------------------------------+
|  Model Router v2.0 - Cost Optimization                  |
+---------------------------------------------------------+

  Analysis:
    Keywords: Simple=2 Complex=0
    Tool Complexity: LOW
    File Context: single_file
    Inference Depth: SHALLOW
    Conversation: FRESH
    Score: -5

  Recommendation: /model haiku
    Reason: Simple query, single operation

  Cost (per 1M input tokens):
    Haiku:  $0.25   Sonnet: $3.00   Opus: $15.00

  Today: 23 prompts | H:14 S:7 O:2 | Est: $1.84
```

### 2. Cost Tracking

Every routing decision is logged to CSV at `~/.claude/plugins/model-router/logs/cost_log.csv`. Run reports:

```bash
# Today
python3 ~/.claude/plugins/model-router/hooks/cost_report.py

# This week, by project
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --week --project

# This month
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --month

# All time
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --all
```

### 3. Budget Alerts

Set daily/weekly limits in `~/.claude/plugins/model-router/config/budget.json`:

```json
{
  "daily_limit_usd": 10.00,
  "weekly_limit_usd": 50.00
}
```

When you hit 80% of a limit, the hook warns you inline.

### 4. Router Advisor Agent

A subagent you can invoke for a second opinion on model selection:

```
# In Claude Code, if you've symlinked the agent:
@router-advisor Should I use Opus for this refactoring task?
```

### 5. Slash Commands

- `/cost-report` - weekly cost breakdown by project
- `/budget-check` - current spend vs budget limits

To use agents and commands in a project, symlink them:

```bash
mkdir -p .claude/agents .claude/commands
ln -s ~/.claude/plugins/model-router/agents/router-advisor.md .claude/agents/
ln -s ~/.claude/plugins/model-router/commands/cost-report.md .claude/commands/
ln -s ~/.claude/plugins/model-router/commands/budget-check.md .claude/commands/
```

## Project-Specific Patterns

Drop a `.claude/router-patterns.json` in any project to extend the base keywords:

```json
{
  "haiku_keywords": ["lookup patient", "check appointment"],
  "opus_keywords": ["hipaa", "phi audit", "compliance review"]
}
```

These merge with the global patterns -- project keywords extend, not replace.

## Customization

### Adjust Thresholds

In `model_router.py`, the scoring thresholds:
```python
score >= 7   -> Opus
score <= -2  -> Haiku
else         -> Sonnet
```

Lower the Opus threshold to be more aggressive about routing to Opus. Raise the Haiku threshold to route more to Haiku.

### Edit Keywords

`~/.claude/plugins/model-router/config/patterns.json` -- add your team's domain-specific terms.

### Budget Limits

`~/.claude/plugins/model-router/config/budget.json` -- set to `null` to disable.

## Settings.json Hook Format

Add this to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/plugins/model-router/hooks/model_router.py"
          }
        ]
      }
    ]
  }
}
```

## Toggling

When you want raw speed without routing recommendations (e.g., `/fast` mode), the hook still runs but doesn't block anything -- it just prints a recommendation. You can ignore it.

To fully disable, remove the hook from `settings.json` or run `./uninstall.sh`.

## Testing

```bash
chmod +x test_hook.sh
./test_hook.sh
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

Preserves your cost logs by default.

## Structure

```
claude-model-router/
├── README.md
├── install.sh                    # One-command install
├── uninstall.sh                  # Clean removal
├── test_hook.sh                  # Test suite
├── plugin/
│   ├── plugin.json               # Package metadata
│   ├── hooks/
│   │   ├── hooks.json            # Hook registration
│   │   ├── model_router.py       # Main routing engine
│   │   └── cost_report.py        # Cost report generator
│   └── config/
│       ├── patterns.json         # Keyword patterns (with healthcare)
│       └── budget.json           # Budget limits
├── agents/
│   └── router-advisor.md         # Model selection subagent
├── commands/
│   ├── cost-report.md            # /cost-report slash command
│   └── budget-check.md           # /budget-check slash command
├── examples/
│   ├── custom_patterns.json
│   └── healthcare_patterns.json
├── docs/
│   ├── README.md
│   └── QUICKSTART.md
├── LICENSE
├── CONTRIBUTING.md
└── PUBLISH.md
```

## Requirements

- Python 3.8+
- Claude Code CLI
- macOS, Linux, or WSL

## Version History

- **v2.0.0** - Cost tracking, budget alerts, conversation depth analysis, agents, commands, project-specific patterns
- **v1.0.0** - Initial release with multi-factor keyword routing

## Author

Christina Cephus

## License

MIT
