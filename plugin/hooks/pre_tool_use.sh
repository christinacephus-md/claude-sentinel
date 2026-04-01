#!/bin/bash
# Claude Sentinel v3 - PreToolUse hook
# Intercepts Bash tool calls containing git/gh commands.
# Actively strips AI trailers from commit messages and PR bodies before they execute.

# Read the tool input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

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
  ROUTER_HOME="${CLAUDE_ROUTER_HOME:-$HOME/.claude/plugins/sentinel}"
  LOG_DIR="$ROUTER_HOME/logs"
  mkdir -p "$LOG_DIR"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | git push | $COMMAND" >> "$LOG_DIR/git_operations.log"
fi

exit 0
