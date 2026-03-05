---
name: cost-report
description: Show model routing cost report for today, this week, or this month.
---

Run the cost report script and display the results. Execute this command:

```bash
python3 ~/.claude/plugins/model-router/hooks/cost_report.py --week --project
```

Then summarize the key findings:
1. Total prompts and model distribution
2. Estimated cost vs all-Opus baseline
3. Savings achieved
4. Any projects burning disproportionately on Opus
5. Recommendations for further optimization
