#!/bin/bash
# Claude Sentinel v6.0 - PostToolUse hook
# DX feedback loops after tool execution.
# v5.0: subagent cost tracking, stronger test nudge
# v6.0: sensitive file path detection

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('tool_input',{})))" 2>/dev/null)

ROUTER_HOME="${CLAUDE_ROUTER_HOME:-$HOME/.claude/plugins/sentinel}"
LOG_DIR="$ROUTER_HOME/logs"
SESSION_DIR="$ROUTER_HOME/logs/sessions"
mkdir -p "$LOG_DIR" "$SESSION_DIR"

# --- Helper: get session file ---
get_session_file() {
  # Use PPID (not $$) to match sentinel.py's os.getppid() fallback
  SESSION_ID="${CLAUDE_SESSION_ID:-$PPID}"
  echo "$SESSION_DIR/session_${SESSION_ID}.json"
}

# --- Helper: increment session counter ---
increment_session_counter() {
  local COUNTER_NAME="$1"
  local SESSION_FILE
  SESSION_FILE=$(get_session_file)

  python3 -c "
import json, os, sys
sf = sys.argv[1]
key = sys.argv[2]
data = {}
if os.path.exists(sf):
    with open(sf, 'r') as f:
        data = json.load(f)
data[key] = data.get(key, 0) + 1
with open(sf, 'w') as f:
    json.dump(data, f)
" "$SESSION_FILE" "$COUNTER_NAME" 2>/dev/null
}

# --- v5.0: Track subagent spawns (the hidden cost killer) ---
if [ "$TOOL_NAME" = "Agent" ]; then
  increment_session_counter "subagent_spawns"

  SUBAGENT_TYPE=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('subagent_type','general-purpose'))" 2>/dev/null)
  DESCRIPTION=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('description',''))" 2>/dev/null)

  # Log agent type only — description may contain PHI from user prompts
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | Agent | type=$SUBAGENT_TYPE | [description scrubbed]" >> "$LOG_DIR/file_changes.log"

  # Check how many subagents this session has spawned
  SESSION_FILE=$(get_session_file)
  SPAWN_COUNT=$(python3 -c "
import json, os, sys
sf = sys.argv[1]
if os.path.exists(sf):
    with open(sf, 'r') as f:
        data = json.load(f)
    print(data.get('subagent_spawns', 0))
else:
    print(0)
" "$SESSION_FILE" 2>/dev/null)

  if [ "$SPAWN_COUNT" -ge 5 ]; then
    echo "" >&2
    echo "  +---------------------------------------------------------+" >&2
    echo "  |  Subagent Cost Alert                                    |" >&2
    echo "  +---------------------------------------------------------+" >&2
    echo "  $SPAWN_COUNT subagents spawned this session." >&2
    echo "  Each subagent creates its own context window + token costs." >&2
    echo "  Consider batching work or using direct tool calls instead." >&2
    echo "" >&2
  elif [ "$SPAWN_COUNT" -ge 3 ]; then
    echo "" >&2
    echo "  Note: $SPAWN_COUNT subagents spawned this session (each has its own cost)." >&2
    echo "" >&2
  fi
fi

# --- Track file reads for compaction advisor ---
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Glob" ] || [ "$TOOL_NAME" = "Grep" ]; then
  increment_session_counter "file_reads"
fi

# --- Track file writes for test coverage reminders ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

  if [ -n "$FILE_PATH" ]; then
    # Log the file change
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $TOOL_NAME | $FILE_PATH" >> "$LOG_DIR/file_changes.log"

    # v6.0: Sensitive file path detection
    BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
    case "$BASENAME" in
      .env|.env.*|credentials.json|secrets.json|*.pem|*.key|*.p12|*.pfx|*.jks|id_rsa|id_ed25519|id_ecdsa|*.keystore|service-account*.json)
        echo "" >&2
        echo "  SENSITIVE FILE: $BASENAME written — ensure this is not committed." >&2
        echo "" >&2
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | sensitive_file | $BASENAME | session=${CLAUDE_SESSION_ID:-unknown}" >> "$LOG_DIR/secret_detections.log"
        ;;
    esac

    # v5.0: Stronger test coverage nudge
    case "$FILE_PATH" in
      *.test.* | *.spec.* | *_test.* | *_spec.* | *__tests__/*) ;;  # Test file, skip
      *.ts | *.tsx | *.js | *.jsx | *.py | *.go | *.rs | *.rb)
        DIR=$(dirname "$FILE_PATH")
        BASE=$(basename "$FILE_PATH" | sed -E 's/\.[^.]+$//')
        EXT=$(basename "$FILE_PATH" | sed -E 's/.*\.//')

        TEST_EXISTS=0
        for pattern in \
          "${DIR}/${BASE}.test.${EXT}" \
          "${DIR}/${BASE}.spec.${EXT}" \
          "${DIR}/${BASE}_test.${EXT}" \
          "${DIR}/__tests__/${BASE}.test.${EXT}" \
          "${DIR}/__tests__/${BASE}.spec.${EXT}" \
          "${DIR}/test_${BASE}.${EXT}" \
          "${DIR}/tests/test_${BASE}.${EXT}" \
          "${DIR}/../tests/${BASE}_test.${EXT}" \
          "${DIR}/../test/${BASE}_test.${EXT}"; do
          if [ -f "$pattern" ]; then
            TEST_EXISTS=1
            break
          fi
        done

        if [ "$TEST_EXISTS" -eq 1 ]; then
          echo ""
          echo "  TDD: $(basename "$FILE_PATH") has tests — update them if behavior changed."
          echo ""
        else
          # v5.0: Stronger nudge for missing tests
          echo ""
          echo "  +---------------------------------------------------------+"
          echo "  |  TDD Nudge: No test file found                         |"
          echo "  +---------------------------------------------------------+"
          echo "  Source: $(basename "$FILE_PATH")"
          echo "  Consider adding: ${BASE}.test.${EXT} or test_${BASE}.${EXT}"
          echo ""
        fi
        ;;
    esac
  fi
fi

# --- Track Bash commands ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('command',''))" 2>/dev/null)

  # Hash command instead of logging raw content — may contain secrets/PHI
  CMD_HASH=$(echo -n "$COMMAND" | shasum -a 256 | cut -d' ' -f1)
  CMD_PREFIX=$(echo "$COMMAND" | cut -c1-30 | sed 's/[^a-zA-Z0-9 _\-\/\.]//g')
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | bash | ${CMD_PREFIX}... | sha256:${CMD_HASH:0:16}" >> "$LOG_DIR/session_commands.log"

  increment_session_counter "bash_calls"
fi

exit 0
