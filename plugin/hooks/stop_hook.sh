#!/bin/bash
# Claude Model Router v5.0 - Stop hook
# Generates a session summary when Claude Code finishes a conversation turn.
# v5.0: Smart compaction advisor, subagent cost summary

ROUTER_HOME="${CLAUDE_ROUTER_HOME:-$HOME/.claude/plugins/model-router}"
LOG_DIR="$ROUTER_HOME/logs"
COST_LOG="$LOG_DIR/cost_log.csv"
SESSION_LOG="$LOG_DIR/session_summary.log"
SESSION_DIR="$LOG_DIR/sessions"

mkdir -p "$LOG_DIR" "$SESSION_DIR"

# Get today's routing stats
TODAY=$(date +%Y-%m-%d)
if [ -f "$COST_LOG" ]; then
  HAIKU_COUNT=$(grep "$TODAY" "$COST_LOG" | grep -c "haiku" || echo "0")
  SONNET_COUNT=$(grep "$TODAY" "$COST_LOG" | grep -c "sonnet" || echo "0")
  OPUS_COUNT=$(grep "$TODAY" "$COST_LOG" | grep -c "opus" || echo "0")
  TOTAL=$((HAIKU_COUNT + SONNET_COUNT + OPUS_COUNT))

  EST_COST=$(grep "$TODAY" "$COST_LOG" | awk -F',' '{sum += $8 + $9} END {printf "%.2f", sum}' 2>/dev/null || echo "0.00")
  EST_SAVINGS=$(grep "$TODAY" "$COST_LOG" | awk -F',' '{sum += $12} END {printf "%.2f", sum}' 2>/dev/null || echo "0.00")
else
  HAIKU_COUNT=0
  SONNET_COUNT=0
  OPUS_COUNT=0
  TOTAL=0
  EST_COST="0.00"
  EST_SAVINGS="0.00"
fi

# Count file changes this session
FILE_CHANGES=0
if [ -f "$LOG_DIR/file_changes.log" ]; then
  FILE_CHANGES=$(grep -c "$TODAY" "$LOG_DIR/file_changes.log" 2>/dev/null || echo "0")
fi

# Count git operations
GIT_OPS=0
if [ -f "$LOG_DIR/git_operations.log" ]; then
  GIT_OPS=$(grep -c "$TODAY" "$LOG_DIR/git_operations.log" 2>/dev/null || echo "0")
fi

# v5.0: Get session-specific stats
SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
SESSION_FILE="$SESSION_DIR/session_${SESSION_ID}.json"
SUBAGENT_SPAWNS=0
SESSION_FILE_READS=0
SESSION_BASH_CALLS=0

if [ -f "$SESSION_FILE" ]; then
  SUBAGENT_SPAWNS=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
print(data.get('subagent_spawns', 0))
" "$SESSION_FILE" 2>/dev/null || echo "0")

  SESSION_FILE_READS=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
print(data.get('file_reads', 0))
" "$SESSION_FILE" 2>/dev/null || echo "0")

  SESSION_BASH_CALLS=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
print(data.get('bash_calls', 0))
" "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Only show summary if there's meaningful activity
if [ "$TOTAL" -gt 0 ] || [ "$FILE_CHANGES" -gt 0 ]; then
  SUMMARY="
  +---------------------------------------------------------+
  |  Session Summary (v5.0)                                 |
  +---------------------------------------------------------+

  Routing:  $TOTAL prompts (H:$HAIKU_COUNT S:$SONNET_COUNT O:$OPUS_COUNT)
  Est cost: \$$EST_COST today"

  # v5.0: Show savings if meaningful
  if [ "$(echo "$EST_SAVINGS > 0.01" | bc 2>/dev/null)" = "1" ]; then
    SUMMARY="$SUMMARY
  Saved:    \$$EST_SAVINGS vs all-Opus"
  fi

  SUMMARY="$SUMMARY
  Files:    $FILE_CHANGES changes tracked
  Git ops:  $GIT_OPS operations"

  # v5.0: Subagent stats
  if [ "$SUBAGENT_SPAWNS" -gt 0 ]; then
    SUMMARY="$SUMMARY
  Agents:   $SUBAGENT_SPAWNS subagents spawned"
  fi

  # v5.0: Context composition breakdown
  if [ "$SESSION_FILE_READS" -gt 5 ] || [ "$SESSION_BASH_CALLS" -gt 5 ] || [ "$SUBAGENT_SPAWNS" -gt 2 ]; then
    SUMMARY="$SUMMARY

  Context composition:
    File reads:  $SESSION_FILE_READS
    Bash calls:  $SESSION_BASH_CALLS
    Subagents:   $SUBAGENT_SPAWNS"
  fi

  SUMMARY="$SUMMARY
"

  echo "$SUMMARY"

  # Append to session log
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | prompts=$TOTAL h=$HAIKU_COUNT s=$SONNET_COUNT o=$OPUS_COUNT est=\$$EST_COST saved=\$$EST_SAVINGS files=$FILE_CHANGES git=$GIT_OPS agents=$SUBAGENT_SPAWNS" >> "$SESSION_LOG"
fi

exit 0
