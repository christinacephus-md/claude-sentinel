#!/bin/bash
# Claude Sentinel v6.0 - PreToolUse hook for Write/Edit
# Scans file content being written for hardcoded secrets.
# WARN only — never blocks. Logs metadata to secret_detections.log.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
ROUTER_HOME="$HOME/.claude/plugins/sentinel"

# Only process Write/Edit tool calls
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

# Check if enabled
SECRET_ENABLED=$(python3 -c "
import json, os
try:
    rh = os.path.expanduser('~/.claude/plugins/sentinel')
    with open(os.path.join(rh, 'config', 'sentinel_config.json')) as f:
        c = json.load(f)
    print('1' if c.get('features',{}).get('secret_scanner',{}).get('scan_writes',True) else '0')
except: print('1')
" 2>/dev/null)

if [ "$SECRET_ENABLED" != "1" ]; then
  exit 0
fi

# Extract content and file path
SCAN_RESULT=$(echo "$INPUT" | python3 -c "
import json, re, sys

data = json.load(sys.stdin)
ti = data.get('tool_input', {})
file_path = ti.get('file_path', '')
# Write tool has 'content', Edit tool has 'new_string'
content = ti.get('content', '') or ti.get('new_string', '') or ''

if not content:
    sys.exit(0)

patterns = {
    'aws_key': r'AKIA[0-9A-Z]{16}',
    'github_token': r'gh[ps]_[A-Za-z0-9_]{36,}',
    'github_pat': r'github_pat_[A-Za-z0-9_]{22,}',
    'generic_secret': r'(?:password|secret|token|api_key|apikey)\s*[=:]\s*[\x22\x27]?[A-Za-z0-9\-._~+/]{8,}',
    'private_key': r'-----BEGIN.*PRIVATE KEY-----',
}
hits = [n for n, p in patterns.items() if re.search(p, content)]
if hits:
    import os
    print(','.join(hits) + '|' + os.path.basename(file_path))
" 2>/dev/null)

if [ -n "$SCAN_RESULT" ]; then
  SECRET_TYPES=$(echo "$SCAN_RESULT" | cut -d'|' -f1)
  FILE_BASENAME=$(echo "$SCAN_RESULT" | cut -d'|' -f2)
  LOG_DIR="$ROUTER_HOME/logs"
  mkdir -p "$LOG_DIR"

  echo "" >&2
  echo "  SECRET WARNING: Potential secrets in file write ($SECRET_TYPES)" >&2
  echo "  File: $FILE_BASENAME" >&2
  echo "  Use environment variables or a secrets manager instead." >&2
  echo "" >&2
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $SECRET_TYPES | write | file=$FILE_BASENAME | session=${CLAUDE_SESSION_ID:-unknown}" >> "$LOG_DIR/secret_detections.log"
fi

exit 0
