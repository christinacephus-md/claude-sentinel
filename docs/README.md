# Model Router Plugin

Intelligent model routing for cost optimization in Claude Code.

## Overview

This plugin analyzes your prompts using a multi-factor scoring system and recommends the optimal Claude model based on task complexity:

- **Haiku** ($0.25/1M tokens) - Simple queries, single file reads, quick lookups
- **Sonnet** ($3.00/1M tokens) - Standard code generation, moderate refactoring
- **Opus** ($15.00/1M tokens) - Complex reasoning, architecture design, deep analysis

## How It Works

### Multi-Factor Analysis

The hook analyzes each prompt using 4 factors:

1. **Keyword Analysis** - Detects simple vs complex task indicators
2. **Tool Complexity** - Infers how many operations Claude will need
3. **File Context** - Single file vs multi-file operations
4. **Inference Depth** - Prompt length and multi-step indicators

### Scoring System

```
Score >= 6:  Recommend Opus (complex reasoning)
Score <= -2: Recommend Haiku (simple query)
Default:     Recommend Sonnet (balanced)
```

## Usage

### Automatic Recommendations

When you submit a prompt, the hook displays an analysis:

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

💰 Cost Comparison (per 1M tokens input):
   • Haiku:  $0.25  (fastest, cheapest)
   • Sonnet: $3.00  (balanced)
   • Opus:   $15.00 (most capable)
```

Claude will see this recommendation and can proactively suggest the model switch.

### Manual Model Switching

You can always override by typing:
```
/model haiku   # Switch to Haiku
/model sonnet  # Switch to Sonnet
/model opus    # Switch to Opus
```

## Configuration

### Customizing Keywords

Edit `~/.claude/plugins/model-router/config/patterns.json`:

```json
{
  "haiku_keywords": [
    "typo", "format", "rename", "simple",
    "read file", "show me", "what is"
  ],
  "opus_keywords": [
    "architect", "design system", "refactor",
    "debug across", "investigate", "analyze"
  ]
}
```

### Disabling the Plugin

Edit `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "model-router": false
  }
}
```

Or remove the `UserPromptSubmit` hook entirely.

## Testing

### Test 1: Simple Query (Should recommend Haiku)
```
> "Show me the contents of README.md"
```

### Test 2: Standard Code Change (Should recommend Sonnet)
```
> "Add error handling to the login function"
```

### Test 3: Complex Architecture (Should recommend Opus)
```
> "Design a microservices architecture with security guardrails"
```

## Cost Savings Strategy

**Default to Sonnet, downgrade to Haiku aggressively, reserve Opus for true complexity**

Example distribution (10M tokens/month):
- 40% simple queries → Haiku: 4M × $0.25 = $1.00
- 50% standard code → Sonnet: 5M × $3.00 = $15.00
- 10% complex reasoning → Opus: 1M × $15.00 = $15.00

**Total**: $31.00/month vs $30.00 all-Sonnet

Real savings come from:
1. Using Haiku for simple reads/queries (40%+ of prompts)
2. Avoiding Opus when Sonnet works (use Opus sparingly)

## Troubleshooting

### Hook not firing?

Check that Python 3 is available:
```bash
python3 --version
```

### Hook errors?

Check the hook output manually:
```bash
echo '{"prompt":"test prompt"}' | python3 ~/.claude/plugins/model-router/hooks/model_router.py
```

### Need to see hook execution?

Enable verbose logging in Claude Code or check terminal output.

## Files

```
~/.claude/plugins/model-router/
├── README.md                          (this file)
├── plugin.json                        (plugin metadata)
├── hooks/
│   ├── hooks.json                     (hook registration)
│   └── model_router.py                (main hook script)
└── config/
    └── patterns.json                  (keyword patterns)
```

## Version

1.0.0 - Initial release

## Author

Christina Cephus
