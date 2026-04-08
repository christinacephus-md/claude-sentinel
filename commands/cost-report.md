---
description: "[DEPRECATED] Use native /cost for per-model + cache breakdown. For historical trends, use /budget-check."
argument-hint: "[--week] [--month] [--all] [--project]"
---

> **Note:** As of Claude Code v2.1.89 (April 2026), the native `/cost` command now shows per-model split and cache-hit breakdown. This command is deprecated for basic cost visibility.
>
> **Use instead:**
> - `/cost` — native per-model + cache breakdown (built into Claude Code)
> - `/budget-check` — daily/weekly limits, historical trends, project breakdown (Sentinel)

For legacy compatibility, this still runs the full report:

```bash
python3 ~/.claude/plugins/sentinel/hooks/cost_report.py --week --project
```

Then summarize:
1. Total prompts and model distribution
2. Estimated cost vs all-Opus baseline
3. Savings achieved
4. Any projects burning disproportionately on Opus
5. Recommendations for further optimization
