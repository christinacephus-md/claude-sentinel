# Model Router Quick Start

## What It Does

Analyzes your prompts and recommends the cheapest model that can handle the task.

## Model Costs (per 1M tokens input)

- **Haiku**: $0.25 - Simple reads, quick lookups
- **Sonnet**: $3.00 - Standard code generation (default)
- **Opus**: $15.00 - Complex reasoning, architecture

## How to Use

### 1. Start Claude Code Normally

```bash
claude
```

The hook runs automatically on every prompt submission.

### 2. Watch for Recommendations

You'll see analysis output like:

```
╔════════════════════════════════════════════════════════════╗
║  🤖 Model Router - Cost Optimization                      ║
╚════════════════════════════════════════════════════════════╝

📊 Analysis:
   • Keywords: Simple=2 Complex=0
   • Tool Complexity: LOW
   • File Context: single_file
   • Inference Depth: SHALLOW

💡 Recommendation: /model haiku
   Reason: Simple query, single operation
```

### 3. Claude Acts on Recommendations

Claude will see the recommendation and can proactively switch models if appropriate.

## Manual Override

You can always switch models manually:

```
/model haiku   # Cheapest - simple tasks
/model sonnet  # Balanced - default
/model opus    # Most capable - complex tasks
```

## Example Prompts

### Haiku Territory (Simple, $0.25/1M)
- "Show me the README"
- "List all Python files"
- "What's in config.json?"
- "Fix this typo in line 42"

### Sonnet Territory (Balanced, $3.00/1M)
- "Add error handling to the login function"
- "Write unit tests for the API"
- "Refactor this class to use composition"
- "Implement pagination for the user list"

### Opus Territory (Complex, $15.00/1M)
- "Design a microservices architecture"
- "Debug this race condition across multiple services"
- "Analyze security vulnerabilities in the codebase"
- "Plan a migration strategy from MongoDB to PostgreSQL"

## Customization

Edit keywords in: `~/.claude/plugins/model-router/config/patterns.json`

## Disable Temporarily

```json
// In ~/.claude/settings.json
{
  "enabledPlugins": {
    "model-router": false
  }
}
```

## Troubleshooting

### Hook not showing output?

1. Check Python 3 is installed: `python3 --version`
2. Test manually:
   ```bash
   echo '{"prompt":"test"}' | python3 ~/.claude/plugins/model-router/hooks/model_router.py
   ```

### Want to see raw analysis?

Test any prompt:
```bash
echo '{"prompt":"YOUR PROMPT HERE"}' | python3 ~/.claude/plugins/model-router/hooks/model_router.py
```

## Cost Savings Tip

**Default strategy**: Start with Sonnet, let hook recommend Haiku downgrades, manually use Opus only when absolutely necessary.

For 10M tokens/month:
- 40% Haiku queries: $1.00
- 50% Sonnet code: $15.00
- 10% Opus complex: $15.00
= **$31/month** vs $30 all-Sonnet (minimal savings, but optimizes performance too)

Real savings come when you can route 50%+ to Haiku.
