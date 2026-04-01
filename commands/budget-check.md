---
name: budget-check
description: Check current spending against daily and weekly budget limits.
---

Run the budget check and show the current daily/weekly status:

```bash
python3 -c "
import json, csv, os
from datetime import date, timedelta
from collections import defaultdict

home = os.path.expanduser('~/.claude/plugins/sentinel')
log = os.path.join(home, 'logs', 'cost_log.csv')
budget_file = os.path.join(home, 'config', 'budget.json')

try:
    with open(budget_file) as f:
        budget = json.load(f)
except:
    print('No budget configured.')
    exit()

today = date.today().isoformat()
week_start = (date.today() - timedelta(days=date.today().weekday())).isoformat()
daily_cost = 0.0
weekly_cost = 0.0

try:
    with open(log) as f:
        for row in csv.DictReader(f):
            cost = float(row.get('est_input_cost', 0)) + float(row.get('est_output_cost', 0))
            if row['date'] == today:
                daily_cost += cost
            if row['date'] >= week_start:
                weekly_cost += cost
except FileNotFoundError:
    pass

dl = budget.get('daily_limit_usd')
wl = budget.get('weekly_limit_usd')
print(f'Daily:  \${daily_cost:.2f} / \${dl:.2f} ({daily_cost/dl*100:.0f}%)' if dl else 'Daily: no limit set')
print(f'Weekly: \${weekly_cost:.2f} / \${wl:.2f} ({weekly_cost/wl*100:.0f}%)' if wl else 'Weekly: no limit set')
"
```

Then provide context on the spending rate and whether the user should consider switching models more aggressively.
