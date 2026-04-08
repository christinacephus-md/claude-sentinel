#!/bin/bash
# Claude Sentinel v6.0 - PreToolUse hook
# Intercepts Bash tool calls containing git/gh commands.
# Actively strips AI trailers from commit messages and PR bodies before they execute.
# v6.0: PHI pattern scanning + secret detection on Bash commands.

# Read the tool input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

ROUTER_HOME="${CLAUDE_ROUTER_HOME:-$HOME/.claude/plugins/sentinel}"

# Only process Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Check if command contains git commit or gh pr create
IS_GIT_COMMIT=$(echo "$COMMAND" | grep -cE "git commit" || true)
IS_GH_PR=$(echo "$COMMAND" | grep -cE "gh pr create" || true)
IS_GIT_PUSH=$(echo "$COMMAND" | grep -cE "git push" || true)

if [ "$IS_GIT_COMMIT" -gt 0 ] || [ "$IS_GH_PR" -gt 0 ]; then
  # Check for AI markers in the command
  HAS_MARKER=$(echo "$COMMAND" | grep -ciE "co-authored-by.*claude|generated.with.*claude|noreply@anthropic|🤖.*generated|🤖 Generated" || true)

  if [ "$HAS_MARKER" -gt 0 ]; then
    # Strip the AI trailers from the command itself
    CLEANED=$(echo "$COMMAND" | sed -E \
      -e 's/[[:space:]]*Co-[Aa]uthored-[Bb]y:[[:space:]]*Claude[^\n]*//' \
      -e 's/[[:space:]]*Co-[Aa]uthored-[Bb]y:[^\n]*noreply@anthropic[^\n]*//' \
      -e 's/[[:space:]]*Generated-by:[^\n]*//' \
      -e 's/🤖[[:space:]]*Generated with \[Claude Code\]\(https:\/\/claude\.com\/claude-code\)//' \
      -e 's/🤖[[:space:]]*Generated with \[Claude Code\][^\n]*//' \
      -e 's/[[:space:]]*Generated with \[Claude Code\]\(https:\/\/claude\.com\/claude-code\)//' \
      -e 's/[[:space:]]*Generated with \[Claude Code\][^\n]*//' \
    )

    # Remove leftover blank lines that pile up after stripping
    CLEANED=$(echo "$CLEANED" | sed -E '/^[[:space:]]*$/{ N; /^\n[[:space:]]*$/d; }')

    # Output the modified tool input as JSON so Claude Code uses the cleaned command
    python3 -c "
import json, sys
cleaned = sys.stdin.read()
print(json.dumps({'decision': 'modify', 'tool_input': {'command': cleaned}}))
" <<< "$CLEANED"

    # Also print a notice to stderr so the user sees it
    echo "" >&2
    echo "  +---------------------------------------------------------+" >&2
    echo "  |  Git Hygiene - AI trailers stripped                      |" >&2
    echo "  +---------------------------------------------------------+" >&2
    echo "" >&2
    if [ "$IS_GIT_COMMIT" -gt 0 ]; then
      echo "  Cleaned: git commit message" >&2
    fi
    if [ "$IS_GH_PR" -gt 0 ]; then
      echo "  Cleaned: gh pr create body" >&2
    fi
    echo "" >&2

    exit 0
  fi
fi

# Log git push events for awareness
if [ "$IS_GIT_PUSH" -gt 0 ]; then
  LOG_DIR="$ROUTER_HOME/logs"
  mkdir -p "$LOG_DIR"
  # Log git push with only the remote name, not the full URL (may contain tokens)
  PUSH_REMOTE=$(echo "$COMMAND" | awk '{for(i=1;i<=NF;i++) if($i=="push") print $(i+1)}' | sed 's|https://[^@]*@|https://***@|g')
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | git push | ${PUSH_REMOTE:-origin}" >> "$LOG_DIR/git_operations.log"
fi

# --- v6.0: Combined PHI + Secret scanning for Bash commands ---
if [ -n "$COMMAND" ]; then
  SCAN_RESULT=$(python3 -c "
import json, os, re, sys

# Load config
config = {}
rh = os.environ.get('CLAUDE_ROUTER_HOME', os.path.expanduser('~/.claude/plugins/sentinel'))
try:
    with open(os.path.join(rh, 'config', 'sentinel_config.json')) as f:
        config = json.load(f)
except: pass

features = config.get('features', {})
text = sys.stdin.read()
results = []

# PHI scan
if features.get('phi_scanner', {}).get('scan_bash', True):
    # Load from shared phi_patterns.json (single source of truth)
    phi = {}
    try:
        with open(os.path.join(rh, 'config', 'phi_patterns.json')) as pf:
            phi = json.load(pf).get('patterns', {})
    except: pass
    if not phi:
        phi = {'ssn': r'\b\d{3}-\d{2}-\d{4}\b', 'email': r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'}
    hits = [n for n, p in phi.items() if re.search(p, text, re.IGNORECASE)]
    if hits:
        results.append('phi:' + ','.join(hits))

# Secret scan
if features.get('secret_scanner', {}).get('scan_bash', True):
    sec = {
        'aws_key': r'AKIA[0-9A-Z]{16}',
        'github_token': r'gh[ps]_[A-Za-z0-9_]{36,}',
        'github_pat': r'github_pat_[A-Za-z0-9_]{22,}',
        'bearer': r'[Bb]earer\s+[A-Za-z0-9\-._~+/]{20,}',
        'generic_secret': r'(?:password|secret|token|api_key|apikey)\s*[=:]\s*[\x22\x27]?[A-Za-z0-9\-._~+/]{8,}',
        'private_key': r'-----BEGIN.*PRIVATE KEY-----',
    }
    hits = [n for n, p in sec.items() if re.search(p, text)]
    if hits:
        results.append('secret:' + ','.join(hits))

print('|'.join(results) if results else '')
" <<< "$COMMAND" 2>/dev/null)

  if [ -n "$SCAN_RESULT" ]; then
    LOG_DIR="$ROUTER_HOME/logs"
    mkdir -p "$LOG_DIR"
    SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

    # Read enforcement modes from config (single Python call for both)
    ENFORCEMENT=$(python3 -c "
import json, os
rh = os.environ.get('CLAUDE_ROUTER_HOME', os.path.join(os.path.expanduser('~'), '.claude', 'plugins', 'sentinel'))
try:
    with open(os.path.join(rh, 'config', 'sentinel_config.json')) as f:
        c = json.load(f)
    phi_e = c.get('features',{}).get('phi_scanner',{}).get('enforcement','warn')
    sec_e = c.get('features',{}).get('secret_scanner',{}).get('enforcement','warn')
    print(f'{phi_e}|{sec_e}')
except: print('warn|warn')
" 2>/dev/null)
    PHI_ENFORCEMENT=$(echo "$ENFORCEMENT" | cut -d'|' -f1)
    SECRET_ENFORCEMENT=$(echo "$ENFORCEMENT" | cut -d'|' -f2)

    BLOCK_REASONS=""

    # Parse and handle PHI detections
    if echo "$SCAN_RESULT" | grep -q "phi:"; then
      PHI_TYPES=$(echo "$SCAN_RESULT" | grep -o 'phi:[^|]*' | sed 's/phi://')
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $PHI_TYPES | bash | session=$SESSION_ID" >> "$LOG_DIR/phi_detections.log"
      if [ "$PHI_ENFORCEMENT" = "block" ]; then
        BLOCK_REASONS="PHI detected: $PHI_TYPES"
      else
        echo "" >&2
        echo "  PHI WARNING: Potential PHI in Bash command ($PHI_TYPES)" >&2
        echo "  Review command content before proceeding." >&2
        echo "" >&2
      fi
    fi

    # Parse and handle secret detections
    if echo "$SCAN_RESULT" | grep -q "secret:"; then
      SECRET_TYPES=$(echo "$SCAN_RESULT" | grep -o 'secret:[^|]*' | sed 's/secret://')
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $SECRET_TYPES | bash | session=$SESSION_ID" >> "$LOG_DIR/secret_detections.log"
      if [ "$SECRET_ENFORCEMENT" = "block" ]; then
        if [ -n "$BLOCK_REASONS" ]; then
          BLOCK_REASONS="$BLOCK_REASONS; Secret detected: $SECRET_TYPES"
        else
          BLOCK_REASONS="Secret detected: $SECRET_TYPES"
        fi
      else
        echo "" >&2
        echo "  SECRET WARNING: Potential secrets in Bash command ($SECRET_TYPES)" >&2
        echo "  Use environment variables instead of hardcoded secrets." >&2
        echo "" >&2
      fi
    fi

    # Emit single JSON block and exit 2 (per Claude Code April 2026 hook spec)
    if [ -n "$BLOCK_REASONS" ]; then
      echo "{\"decision\":\"block\",\"reason\":\"$BLOCK_REASONS. Configure enforcement in sentinel_config.json.\"}"
      exit 2
    fi
  fi
fi

exit 0
