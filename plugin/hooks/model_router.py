#!/usr/bin/env python3
"""
Claude Model Router v2.0
Intelligent model routing + cost tracking for Claude Code

Analyzes prompts via multi-factor scoring and recommends optimal model.
Logs all routing decisions for cost visibility.
"""

import json
import os
import sys
import re
import csv
from datetime import datetime, date
from pathlib import Path

# --- Configuration ---

ROUTER_HOME = os.environ.get(
    'CLAUDE_ROUTER_HOME',
    os.path.expanduser('~/.claude/plugins/model-router')
)
CONFIG_FILE = os.path.join(ROUTER_HOME, 'config', 'patterns.json')
COST_LOG = os.path.join(ROUTER_HOME, 'logs', 'cost_log.csv')
BUDGET_FILE = os.path.join(ROUTER_HOME, 'config', 'budget.json')

# Model pricing (per 1M tokens, input)
PRICING = {
    'haiku':  {'input': 0.25,  'output': 1.25,  'cache_read': 0.025},
    'sonnet': {'input': 3.00,  'output': 15.00, 'cache_read': 0.30},
    'opus':   {'input': 15.00, 'output': 75.00, 'cache_read': 1.50},
}

DEFAULT_PATTERNS = {
    "haiku_keywords": [
        "typo", "format", "rename", "simple", "read file", "show me",
        "what is", "list", "find file", "quick", "view", "display",
        "check", "status", "version", "print", "cat", "head",
        "look at", "open", "see the", "tell me", "which"
    ],
    "opus_keywords": [
        "architect", "design system", "refactor entire", "debug across",
        "investigate", "analyze", "security", "performance", "optimize",
        "migration", "strategy", "tradeoff", "implement from scratch",
        "plan", "audit", "review entire", "redesign", "scale",
        "distributed", "microservices", "infrastructure", "terraform",
        "think hard", "deep dive", "comprehensive", "surveil",
        "synthesize", "research"
    ],
    "sonnet_default": True
}

# --- Pattern Loading ---

def load_patterns():
    """Load keyword patterns from config, with project overlay support."""
    try:
        with open(CONFIG_FILE, 'r') as f:
            base = json.load(f)
    except Exception:
        base = DEFAULT_PATTERNS

    # Check for project-specific overlay
    cwd = os.environ.get('CLAUDE_CWD', os.getcwd())
    project_config = os.path.join(cwd, '.claude', 'router-patterns.json')
    if os.path.exists(project_config):
        try:
            with open(project_config, 'r') as f:
                overlay = json.load(f)
            # Merge: project keywords extend base
            base['haiku_keywords'] = list(set(
                base.get('haiku_keywords', []) + overlay.get('haiku_keywords', [])
            ))
            base['opus_keywords'] = list(set(
                base.get('opus_keywords', []) + overlay.get('opus_keywords', [])
            ))
        except Exception:
            pass

    return base


# --- Analysis Factors ---

def analyze_keywords(prompt, patterns):
    """Factor 1: Keyword matching with weighted scoring."""
    prompt_lower = prompt.lower()

    simple_hits = [kw for kw in patterns['haiku_keywords'] if kw in prompt_lower]
    complex_hits = [kw for kw in patterns['opus_keywords'] if kw in prompt_lower]

    return {
        'simple_score': len(simple_hits),
        'complex_score': len(complex_hits),
        'simple_hits': simple_hits[:3],
        'complex_hits': complex_hits[:3],
    }


def analyze_tool_complexity(prompt):
    """Factor 2: Infer tool usage complexity from prompt content."""
    prompt_lower = prompt.lower()

    planning = any(w in prompt_lower for w in [
        'plan', 'design', 'architect', 'strategy', 'think hard',
        'research', 'comprehensive', 'deep dive'
    ])
    multi_file = any(w in prompt_lower for w in [
        'files', 'multiple', 'across', 'all', 'entire', 'whole',
        'codebase', 'repo', 'project'
    ])
    single_op = any(w in prompt_lower for w in [
        'this file', 'this function', 'this line', 'one thing'
    ])

    if planning:
        return 'high'
    elif multi_file and not single_op:
        return 'medium'
    else:
        return 'low'


def analyze_file_context(prompt):
    """Factor 3: File reference density."""
    file_paths = re.findall(r'[\w\-/\.]+\.[\w]{1,10}', prompt)
    dirs = re.findall(r'[\w\-]+/', prompt)

    total = len(file_paths) + len(dirs)
    if total > 5:
        return 'many_files'
    elif total > 1:
        return 'multiple_files'
    elif total == 1:
        return 'single_file'
    return 'no_files'


def analyze_inference_depth(prompt):
    """Factor 4: Reasoning depth heuristics."""
    length = len(prompt)
    sentences = prompt.count('.') + prompt.count('?') + prompt.count('!')
    steps = (prompt.lower().count('then ') + prompt.lower().count('and then') +
             prompt.lower().count('after that') + prompt.lower().count('next ') +
             prompt.lower().count('finally'))

    # Multi-part requests
    numbered = len(re.findall(r'\b\d+[\.\)]\s', prompt))
    bullets = prompt.count('- ')

    complexity = length + (sentences * 20) + (steps * 50) + (numbered * 40) + (bullets * 30)

    if complexity > 500 or steps > 2 or numbered > 2:
        return 'deep'
    elif complexity > 150 or sentences > 2:
        return 'moderate'
    return 'shallow'


def analyze_conversation_depth(prompt):
    """Factor 5: Is this a follow-up or a fresh complex request?"""
    prompt_lower = prompt.lower().strip()

    # Short follow-ups are cheap
    continuations = [
        'yes', 'no', 'ok', 'sure', 'do it', 'go ahead', 'approved',
        'looks good', 'lgtm', 'thanks', 'perfect', 'great',
        'the bottom', 'that one', 'this one', 'yep', 'nope',
        'continue', 'proceed', 'next'
    ]
    if any(prompt_lower.startswith(c) for c in continuations) and len(prompt) < 80:
        return 'continuation'

    # Question-only prompts
    if prompt.strip().endswith('?') and len(prompt) < 100:
        return 'question'

    return 'fresh'


# --- Scoring Engine ---

def score_and_recommend(analysis):
    """Combine all factors into a model recommendation."""
    score = 0

    # Factor 1: Keywords (strongest signal)
    score += analysis['keywords']['complex_score'] * 3
    score -= analysis['keywords']['simple_score'] * 2

    # Factor 2: Tool complexity
    tool_scores = {'high': 4, 'medium': 1, 'low': -1}
    score += tool_scores.get(analysis['tool_complexity'], 0)

    # Factor 3: File context
    file_scores = {'many_files': 3, 'multiple_files': 1, 'single_file': 0, 'no_files': 0}
    score += file_scores.get(analysis['file_context'], 0)

    # Factor 4: Inference depth
    depth_scores = {'deep': 4, 'moderate': 1, 'shallow': -1}
    score += depth_scores.get(analysis['inference_depth'], 0)

    # Factor 5: Conversation continuations are always cheap
    if analysis['conversation_depth'] == 'continuation':
        return 'haiku', 'Short follow-up, no complex reasoning needed', score
    if analysis['conversation_depth'] == 'question' and score < 3:
        return 'haiku', 'Simple question', score

    # Thresholds
    if score >= 7:
        return 'opus', 'Complex reasoning, multi-step planning', score
    elif score <= -2:
        return 'haiku', 'Simple query, single operation', score
    else:
        return 'sonnet', 'Balanced code generation', score


# --- Cost Tracking ---

def ensure_log_dir():
    """Create logs directory if it doesn't exist."""
    log_dir = os.path.dirname(COST_LOG)
    os.makedirs(log_dir, exist_ok=True)

    if not os.path.exists(COST_LOG):
        with open(COST_LOG, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                'timestamp', 'date', 'recommended_model', 'score',
                'reason', 'prompt_length', 'project_dir',
                'est_input_cost', 'est_output_cost'
            ])


def log_routing_decision(model, score, reason, prompt, project_dir):
    """Append routing decision to CSV log."""
    try:
        ensure_log_dir()
        now = datetime.now()

        # Estimate cost for a typical exchange at this model tier
        # Rough: ~2K input tokens, ~1K output tokens per interaction
        est_input = PRICING[model]['input'] * 2000 / 1_000_000
        est_output = PRICING[model]['output'] * 1000 / 1_000_000

        with open(COST_LOG, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                now.isoformat(),
                now.strftime('%Y-%m-%d'),
                model,
                score,
                reason,
                len(prompt),
                project_dir,
                f'{est_input:.6f}',
                f'{est_output:.6f}'
            ])
    except Exception:
        pass  # Never block the user


def get_daily_summary():
    """Get today's routing summary from the log."""
    try:
        today = date.today().isoformat()
        counts = {'haiku': 0, 'sonnet': 0, 'opus': 0}
        total_est = 0.0

        with open(COST_LOG, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row['date'] == today:
                    model = row['recommended_model']
                    counts[model] = counts.get(model, 0) + 1
                    total_est += float(row.get('est_input_cost', 0))
                    total_est += float(row.get('est_output_cost', 0))

        total_prompts = sum(counts.values())
        return counts, total_prompts, total_est
    except Exception:
        return {'haiku': 0, 'sonnet': 0, 'opus': 0}, 0, 0.0


# --- Budget Monitoring ---

def check_budget():
    """Check if spending is approaching budget limits."""
    try:
        with open(BUDGET_FILE, 'r') as f:
            budget = json.load(f)
    except Exception:
        return None  # No budget set

    daily_limit = budget.get('daily_limit_usd', None)
    weekly_limit = budget.get('weekly_limit_usd', None)

    if not daily_limit and not weekly_limit:
        return None

    counts, total_prompts, daily_est = get_daily_summary()

    alerts = []
    if daily_limit and daily_est > daily_limit * 0.8:
        pct = (daily_est / daily_limit) * 100
        alerts.append(f'Daily budget: ${daily_est:.2f} / ${daily_limit:.2f} ({pct:.0f}%)')

    return alerts if alerts else None


# --- Main ---

def main():
    try:
        input_data = json.load(sys.stdin)
        prompt = input_data.get('prompt', '')

        if not prompt or len(prompt.strip()) < 3:
            sys.exit(0)

        patterns = load_patterns()
        project_dir = os.environ.get('CLAUDE_CWD', os.getcwd())

        # Multi-factor analysis
        analysis = {
            'keywords': analyze_keywords(prompt, patterns),
            'tool_complexity': analyze_tool_complexity(prompt),
            'file_context': analyze_file_context(prompt),
            'inference_depth': analyze_inference_depth(prompt),
            'conversation_depth': analyze_conversation_depth(prompt),
        }

        model, reason, score = score_and_recommend(analysis)

        # Log the decision
        log_routing_decision(model, score, reason, prompt, project_dir)

        # Get daily stats
        counts, total_prompts, daily_est = get_daily_summary()

        # Check budget
        budget_alerts = check_budget()

        # Build output
        kw = analysis['keywords']
        output_lines = [
            '',
            '+---------------------------------------------------------+',
            '|  Model Router v2.0 - Cost Optimization                  |',
            '+---------------------------------------------------------+',
            '',
            f'  Analysis:',
            f'    Keywords: Simple={kw["simple_score"]} Complex={kw["complex_score"]}',
            f'    Tool Complexity: {analysis["tool_complexity"].upper()}',
            f'    File Context: {analysis["file_context"]}',
            f'    Inference Depth: {analysis["inference_depth"].upper()}',
            f'    Conversation: {analysis["conversation_depth"].upper()}',
            f'    Score: {score}',
            '',
            f'  Recommendation: /model {model}',
            f'    Reason: {reason}',
            '',
            f'  Cost (per 1M input tokens):',
            f'    Haiku:  $0.25   Sonnet: $3.00   Opus: $15.00',
        ]

        # Daily stats
        if total_prompts > 0:
            output_lines += [
                '',
                f'  Today: {total_prompts} prompts | '
                f'H:{counts["haiku"]} S:{counts["sonnet"]} O:{counts["opus"]} | '
                f'Est: ${daily_est:.2f}',
            ]

        # Budget alerts
        if budget_alerts:
            output_lines += ['']
            for alert in budget_alerts:
                output_lines.append(f'  BUDGET WARNING: {alert}')

        output_lines.append('')

        print('\n'.join(output_lines))
        sys.exit(0)

    except Exception:
        sys.exit(0)


if __name__ == '__main__':
    main()
