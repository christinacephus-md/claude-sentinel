#!/usr/bin/env python3
"""
Claude Sentinel v6.0
Developer discipline layer + SOC 2 compliance for Claude Code

v6.0 — SOC 2 compliance layer:
- PHI pattern scanner: SSN, DOB, MRN, phone, email detection in prompts and commands
- Prompt audit log: SHA-256 hash-based audit trail (never logs content)
- Data classification gate: secret/credential detection in commands and file writes
- All features toggleable via config/sentinel_config.json

v5.0 — developer discipline:
- Debug keyword tier, code review routing, smart compaction advisor
- Subagent cost awareness, test coverage nudge, PR size gating

Carried from v4.0:
- Tiered keyword weights, word boundary matching, downgrade signals
- Stricter opus threshold (10), wider haiku band (<= -1)
- Short prompt auto-downgrade, savings tracking vs always-opus baseline
"""

import json
import os
import sys
import re
import csv
import hashlib
import tempfile
from datetime import datetime, date
from pathlib import Path

# --- Configuration ---

ROUTER_HOME = os.environ.get(
    'CLAUDE_ROUTER_HOME',
    os.path.expanduser('~/.claude/plugins/sentinel')
)
CONFIG_FILE = os.path.join(ROUTER_HOME, 'config', 'patterns.json')
SENTINEL_CONFIG_FILE = os.path.join(ROUTER_HOME, 'config', 'sentinel_config.json')
COST_LOG = os.path.join(ROUTER_HOME, 'logs', 'cost_log.csv')
BUDGET_FILE = os.path.join(ROUTER_HOME, 'config', 'budget.json')
SESSION_DIR = os.path.join(ROUTER_HOME, 'logs', 'sessions')

# v6.0: SOC 2 compliance logs
PHI_LOG = os.path.join(ROUTER_HOME, 'logs', 'phi_detections.log')
AUDIT_LOG = os.path.join(ROUTER_HOME, 'logs', 'prompt_audit.log')

# v7.0: PHI/PII detection — all 18 HIPAA Safe Harbor identifiers
PHI_PATTERNS = {
    # 1. Names (patient context)
    'patient_medical': r'\b(?:patient|pt)\s+[A-Z][a-z]+\s+(?:diagnosis|prescribed|admitted|discharged|treatment)\b',
    # 2. Geographic data (ZIP codes more specific than 3-digit)
    'zip_code': r'\b\d{5}(?:-\d{4})?\b',
    # 3. Dates (DOB, admission, discharge, death)
    'dob': r'\b(?:DOB|date of birth|born on|admitted|discharged|died)\s*[:\-]?\s*\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b',
    # 4. Phone numbers
    'phone': r'\b(?:\+1[\s\-]?)?\(?\d{3}\)?[\s\-]\d{3}[\s\-]\d{4}\b',
    # 5. Fax numbers
    'fax': r'\b(?:fax|facsimile)\s*[:\-]?\s*(?:\+1[\s\-]?)?\(?\d{3}\)?[\s\-]?\d{3}[\s\-]?\d{4}\b',
    # 6. Email addresses
    'email': r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',
    # 7. SSN (exclude known non-SSN ranges: 000, 666, 900-999)
    'ssn': r'\b(?!000|666|9\d{2})\d{3}[- ]?\d{2}[- ]?\d{4}\b',
    # 8. MRN / Medical record numbers
    'mrn': r'\b(?:MRN|medical record|chart)\s*[:#]?\s*\d{6,10}\b',
    # 9. Health plan beneficiary numbers
    'health_plan': r'\b(?:beneficiary|member|policy|insurance)\s*(?:id|#|number)\s*[:\-]?\s*[A-Z0-9]{6,15}\b',
    # 10. Account numbers
    'account_number': r'\b(?:account|acct)\s*[:#]?\s*\d{8,12}\b',
    # 11. Certificate/license numbers (DEA, NPI, medical license)
    'license': r'\b(?:DEA|NPI|license)\s*[:#]?\s*[A-Z0-9]{7,15}\b',
    # 12. Vehicle identifiers (VIN)
    'vin': r'\b[A-HJ-NPR-Z0-9]{17}\b',
    # 13. Device identifiers (UDI)
    'device_id': r'\b(?:UDI|device|serial)\s*[:#]?\s*[A-Z0-9\-]{10,20}\b',
    # 14. Web URLs (patient portal links)
    'patient_url': r'\b(?:patient|portal|mychart)\S*https?://\S+\b',
    # 15. IP addresses
    'ip_address': r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b',
    # 16. Biometric identifiers (keywords)
    'biometric': r'\b(?:fingerprint|voiceprint|retina|iris|facial recognition|biometric)\s+(?:data|scan|id|record)\b',
    # 17. Full-face photo filenames
    'photo': r'\b(?:patient|face|headshot|photo)_?\w*\.(?:jpg|jpeg|png|gif|bmp|tiff)\b',
    # 18. Any unique identifying code
    'patient_id': r'\b(?:patient_id|subscriber_id|member_id)\s*[=:]\s*["\']?[A-Za-z0-9\-]{6,}\b',
}

# Model pricing (per 1M tokens)
PRICING = {
    'haiku':  {'input': 0.25,  'output': 1.25,  'cache_read': 0.025},
    'sonnet': {'input': 3.00,  'output': 15.00, 'cache_read': 0.30},
    'opus':   {'input': 15.00, 'output': 75.00, 'cache_read': 1.50},
}

# --- Tiered Keyword Weights ---
# Weight reflects how strongly each keyword signals that tier.
# Higher weight = stronger signal. Word boundary matching is enforced.

HAIKU_KEYWORDS = {
    # Simple lookups / displays
    'typo': 2, 'format': 2, 'rename': 2, 'simple': 3, 'read file': 2,
    'show me': 2, 'what is': 2, 'list': 1, 'find file': 2, 'quick': 2,
    'view': 1, 'display': 2, 'check': 1, 'status': 2, 'version': 2,
    'print': 1, 'look at': 2, 'see the': 1, 'tell me': 1, 'which': 1,
    # Additional haiku signals
    'how many': 2, 'where is': 2, 'count': 1, 'summarize': 1,
    'explain this': 2, 'what does': 2, 'help me understand': 2,
    'show': 1, 'whats': 2, "what's": 2, 'describe': 1,
}

OPUS_KEYWORDS = {
    # Tier 1: Strong opus signals (weight 4) - truly need deep reasoning
    'architect': 4, 'design system': 4, 'refactor entire': 4,
    'implement from scratch': 4, 'think hard': 4, 'deep dive': 4,
    'redesign': 4, 'from the ground up': 4,
    # Tier 2: Moderate opus signals (weight 2) - often need opus
    'debug across': 2, 'review entire': 2, 'migration': 2,
    'tradeoff': 2, 'distributed': 2, 'microservices': 2,
    'infrastructure': 2, 'terraform': 2, 'comprehensive': 2,
    'synthesize': 2,
    # Tier 3: Weak opus signals (weight 1) - context-dependent
    # These were causing false positives in v3.1
    'investigate': 1, 'analyze': 1, 'security': 1, 'performance': 1,
    'optimize': 1, 'strategy': 1, 'plan': 1, 'audit': 1, 'scale': 1,
    'research': 1,
    # Domain-specific (from project overlay)
    'hipaa': 2, 'compliance': 2, 'encryption': 2, 'fhir': 2,
    'hl7': 2, 'patient data security': 3, 'data governance': 2,
    'privacy': 1, 'gdpr': 2, 'access control': 1, 'audit logging': 1,
}

# Downgrade signals — push AWAY from opus toward cheaper models
DOWNGRADE_KEYWORDS = {
    'just': 3, 'quickly': 3, 'briefly': 3, 'simply': 2, 'only': 1,
    'small': 2, 'minor': 2, 'tiny': 2, 'little': 1, 'tweak': 3,
    'fix this': 2, 'change this': 2, 'update this': 2, 'add this': 2,
    'real quick': 4, 'one thing': 3, 'single': 1, 'straightforward': 3,
    'easy': 2, 'basic': 2, 'trivial': 3,
}

# v5.0: Debug keywords — these should route to Sonnet minimum
# Debugging rarely works well on Haiku; needs reasoning but not full Opus
DEBUG_KEYWORDS = {
    'error': 1, 'bug': 2, 'broken': 2, 'failing': 2, 'failed': 2,
    'stack trace': 3, 'traceback': 3, 'exception': 2, 'crash': 2,
    'not working': 3, 'doesnt work': 3, "doesn't work": 3,
    'undefined': 1, 'null': 1, 'segfault': 3, 'panic': 2,
    'debug': 2, 'breakpoint': 1, 'regression': 3, 'flaky': 2,
    'intermittent': 2, 'race condition': 3, 'deadlock': 3,
    'memory leak': 3, 'timeout': 1, 'hang': 2, 'infinite loop': 3,
    'wrong output': 2, 'unexpected': 1, 'off by one': 2,
}

# v5.0: Code review keywords — review tasks need structured analysis
REVIEW_KEYWORDS = {
    'review': 2, 'code review': 3, 'review this pr': 3,
    'review this diff': 3, 'look over': 1, 'check my code': 2,
    'feedback on': 1, 'critique': 2, 'pr review': 3,
    'pull request': 2, 'merge request': 2, 'diff': 1,
    'approve': 1, 'nits': 1, 'suggestions': 1,
}


# --- Pattern Loading ---

def load_patterns():
    """Load keyword patterns from config, with project overlay support."""
    try:
        with open(CONFIG_FILE, 'r') as f:
            base = json.load(f)
    except Exception:
        base = {}

    # Check for project-specific overlay
    cwd = os.environ.get('CLAUDE_CWD', os.getcwd())
    project_config = os.path.join(cwd, '.claude', 'router-patterns.json')
    if os.path.exists(project_config):
        try:
            with open(project_config, 'r') as f:
                overlay = json.load(f)
            # Merge overlay keywords into weighted dicts
            for kw in overlay.get('haiku_keywords', []):
                if kw not in HAIKU_KEYWORDS:
                    HAIKU_KEYWORDS[kw] = 2
            for kw in overlay.get('opus_keywords', []):
                if kw not in OPUS_KEYWORDS:
                    OPUS_KEYWORDS[kw] = 2
        except Exception:
            pass

    return base


# --- Analysis Factors ---

def match_keyword_weighted(prompt_lower, keyword_dict):
    """Match keywords with word boundary enforcement and return weighted score."""
    total_score = 0
    hits = []

    for keyword, weight in keyword_dict.items():
        # Multi-word phrases: use simple containment
        # Single words: use word boundary regex to prevent partial matches
        if ' ' in keyword:
            if keyword in prompt_lower:
                total_score += weight
                hits.append((keyword, weight))
        else:
            # \b prevents "plan" matching "explain", "plant", etc.
            if re.search(r'\b' + re.escape(keyword) + r'\b', prompt_lower):
                total_score += weight
                hits.append((keyword, weight))

    return total_score, hits


def analyze_keywords(prompt, patterns):
    """Factor 1: Weighted keyword matching with word boundaries."""
    prompt_lower = prompt.lower()

    simple_score, simple_hits = match_keyword_weighted(prompt_lower, HAIKU_KEYWORDS)
    complex_score, complex_hits = match_keyword_weighted(prompt_lower, OPUS_KEYWORDS)
    downgrade_score, downgrade_hits = match_keyword_weighted(prompt_lower, DOWNGRADE_KEYWORDS)
    debug_score, debug_hits = match_keyword_weighted(prompt_lower, DEBUG_KEYWORDS)
    review_score, review_hits = match_keyword_weighted(prompt_lower, REVIEW_KEYWORDS)

    return {
        'simple_score': simple_score,
        'complex_score': complex_score,
        'downgrade_score': downgrade_score,
        'debug_score': debug_score,
        'review_score': review_score,
        'simple_hits': [h[0] for h in simple_hits[:3]],
        'complex_hits': [h[0] for h in complex_hits[:3]],
        'downgrade_hits': [h[0] for h in downgrade_hits[:3]],
        'debug_hits': [h[0] for h in debug_hits[:3]],
        'review_hits': [h[0] for h in review_hits[:3]],
    }


def analyze_tool_complexity(prompt):
    """Factor 2: Infer tool usage complexity from prompt content."""
    prompt_lower = prompt.lower()

    # Only strong planning signals trigger high (removed weak words like "plan")
    planning = any(w in prompt_lower for w in [
        'design system', 'architect', 'think hard',
        'comprehensive plan', 'deep dive into',
        'implement from scratch', 'build out',
    ])
    multi_file = any(w in prompt_lower for w in [
        'multiple files', 'across the', 'entire codebase',
        'whole project', 'all files', 'every file',
    ])
    single_op = any(w in prompt_lower for w in [
        'this file', 'this function', 'this line', 'this method',
        'this component', 'this class', 'one thing', 'this test',
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

    if complexity > 600 or steps > 3 or numbered > 3:
        return 'deep'
    elif complexity > 200 or sentences > 3:
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
        'continue', 'proceed', 'next', 'sounds good', 'correct',
        'right', 'exactly', 'yeah', 'ya', 'please', 'go for it',
        'ship it', 'merge it', 'push it', 'commit', 'done',
        'nice', 'cool', 'awesome', 'ok do it', 'confirmed',
    ]
    if any(prompt_lower.startswith(c) for c in continuations) and len(prompt) < 100:
        return 'continuation'

    # Question-only prompts under 120 chars
    if prompt.strip().endswith('?') and len(prompt) < 120:
        return 'question'

    return 'fresh'


# --- Scoring Engine ---

def score_and_recommend(analysis):
    """Combine all factors into a model recommendation.

    v5.0 changes:
    - Debug floor: debugging prompts can't go below Sonnet
    - Review routing: code review prompts get Sonnet minimum for small, Opus for large
    - Smarter compaction signal in session tracking

    Carried from v4.0:
    - Opus threshold: 10
    - Haiku band: <= -1
    - Downgrade signals reduce score
    - Short prompt cap prevents opus for brief requests
    """
    score = 0
    kw = analysis['keywords']

    # Factor 1: Keywords (strongest signal, weighted)
    score += kw['complex_score']
    score -= kw['simple_score']
    score -= kw['downgrade_score']

    # v5.0: Debug keywords add moderate complexity (pushes toward Sonnet)
    score += kw['debug_score']

    # v5.0: Review keywords add moderate complexity
    score += kw['review_score']

    # Factor 2: Tool complexity
    tool_scores = {'high': 3, 'medium': 1, 'low': -1}
    score += tool_scores.get(analysis['tool_complexity'], 0)

    # Factor 3: File context
    file_scores = {'many_files': 2, 'multiple_files': 1, 'single_file': 0, 'no_files': 0}
    score += file_scores.get(analysis['file_context'], 0)

    # Factor 4: Inference depth
    depth_scores = {'deep': 3, 'moderate': 1, 'shallow': -1}
    score += depth_scores.get(analysis['inference_depth'], 0)

    # Factor 5: Conversation continuations are always cheap
    if analysis['conversation_depth'] == 'continuation':
        return 'haiku', 'Short follow-up', score
    if analysis['conversation_depth'] == 'question' and score < 5:
        return 'haiku', 'Simple question', score

    # Short prompt cap: prompts under 60 chars can't trigger opus
    prompt_len = analysis.get('prompt_length', 100)
    if prompt_len < 60 and score >= 10:
        score = 8  # Cap at sonnet range
        return 'sonnet', 'Short prompt capped to Sonnet', score

    # v5.0: Debug floor — debugging prompts never go to Haiku
    if kw['debug_score'] >= 3 and score <= -1:
        score = 1  # Force into Sonnet range
        return 'sonnet', 'Debug task (Sonnet floor)', score

    # v5.0: Review routing — code reviews need at least Sonnet
    if kw['review_score'] >= 3 and score <= -1:
        score = 1
        return 'sonnet', 'Code review (Sonnet floor)', score

    # v5.0: Large review + many files → Opus
    if kw['review_score'] >= 3 and analysis['file_context'] in ('many_files',) and analysis['inference_depth'] == 'deep':
        if score < 10:
            score = 10
        return 'opus', 'Large code review — deep multi-file analysis', score

    # Thresholds
    if score >= 10:
        return 'opus', 'Complex reasoning, multi-step planning', score
    elif score <= -1:
        return 'haiku', 'Simple task', score
    else:
        return 'sonnet', 'Balanced code generation', score


# --- Cost Tracking ---

def estimate_tokens(prompt_length, model):
    """Estimate input/output tokens from prompt character count."""
    est_input = max(500, int(prompt_length / 4) + 2000)

    output_by_tier = {
        'haiku':  400,
        'sonnet': 1200,
        'opus':   2500,
    }
    est_output = output_by_tier.get(model, 1200)

    return est_input, est_output


def calculate_savings(model, est_in_tokens, est_out_tokens):
    """Calculate savings vs always using opus."""
    opus_cost = (PRICING['opus']['input'] * est_in_tokens / 1_000_000 +
                 PRICING['opus']['output'] * est_out_tokens / 1_000_000)
    actual_cost = (PRICING[model]['input'] * est_in_tokens / 1_000_000 +
                   PRICING[model]['output'] * est_out_tokens / 1_000_000)
    return opus_cost - actual_cost


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
                'est_input_cost', 'est_output_cost',
                'est_input_tokens', 'est_output_tokens',
                'est_savings'
            ])


def log_routing_decision(model, score, reason, prompt, project_dir):
    """Append routing decision to CSV log with savings tracking."""
    try:
        ensure_log_dir()
        now = datetime.now()
        prompt_len = len(prompt)

        est_in_tokens, est_out_tokens = estimate_tokens(prompt_len, model)
        est_input_cost = PRICING[model]['input'] * est_in_tokens / 1_000_000
        est_output_cost = PRICING[model]['output'] * est_out_tokens / 1_000_000
        savings = calculate_savings(model, est_in_tokens, est_out_tokens)

        with open(COST_LOG, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                now.isoformat(),
                now.strftime('%Y-%m-%d'),
                model,
                score,
                reason,
                prompt_len,
                project_dir,
                f'{est_input_cost:.6f}',
                f'{est_output_cost:.6f}',
                est_in_tokens,
                est_out_tokens,
                f'{savings:.6f}',
            ])
    except Exception:
        pass


def get_daily_summary():
    """Get today's routing summary from the log."""
    try:
        today = date.today().isoformat()
        counts = {'haiku': 0, 'sonnet': 0, 'opus': 0}
        total_est = 0.0
        total_savings = 0.0

        with open(COST_LOG, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row['date'] == today:
                    model = row['recommended_model']
                    counts[model] = counts.get(model, 0) + 1
                    total_est += float(row.get('est_input_cost', 0))
                    total_est += float(row.get('est_output_cost', 0))
                    total_savings += float(row.get('est_savings', 0))

        total_prompts = sum(counts.values())
        return counts, total_prompts, total_est, total_savings
    except Exception:
        return {'haiku': 0, 'sonnet': 0, 'opus': 0}, 0, 0.0, 0.0


# --- Budget Monitoring ---

def check_budget():
    """Check if spending is approaching budget limits."""
    try:
        with open(BUDGET_FILE, 'r') as f:
            budget = json.load(f)
    except Exception:
        return None

    daily_limit = budget.get('daily_limit_usd', None)
    weekly_limit = budget.get('weekly_limit_usd', None)

    if not daily_limit and not weekly_limit:
        return None

    counts, total_prompts, daily_est, _ = get_daily_summary()

    alerts = []
    if daily_limit and daily_est > daily_limit * 0.8:
        pct = (daily_est / daily_limit) * 100
        alerts.append(f'Daily budget: ${daily_est:.2f} / ${daily_limit:.2f} ({pct:.0f}%)')

    return alerts if alerts else None


# --- Session Depth Tracking ---

# Cache write pricing per 1M tokens (the hidden cost killer)
CACHE_WRITE_PRICING = {
    'haiku':  1.25,
    'sonnet': 3.75,
    'opus':   18.75,
}

# Estimated context size growth per prompt (tokens)
# Based on real data: avg ~4-6K tokens per turn (prompt + response + tool results)
EST_TOKENS_PER_TURN = 5000

# Session depth thresholds and warnings
SESSION_THRESHOLDS = [
    (15, 'TIP',     'Consider /compact to reduce context size'),
    (25, 'WARNING', 'Cache costs growing — try /compact or start fresh'),
    (40, 'ALERT',   'Long session! Start a new conversation to reset cache costs'),
]


def get_session_id():
    """Get a stable session ID for this Claude Code process.

    Uses CLAUDE_SESSION_ID env var if available, otherwise falls back
    to parent PID (the Claude Code process that spawned this hook).
    """
    return os.environ.get('CLAUDE_SESSION_ID', str(os.getppid()))


def track_session_depth():
    """Increment and return the current session prompt count.

    Writes a counter file per session in SESSION_DIR.
    Returns (prompt_number, est_context_tokens, cache_cost_alert).
    """
    try:
        os.makedirs(SESSION_DIR, exist_ok=True)
        session_id = get_session_id()
        session_file = os.path.join(SESSION_DIR, f'session_{session_id}.json')

        # Read or initialize
        if os.path.exists(session_file):
            with open(session_file, 'r') as f:
                data = json.load(f)
            data['prompt_count'] += 1
        else:
            data = {
                'session_id': session_id,
                'started': datetime.now().isoformat(),
                'prompt_count': 1,
            }

        # Write back
        with open(session_file, 'w') as f:
            json.dump(data, f)

        prompt_count = data['prompt_count']
        est_context = prompt_count * EST_TOKENS_PER_TURN

        # Check thresholds (use highest matching)
        alert = None
        for threshold, level, message in SESSION_THRESHOLDS:
            if prompt_count >= threshold:
                # Estimate cache write cost per prompt at this depth
                opus_cache_cost = CACHE_WRITE_PRICING['opus'] * est_context / 1_000_000
                sonnet_cache_cost = CACHE_WRITE_PRICING['sonnet'] * est_context / 1_000_000
                alert = {
                    'level': level,
                    'message': message,
                    'prompt_count': prompt_count,
                    'est_context_k': round(est_context / 1000),
                    'opus_cache_per_prompt': opus_cache_cost,
                    'sonnet_cache_per_prompt': sonnet_cache_cost,
                }

        return prompt_count, est_context, alert

    except Exception:
        return 0, 0, None


def analyze_compaction_need(session_data):
    """v5.0: Smart compaction advisor — analyzes WHY context is bloated.

    Returns a recommendation dict or None.
    """
    prompt_count = session_data.get('prompt_count', 0)
    subagent_spawns = session_data.get('subagent_spawns', 0)
    file_reads = session_data.get('file_reads', 0)
    bash_calls = session_data.get('bash_calls', 0)

    if prompt_count < 10:
        return None

    # Estimate context composition
    est_context_k = round(prompt_count * EST_TOKENS_PER_TURN / 1000)

    # Subagent-heavy sessions balloon fast
    if subagent_spawns >= 3:
        return {
            'reason': f'{subagent_spawns} subagent spawns inflating context',
            'action': '/compact — subagent results dominate context',
            'severity': 'high' if subagent_spawns >= 5 else 'medium',
            'est_context_k': est_context_k,
        }

    # File-read-heavy sessions (lots of tool output)
    if file_reads >= 10:
        return {
            'reason': f'{file_reads} file reads — tool output bloating context',
            'action': '/compact — most context is file content already read',
            'severity': 'high' if file_reads >= 20 else 'medium',
            'est_context_k': est_context_k,
        }

    # Long sessions with lots of bash output
    if bash_calls >= 15:
        return {
            'reason': f'{bash_calls} bash commands — terminal output in context',
            'action': '/compact or start fresh',
            'severity': 'medium',
            'est_context_k': est_context_k,
        }

    # General depth warning
    if prompt_count >= 20:
        return {
            'reason': f'{prompt_count} prompts deep — context growing',
            'action': '/compact to reduce cache write costs',
            'severity': 'medium' if prompt_count < 30 else 'high',
            'est_context_k': est_context_k,
        }

    return None


def cleanup_stale_sessions():
    """Remove session files older than 24 hours (runs occasionally)."""
    try:
        if not os.path.exists(SESSION_DIR):
            return
        now = datetime.now().timestamp()
        for f in os.listdir(SESSION_DIR):
            fp = os.path.join(SESSION_DIR, f)
            if now - os.path.getmtime(fp) > 86400:  # 24 hours
                os.remove(fp)
    except Exception:
        pass


# --- v6.0: SOC 2 Compliance Functions ---

def load_sentinel_config():
    """Load feature toggle config for v6.0 SOC 2 features."""
    try:
        with open(SENTINEL_CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception:
        return {}


def scan_for_phi(text, source='prompt'):
    """Scan text for PHI/PII patterns. Returns list of (pattern_name, source) detections."""
    detections = []
    for name, pattern in PHI_PATTERNS.items():
        if re.search(pattern, text, re.IGNORECASE):
            detections.append((name, source))
    return detections


def log_phi_detection(detections, session_id):
    """Log PHI detections (metadata only, NEVER content)."""
    try:
        ensure_log_dir()
        now = datetime.now().isoformat()
        with open(PHI_LOG, 'a') as f:
            for pattern_name, source in detections:
                f.write(f'{now} | {pattern_name} | {source} | session={session_id}\n')
    except Exception:
        pass


def log_prompt_audit(prompt, model, score, session_id, project_dir):
    """Log SHA-256 hash of prompt for audit trail. NEVER logs content."""
    try:
        ensure_log_dir()
        prompt_hash = hashlib.sha256(prompt.encode('utf-8')).hexdigest()
        now = datetime.now().isoformat()
        with open(AUDIT_LOG, 'a') as f:
            f.write(f'{now} | {prompt_hash} | {model} | {score} | {session_id} | {project_dir}\n')
    except Exception:
        pass


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
            'prompt_length': len(prompt),
        }

        model, reason, score = score_and_recommend(analysis)

        # Log the decision
        log_routing_decision(model, score, reason, prompt, project_dir)

        # v6.0: SOC 2 compliance checks
        sentinel_config = load_sentinel_config()
        session_id = get_session_id()

        # v6.0: Prompt audit log (hash-based, never logs content)
        if sentinel_config.get('features', {}).get('prompt_audit', {}).get('enabled', True):
            log_prompt_audit(prompt, model, score, session_id, project_dir)

        # v6.0: PHI pattern scanning
        if sentinel_config.get('features', {}).get('phi_scanner', {}).get('scan_prompts', True):
            phi_detections = scan_for_phi(prompt, source='prompt')
            if phi_detections:
                log_phi_detection(phi_detections, session_id)
                pattern_names = ', '.join(d[0] for d in phi_detections)
                print(f'\n  PHI WARNING: Potential PHI detected in prompt ({pattern_names})', file=sys.stderr)
                print(f'  Review prompt content before proceeding.\n', file=sys.stderr)

        # Track session depth
        session_depth, est_context, session_alert = track_session_depth()

        # Cleanup stale sessions occasionally (1 in 20 calls)
        if session_depth % 20 == 0:
            cleanup_stale_sessions()

        # Get daily stats
        counts, total_prompts, daily_est, daily_savings = get_daily_summary()

        # Check budget
        budget_alerts = check_budget()

        # Build output
        kw = analysis['keywords']
        output_lines = [
            '',
            '+---------------------------------------------------------+',
            '|  Sentinel v6.0 - Cost Optimization + SOC 2           |',
            '+---------------------------------------------------------+',
            '',
            f'  Analysis:',
            f'    Keywords: Simple={kw["simple_score"]} Complex={kw["complex_score"]} Downgrade={kw["downgrade_score"]}',
            f'    Debug={kw["debug_score"]} Review={kw["review_score"]}',
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

        # Daily stats with savings
        if total_prompts > 0:
            output_lines += [
                '',
                f'  Today: {total_prompts} prompts | '
                f'H:{counts["haiku"]} S:{counts["sonnet"]} O:{counts["opus"]} | '
                f'Est: ${daily_est:.2f}',
            ]
            if daily_savings > 0:
                output_lines.append(
                    f'  Saved vs all-Opus: ${daily_savings:.2f}'
                )

        # Session depth alert
        if session_alert:
            lvl = session_alert['level']
            output_lines += [
                '',
                f'  {lvl}: Session depth: {session_alert["prompt_count"]} prompts (~{session_alert["est_context_k"]}K context)',
                f'    Cache write/prompt: Opus=${session_alert["opus_cache_per_prompt"]:.2f}  Sonnet=${session_alert["sonnet_cache_per_prompt"]:.2f}',
                f'    -> {session_alert["message"]}',
            ]
        elif session_depth > 0:
            est_k = round(est_context / 1000)
            output_lines.append(f'  Session: {session_depth} prompts (~{est_k}K context)')

        # v5.0: Smart compaction advisor
        try:
            session_id = get_session_id()
            session_file = os.path.join(SESSION_DIR, f'session_{session_id}.json')
            if os.path.exists(session_file):
                with open(session_file, 'r') as f:
                    session_data = json.load(f)
                compact_rec = analyze_compaction_need(session_data)
                if compact_rec:
                    sev = compact_rec['severity'].upper()
                    output_lines += [
                        '',
                        f'  COMPACT [{sev}]: {compact_rec["reason"]}',
                        f'    -> {compact_rec["action"]}',
                    ]
        except Exception:
            pass

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
