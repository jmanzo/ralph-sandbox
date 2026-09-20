#!/usr/bin/env bash
#
# ralph-loop -- run the agent against .ralph/PROMPT.md, one task per iteration,
# until the PRD is done or the iteration budget runs out.
#
# This runs INSIDE the sandbox; `ralph loop` on the host is what starts it.
# Each iteration is a fresh agent session with no memory of the last one. The
# loop's memory is the git history and .ralph/progress.md, which is the whole
# point of the technique: context that survives is context someone wrote down.
#
set -uo pipefail

MAX="${1:-${RALPH_LOOP_MAX:-10}}"
PROMPT_FILE="${RALPH_PROMPT_FILE:-.ralph/PROMPT.md}"
PROGRESS_FILE="${RALPH_PROGRESS_FILE:-.ralph/progress.md}"
LOG_DIR="${RALPH_LOG_DIR:-.ralph/logs}"
AGENT_CMD="${RALPH_AGENT_CMD:-claude --dangerously-skip-permissions}"
SLEEP="${RALPH_LOOP_SLEEP:-0}"
STALL_LIMIT="${RALPH_LOOP_STALL:-3}"
FAIL_LIMIT="${RALPH_LOOP_FAILS:-2}"

SIGIL='<promise>COMPLETE</promise>'

say()  { printf '\033[36m==> %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[33mralph-loop: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mralph-loop: %s\033[0m\n' "$*" >&2; exit 1; }

case "$MAX" in
  ''|*[!0-9]*) die "iteration budget must be a number, got '$MAX'" ;;
esac
[ "$MAX" -gt 0 ] || die "iteration budget must be at least 1"
[ -f "$PROMPT_FILE" ] || die "no $PROMPT_FILE here -- run 'ralph init' on the host first"

USE_JQ=0
command -v jq >/dev/null 2>&1 && USE_JQ=1
git rev-parse --git-dir >/dev/null 2>&1 || warn "not a git repository -- the loop cannot commit, and iterations will not remember each other"

read -r -a AGENT <<<"$AGENT_CMD"
command -v "${AGENT[0]}" >/dev/null 2>&1 || die "agent not found: ${AGENT[0]}"

mkdir -p "$LOG_DIR"
PROMPT="$(cat "$PROMPT_FILE")"

# Render the agent's JSON event stream as something a human can watch. The
# untouched stream still goes to the log, so nothing is lost to the filter.
pretty() {
  if [ "$USE_JQ" = 1 ]; then
    jq -j --unbuffered '
      if .type == "assistant" then
        ( .message.content[]?
          | if   .type == "text"     then .text
            elif .type == "tool_use" then "\n  . " + (.name // "tool") + "\n"
            else empty end )
      elif .type == "result" then
        "\n\n[" + (.subtype // "result")
        + "] turns=" + ((.num_turns // 0) | tostring)
        + " cost=$" + ((.total_cost_usd // 0) | tostring) + "\n"
      else empty end' 2>/dev/null
  else
    cat
  fi
}

# Done means the agent said so in its final message. Checking the result event
# rather than the whole transcript keeps a mid-run mention of the sigil -- the
# agent quoting its own instructions, say -- from ending the run early.
completed() {
  local log="$1"
  if [ "$USE_JQ" = 1 ]; then
    jq -r 'select(.type == "result") | (.result // "")' "$log" 2>/dev/null \
      | grep -qF "$SIGIL" && return 0
    jq -r 'select(.type == "assistant")
           | (.message.content[]? | select(.type == "text") | .text)' "$log" 2>/dev/null \
      | tail -5 | grep -qF "$SIGIL" && return 0
    return 1
  fi
  grep -qF "$SIGIL" "$log"
}

# An iteration that moved neither the git history nor the progress log did
# nothing, whatever it said. A few of those in a row means the loop is stuck
# and burning money.
fingerprint() {
  git rev-parse HEAD 2>/dev/null || printf 'no-head'
  git status --porcelain 2>/dev/null | cksum
  # --porcelain lists paths, not contents: without this, two iterations that
  # edited the same tracked file differently would look identical.
  git diff HEAD 2>/dev/null | cksum
  cksum < "$PROGRESS_FILE" 2>/dev/null || printf 'no-progress'
}

iteration=0
fails=0
stalls=0
previous=""
total_cost=0
started="$(date +%s)"

summary() {
  local elapsed=$(($(date +%s) - started))
  say "$iteration iteration(s), $((elapsed / 60))m$((elapsed % 60))s, cost \$$total_cost"
  say "transcripts in $LOG_DIR"
}
trap 'printf "\n"; warn "interrupted"; summary; exit 130' INT

while [ "$iteration" -lt "$MAX" ]; do
  iteration=$((iteration + 1))
  stamp="$(date +%Y%m%d-%H%M%S)"
  log="$LOG_DIR/$(printf '%03d' "$iteration")-$stamp.jsonl"

  say "iteration $iteration/$MAX  ($stamp)"

  "${AGENT[@]}" -p "$PROMPT" --output-format stream-json --verbose 2>&1 \
    | tee "$log" | pretty
  rc="${PIPESTATUS[0]}"

  if [ "$USE_JQ" = 1 ]; then
    cost="$(jq -r 'select(.type == "result") | (.total_cost_usd // empty)' "$log" 2>/dev/null | tail -1)"
    [ -n "${cost:-}" ] && total_cost="$(awk -v a="$total_cost" -v b="$cost" 'BEGIN { printf "%.4f", a + b }')"
  fi

  if [ "$rc" -ne 0 ]; then
    fails=$((fails + 1))
    warn "iteration $iteration exited $rc (consecutive failure $fails/$FAIL_LIMIT)"
    if [ "$fails" -ge "$FAIL_LIMIT" ]; then
      warn "the agent is not running; see $log"
      summary
      exit 1
    fi
    [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
    continue
  fi
  fails=0

  if completed "$log"; then
    say "the agent reports the PRD is done"
    summary
    exit 0
  fi

  current="$(fingerprint)"
  if [ "$current" = "$previous" ]; then
    stalls=$((stalls + 1))
    warn "nothing changed this iteration (stall $stalls/$STALL_LIMIT)"
    if [ "$stalls" -ge "$STALL_LIMIT" ]; then
      warn "the loop is not making progress -- read $PROGRESS_FILE and sharpen the PRD"
      summary
      exit 2
    fi
  else
    stalls=0
  fi
  previous="$current"

  [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
done

say "iteration budget of $MAX reached without a completion signal"
summary
exit 3
