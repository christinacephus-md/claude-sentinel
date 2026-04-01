#!/usr/bin/env python3
"""
Cost Report Generator for Claude Sentinel v3.1
Reads the routing log and produces daily/weekly/monthly cost summaries.

v3.1: Token-weighted cost estimates — uses actual prompt length to
approximate token counts instead of flat per-prompt rates.

Usage:
  python3 cost_report.py              # Today's summary
  python3 cost_report.py --week       # This week
  python3 cost_report.py --month      # This month
  python3 cost_report.py --all        # All time
  python3 cost_report.py --project    # Breakdown by project
"""

import csv
import os
import sys
from datetime import datetime, date, timedelta
from collections import defaultdict

ROUTER_HOME = os.environ.get(
    'CLAUDE_ROUTER_HOME',
    os.path.expanduser('~/.claude/plugins/sentinel')
)
COST_LOG = os.path.join(ROUTER_HOME, 'logs', 'cost_log.csv')

# Must match sentinel.py pricing
PRICING = {
    'haiku':  {'input': 0.25,  'output': 1.25},
    'sonnet': {'input': 3.00,  'output': 15.00},
    'opus':   {'input': 15.00, 'output': 75.00},
}

PRICING_DISPLAY = {
    'haiku':  '$0.25/1M',
    'sonnet': '$3.00/1M',
    'opus':   '$15.00/1M',
}

# Output token estimates by model tier (matches sentinel.py)
OUTPUT_TOKENS_BY_TIER = {
    'haiku':  400,
    'sonnet': 1200,
    'opus':   2500,
}


def estimate_tokens_from_row(row):
    """Extract or recompute token estimates from a log row.

    v3.1 rows include est_input_tokens / est_output_tokens columns.
    Older v3.0 rows only have prompt_length — recompute on the fly.
    """
    est_in = row.get('est_input_tokens', '')
    est_out = row.get('est_output_tokens', '')

    if est_in and est_out:
        return int(est_in), int(est_out)

    # Fallback: recompute from prompt_length (v3.0 rows)
    prompt_len = int(row.get('prompt_length', 0))
    model = row.get('recommended_model', 'sonnet')
    in_tokens = max(500, int(prompt_len / 4) + 2000)
    out_tokens = OUTPUT_TOKENS_BY_TIER.get(model, 1200)
    return in_tokens, out_tokens


def load_log(start_date=None):
    """Load log entries, optionally filtered by start date."""
    entries = []
    try:
        with open(COST_LOG, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                row_date = row.get('date', '')
                if start_date and row_date < start_date:
                    continue
                entries.append(row)
    except FileNotFoundError:
        pass
    return entries


def summarize(entries):
    """Produce a summary with token-weighted cost estimates."""
    counts = defaultdict(int)
    est_cost = 0.0
    opus_baseline = 0.0
    by_project = defaultdict(lambda: defaultdict(int))
    by_day = defaultdict(lambda: defaultdict(int))

    for e in entries:
        model = e.get('recommended_model', 'sonnet')
        counts[model] += 1

        # Get token estimates for this row
        in_tokens, out_tokens = estimate_tokens_from_row(e)

        # Actual cost at the routed model
        actual_in = PRICING[model]['input'] * in_tokens / 1_000_000
        actual_out = PRICING[model]['output'] * out_tokens / 1_000_000
        est_cost += actual_in + actual_out

        # Baseline: what it would cost at Opus with the SAME token counts
        baseline_in = PRICING['opus']['input'] * in_tokens / 1_000_000
        baseline_out = PRICING['opus']['output'] * out_tokens / 1_000_000
        opus_baseline += baseline_in + baseline_out

        project = e.get('project_dir', 'unknown')
        project_name = os.path.basename(project) if project else 'unknown'
        by_project[project_name][model] += 1

        day = e.get('date', 'unknown')
        by_day[day][model] += 1

    total = sum(counts.values())
    savings = opus_baseline - est_cost if opus_baseline > 0 else 0
    savings_pct = (savings / opus_baseline * 100) if opus_baseline > 0 else 0

    return {
        'counts': dict(counts),
        'total': total,
        'est_cost': est_cost,
        'opus_baseline': opus_baseline,
        'savings': savings,
        'savings_pct': savings_pct,
        'by_project': dict(by_project),
        'by_day': dict(by_day),
    }


def print_report(title, entries, show_projects=False):
    """Print a formatted cost report."""
    if not entries:
        print(f'\n  No routing data found for: {title}')
        print(f'  Start using the model router to see cost data here.\n')
        return

    s = summarize(entries)

    print()
    print('+---------------------------------------------------------+')
    print(f'|  Cost Report: {title:<42} |')
    print('+---------------------------------------------------------+')
    print()
    print(f'  Total Prompts: {s["total"]}')
    print()
    print(f'  Model Distribution:')
    for model in ['haiku', 'sonnet', 'opus']:
        count = s['counts'].get(model, 0)
        pct = (count / s['total'] * 100) if s['total'] > 0 else 0
        bar = '#' * int(pct / 2)
        print(f'    {model:>6}: {count:>4} ({pct:5.1f}%)  {bar}')
    print()
    print(f'  Estimated Cost:     ${s["est_cost"]:.2f}')
    print(f'  All-Opus Baseline:  ${s["opus_baseline"]:.2f}')
    if s['savings'] >= 0:
        print(f'  Estimated Savings:  ${s["savings"]:.2f} ({s["savings_pct"]:.0f}%)')
    else:
        print(f'  Over Baseline By:   ${abs(s["savings"]):.2f} ({abs(s["savings_pct"]):.0f}%)')

    if show_projects and s['by_project']:
        print()
        print(f'  By Project:')
        for project, models in sorted(s['by_project'].items()):
            total_p = sum(models.values())
            breakdown = ', '.join(f'{m[0].upper()}:{c}' for m, c in sorted(models.items()))
            print(f'    {project:>30}: {total_p:>3} prompts ({breakdown})')

    if len(s['by_day']) > 1:
        print()
        print(f'  By Day:')
        for day, models in sorted(s['by_day'].items())[-7:]:  # Last 7 days
            total_d = sum(models.values())
            breakdown = ', '.join(f'{m[0].upper()}:{c}' for m, c in sorted(models.items()))
            print(f'    {day}: {total_d:>3} prompts ({breakdown})')

    print()
    print(f'  Note: Estimates use prompt length / 4 for input tokens + 2K')
    print(f'  context overhead.  For exact figures, check console.anthropic.com')
    print()


def main():
    args = sys.argv[1:]
    show_projects = '--project' in args or '-p' in args

    today = date.today()

    if '--all' in args or '-a' in args:
        entries = load_log()
        print_report('All Time', entries, show_projects=True)
    elif '--month' in args or '-m' in args:
        start = (today.replace(day=1)).isoformat()
        entries = load_log(start)
        print_report(f'Month of {today.strftime("%B %Y")}', entries, show_projects)
    elif '--week' in args or '-w' in args:
        start = (today - timedelta(days=today.weekday())).isoformat()
        entries = load_log(start)
        print_report(f'Week of {start}', entries, show_projects)
    else:
        entries = load_log(today.isoformat())
        print_report(f'Today ({today.isoformat()})', entries, show_projects)


if __name__ == '__main__':
    main()
