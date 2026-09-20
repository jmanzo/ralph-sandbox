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

MAX="${1:-${RALPH_LOOP_MAX:-0}}"
PROMPT_FILE="${RALPH_PROMPT_FILE:-.ralph/PROMPT.md}"
PROGRESS_FILE="${RALPH_PROGRESS_FILE:-.ralph/progress.md}"
LOG_DIR="${RALPH_LOG_DIR:-.ralph/logs}"
AGENT_CMD="${RALPH_AGENT_CMD:-claude --dangerously-skip-permissions}"
SLEEP="${RALPH_LOOP_SLEEP:-0}"
STALL_LIMIT="${RALPH_LOOP_STALL:-3}"
FAIL_LIMIT="${RALPH_LOOP_FAILS:-2}"
REPEAT_LIMIT="${RALPH_LOOP_REPEAT:-3}"
MAX_COST="${RALPH_LOOP_MAX_COST:-}"
MODEL="${RALPH_MODEL_ORCHESTRATOR:-}"
ALERT_JSON="${RALPH_ALERT_JSON:-.ralph/alert.json}"
ALERT_TXT="${RALPH_ALERT_TXT:-.ralph/alert.txt}"

SIGIL='<promise>COMPLETE</promise>'

say()  { printf '\033[36m==> %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[33mralph-loop: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31mralph-loop: %s\033[0m\n' "$*" >&2; exit 1; }

# 0 means what it says: keep going until the PRD is done or a guardrail trips.
# That is the normal way to run this -- a cap is for when you want to sample.
case "$MAX" in
  unlimited|none|inf) MAX=0 ;;
  ''|*[!0-9]*) die "iteration cap must be a number, or 0 for no cap, got '$MAX'" ;;
esac
[ -f "$PROMPT_FILE" ] || die "no $PROMPT_FILE here -- run 'ralph init' on the host first"

USE_JQ=0
command -v jq >/dev/null 2>&1 && USE_JQ=1
git rev-parse --git-dir >/dev/null 2>&1 || warn "not a git repository -- the loop cannot commit, and iterations will not remember each other"

read -r -a AGENT <<<"$AGENT_CMD"
command -v "${AGENT[0]}" >/dev/null 2>&1 || die "agent not found: ${AGENT[0]}"

# The orchestrator is deliberately the cheapest model in the tree: it routes and
# records, and the subagents -- whose models live in .claude/agents/*.md -- do
# the thinking. An explicit --model in RALPH_AGENT_CMD wins.
if [ -n "$MODEL" ]; then
  case " $AGENT_CMD " in
    *" --model "*|*" -m "*) : ;;
    *) AGENT+=(--model "$MODEL") ;;
  esac
fi

mkdir -p "$LOG_DIR"
rm -f "$ALERT_JSON" "$ALERT_TXT"
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

# The failure signature the orchestrator emits when it gives up on a task. The
# same string three times running means two agents are trading one bug back and
# forth, which is the most expensive way for this loop to achieve nothing.
blocked_signature() {
  local log="$1" text
  if [ "$USE_JQ" = 1 ]; then
    text="$(jq -r 'select(.type == "result") | (.result // "")' "$log" 2>/dev/null)"
  else
    text="$(cat "$log" 2>/dev/null)"
  fi
  printf '%s\n' "$text" \
    | sed -n 's/.*<blocked>\(.*\)<\/blocked>.*/\1/p' \
    | head -1 \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed 's/^ *//; s/ *$//' \
    | cut -c1-200
}

json_escape() {
  printf '%s' "${1:-}" \
    | tr '\n\r\t' '   ' \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# The alert is written here and posted by the HOST once the container exits.
# Deliberate: the sandbox never needs Slack on its egress allowlist, and the
# webhook URL never enters it.
write_alert() {
  local code="$1" reason="$2" detail="${3:-}" elapsed
  elapsed=$(($(date +%s) - started))
  mkdir -p "$(dirname "$ALERT_JSON")" 2>/dev/null || true
  {
    printf '{"exit":%s,'            "$code"
    printf '"reason":"%s",'         "$(json_escape "$reason")"
    printf '"detail":"%s",'         "$(json_escape "$detail")"
    printf '"iterations":%s,'       "$iteration"
    printf '"cost_usd":"%s",'       "$total_cost"
    printf '"elapsed_seconds":%s,'  "$elapsed"
    printf '"workspace":"%s",'      "$(json_escape "${RALPH_PROJECT:-/workspace}")"
    printf '"finished_at":"%s"}\n'  "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$ALERT_JSON"
  {
    printf 'ralph loop: %s\n' "$reason"
    printf '%s  |  %s iteration(s)  |  %sm%ss  |  $%s\n' \
      "${RALPH_PROJECT:-/workspace}" "$iteration" \
      "$((elapsed / 60))" "$((elapsed % 60))" "$total_cost"
    [ -n "$detail" ] && printf '%s\n' "$detail"
  } > "$ALERT_TXT"
}

finish() {
  write_alert "$1" "$2" "${3:-}"
  summary
  exit "$1"
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
repeats=0
previous=""
last_signature=""
signature=""
total_cost=0
started="$(date +%s)"

summary() {
  local elapsed=$(($(date +%s) - started))
  say "$iteration iteration(s), $((elapsed / 60))m$((elapsed % 60))s, cost \$$total_cost"
  say "transcripts in $LOG_DIR"
}
trap 'printf "\n"; warn "interrupted"; finish 130 "interrupted by hand"' INT

while [ "$MAX" -eq 0 ] || [ "$iteration" -lt "$MAX" ]; do
  iteration=$((iteration + 1))
  stamp="$(date +%Y%m%d-%H%M%S)"
  log="$LOG_DIR/$(printf '%03d' "$iteration")-$stamp.jsonl"

  if [ "$MAX" -eq 0 ]; then
    say "iteration $iteration  ($stamp)"
  else
    say "iteration $iteration/$MAX  ($stamp)"
  fi

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
      finish 1 "the agent failed $fails times running" "last exit code $rc; transcript $log"
    fi
    [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
    continue
  fi
  fails=0

  if completed "$log"; then
    say "the agent reports the PRD is done"
    finish 0 "finished the PRD"
  fi

  # With no iteration cap, the spend ceiling is the other end of the leash.
  if [ -n "$MAX_COST" ] \
     && awk -v a="$total_cost" -v b="$MAX_COST" 'BEGIN { exit !(a + 0 >= b + 0) }'; then
    warn "spent \$$total_cost, at or past the \$$MAX_COST ceiling"
    finish 5 "hit the \$$MAX_COST spend ceiling" \
      "\$$total_cost over $iteration iteration(s); the PRD is not finished"
  fi

  # Has the orchestrator given up on the same thing it gave up on last time?
  signature="$(blocked_signature "$log")"
  if [ -n "$signature" ]; then
    if [ "$signature" = "$last_signature" ]; then
      repeats=$((repeats + 1))
    else
      repeats=1
    fi
    last_signature="$signature"
    warn "iteration $iteration ended blocked ($repeats/$REPEAT_LIMIT): $signature"
    if [ "$repeats" -ge "$REPEAT_LIMIT" ]; then
      warn "the same failure has survived $repeats iterations -- stopping before it costs more"
      finish 4 "stuck on one failure for $repeats iterations" "blocked on: $signature"
    fi
  else
    repeats=0
    last_signature=""
  fi

  current="$(fingerprint)"
  if [ "$current" = "$previous" ]; then
    stalls=$((stalls + 1))
    warn "nothing changed this iteration (stall $stalls/$STALL_LIMIT)"
    if [ "$stalls" -ge "$STALL_LIMIT" ]; then
      warn "the loop is not making progress -- read $PROGRESS_FILE and sharpen the PRD"
      finish 2 "changed nothing for $stalls iterations" "nothing committed and nothing logged; the PRD may be too vague to act on"
    fi
  else
    stalls=0
  fi
  previous="$current"

  [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
done

say "iteration cap of $MAX reached without a completion signal"
finish 3 "ran out of iterations" \
  "cap of $MAX spent; raise it, drop it for an uncapped run, or narrow the PRD"
