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
# Two providers can drive it. Anthropic's `claude` is the default and runs the
# four-role tree (orchestrator plus three subagents). OpenAI's `codex` is the
# fallback, and runs one session that plays all four parts, because Codex has
# no per-role subagent definitions -- only a single default subagent model.
# The handover is one-way: once codex has the loop, it keeps it.
#
set -uo pipefail

MAX="${1:-${RALPH_LOOP_MAX:-0}}"
PROMPT_FILE="${RALPH_PROMPT_FILE:-.ralph/PROMPT.md}"
CODEX_PROMPT_FILE="${RALPH_CODEX_PROMPT_FILE:-.ralph/PROMPT.codex.md}"
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

# Which provider starts the run, and which one catches it when the first one
# runs out of road. RALPH_FALLBACK=off means a limit or a wall halts the run
# the way it always did.
PROVIDER="${RALPH_PROVIDER:-anthropic}"
FALLBACK="${RALPH_FALLBACK:-codex}"
CODEX_CMD="${RALPH_CODEX_CMD:-codex exec}"
CODEX_MODEL="${RALPH_CODEX_MODEL:-gpt-5.6-sol}"
CODEX_EFFORT="${RALPH_CODEX_EFFORT:-high}"

# What "the Anthropic limit is reached" looks like in a transcript. Matched
# case-insensitively, and only on an iteration that actually failed -- an agent
# merely writing the words must not hand the run to another provider.
LIMIT_PATTERN="${RALPH_LIMIT_PATTERN:-usage limit reached|rate_limit_error|credit balance( is)? too low|429 Too Many Requests}"

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

case "$PROVIDER" in
  anthropic|codex) ;;
  *) die "unknown provider '$PROVIDER' (expected anthropic or codex)" ;;
esac
case "$FALLBACK" in
  codex|off|none|'') ;;
  *) die "unknown fallback '$FALLBACK' (expected codex or off)" ;;
esac
[ "$FALLBACK" = "none" ] && FALLBACK=off
[ -z "$FALLBACK" ] && FALLBACK=off

USE_JQ=0
command -v jq >/dev/null 2>&1 && USE_JQ=1
git rev-parse --git-dir >/dev/null 2>&1 || warn "not a git repository -- the loop cannot commit, and iterations will not remember each other"

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------
# Each provider knows four things: the command to run an iteration, how to
# find the agent's final message in the log, how to render the log for a
# human, and what an iteration cost. Everything else in this file is the same
# whichever one is driving.

AGENT=()
CODEX=()
read -r -a AGENT <<<"$AGENT_CMD"
read -r -a CODEX <<<"$CODEX_CMD"

# The orchestrator is deliberately the cheapest model in the tree: it routes and
# records, and the subagents -- whose models live in .claude/agents/*.md -- do
# the thinking. An explicit --model in RALPH_AGENT_CMD wins.
if [ -n "$MODEL" ]; then
  case " $AGENT_CMD " in
    *" --model "*|*" -m "*) : ;;
    *) AGENT+=(--model "$MODEL") ;;
  esac
fi

# Codex has no equivalent of .claude/agents/*.md: subagents it spawns all share
# one `default_subagent_model`. So the model and the reasoning effort are
# per-session, set here, and the role split lives in the prompt instead.
if [ -n "$CODEX_MODEL" ]; then
  case " $CODEX_CMD " in
    *" --model "*|*" -m "*) : ;;
    *) CODEX+=(-m "$CODEX_MODEL") ;;
  esac
fi
[ -n "$CODEX_EFFORT" ] && CODEX+=(-c "model_reasoning_effort=$CODEX_EFFORT")

provider_prompt_file() {
  case "$1" in
    codex) printf '%s' "$CODEX_PROMPT_FILE" ;;
    *)     printf '%s' "$PROMPT_FILE" ;;
  esac
}

provider_binary() {
  case "$1" in
    codex) printf '%s' "${CODEX[0]}" ;;
    *)     printf '%s' "${AGENT[0]}" ;;
  esac
}

# Run one iteration. Both providers write a JSONL transcript to $2 and the
# agent's final message to $3; the rest of the loop reads only those two.
run_iteration() {
  local provider="$1" log="$2" last="$3" rc
  case "$provider" in
    codex)
      # --dangerously-bypass-approvals-and-sandbox is the right call *here*
      # and nowhere else: codex's own sandbox would be a second cage inside
      # the container, and the container is the cage that matters.
      # -o hands us the final message directly, which beats parsing codex's
      # event schema and re-parsing it after every codex release.
      printf '%s' "$PROMPT" \
        | "${CODEX[@]}" --json \
            --dangerously-bypass-approvals-and-sandbox \
            --skip-git-repo-check \
            -o "$last" - 2>&1 \
        | tee "$log" | pretty_codex
      rc="${PIPESTATUS[1]}"
      ;;
    *)
      "${AGENT[@]}" -p "$PROMPT" --output-format stream-json --verbose 2>&1 \
        | tee "$log" | pretty_claude
      rc="${PIPESTATUS[0]}"
      # claude has no --output-last-message, so extract the same artefact here
      # and give the checks below one shape to read whoever produced it.
      claude_last_message "$log" > "$last" 2>/dev/null || : > "$last"
      ;;
  esac
  return "$rc"
}

# The final message, as claude's stream-json reports it. Preferring the result
# event over the whole transcript keeps a mid-run mention of the sigil -- the
# agent quoting its own instructions, say -- from ending the run early. The
# tail of the assistant text is the fallback for a run that produced no result
# event at all.
claude_last_message() {
  local log="$1" text
  if [ "$USE_JQ" = 1 ]; then
    text="$(jq -r 'select(.type == "result") | (.result // "")' "$log" 2>/dev/null)"
    if [ -z "${text//[[:space:]]/}" ]; then
      text="$(jq -r 'select(.type == "assistant")
                     | (.message.content[]? | select(.type == "text") | .text)' \
                "$log" 2>/dev/null | tail -5)"
    fi
    printf '%s\n' "$text"
  else
    cat "$log"
  fi
}

# Render claude's JSON event stream as something a human can watch. The
# untouched stream still goes to the log, so nothing is lost to the filter.
pretty_claude() {
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

# The same, for codex's event stream. Codex interleaves tracing lines on
# stderr with the JSONL, so anything that is not an event is passed through
# untouched rather than swallowed -- that is where its errors show up.
pretty_codex() {
  if [ "$USE_JQ" = 1 ]; then
    jq -j -R --unbuffered '
      . as $raw
      | try (fromjson) catch null
      | if . == null then
          (if ($raw | test("^\\s*(\\{|$)")) then empty else $raw + "\n" end)
        elif .type == "item.completed" then
          ( .item
            | if   .type == "agent_message"     then (.text // "") + "\n"
              elif .type == "reasoning"         then empty
              elif .type == "command_execution" then "\n  . " + ((.command // "command") | tostring | .[0:120]) + "\n"
              elif .type == "file_change"       then "\n  . edit " + ((.path // "") | tostring) + "\n"
              elif .type == "error"             then "\n  ! " + ((.message // "error") | tostring) + "\n"
              else empty end )
        elif .type == "turn.completed" then
          ( .usage
            | "\n\n[turn] in=" + ((.input_tokens // 0) | tostring)
              + " out=" + ((.output_tokens // 0) | tostring) + " tokens\n" )
        elif .type == "turn.failed" then
          "\n\n[failed] " + ((.error.message // "turn failed") | tostring) + "\n"
        else empty end' 2>/dev/null
  else
    cat
  fi
}

# Sum one usage field across a codex transcript, skipping whatever is not an
# event.
codex_usage() {
  jq -R -r --arg field "$1" '
    (try fromjson catch null)
    | select(. != null and .type == "turn.completed")
    | (.usage[$field] // empty)' "$2" 2>/dev/null \
    | paste -sd+ -
}

# What the iteration cost, added to the running totals. Anthropic reports USD
# per turn; codex on a ChatGPT login reports tokens and no price, so the spend
# ceiling can only police the Anthropic half of a run. Reporting tokens is
# honest; inventing a dollar figure for them would not be.
account() {
  local provider="$1" log="$2" cost tin tout
  [ "$USE_JQ" = 1 ] || return 0
  case "$provider" in
    codex)
      # -R, not plain jq: codex writes tracing lines to stderr and the log has
      # both streams in it, so a parser that aborts on the first non-JSON line
      # silently accounts for nothing. Found by running it for real.
      tin="$(codex_usage input_tokens  "$log")"
      tout="$(codex_usage output_tokens "$log")"
      [ -n "${tin:-}" ]  && total_in="$((total_in + $(printf '%s' "$tin")))"
      [ -n "${tout:-}" ] && total_out="$((total_out + $(printf '%s' "$tout")))"
      ;;
    *)
      cost="$(jq -r 'select(.type == "result") | (.total_cost_usd // empty)' "$log" 2>/dev/null | tail -1)"
      [ -n "${cost:-}" ] && total_cost="$(awk -v a="$total_cost" -v b="$cost" 'BEGIN { printf "%.4f", a + b }')"
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Reading the iteration back
# ---------------------------------------------------------------------------

# Done means the agent said so in its final message, whichever provider wrote
# it.
completed() {
  grep -qF "$SIGIL" "$1" 2>/dev/null
}

# The failure signature the orchestrator emits when it gives up on a task. The
# same string three times running means two agents are trading one bug back and
# forth, which is the most expensive way for this loop to achieve nothing.
blocked_signature() {
  sed -n 's/.*<blocked>\(.*\)<\/blocked>.*/\1/p' "$1" 2>/dev/null \
    | head -1 \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed 's/^ *//; s/ *$//' \
    | cut -c1-200
}

# Did this iteration die because the provider cut us off, rather than because
# the agent is broken? Only asked of an iteration that already failed: the
# words appearing in a transcript that otherwise succeeded mean the agent was
# talking about limits, not hitting one.
limit_hit() {
  LC_ALL=C grep -qaiE "$LIMIT_PATTERN" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Handover
# ---------------------------------------------------------------------------
# Switching providers mid-run is a one-way door. Codex does not hand the loop
# back: a run that ping-ponged between providers would make the three-attempt
# budget meaningless, since each side would keep granting the other a fresh
# three.
switch_provider() {
  local reason="$1" target="$FALLBACK" bin prompt

  [ "$target" != "off" ] || return 1
  [ "$PROVIDER" != "$target" ] || return 1

  bin="$(provider_binary "$target")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    warn "would hand over to $target, but '$bin' is not installed in the sandbox"
    return 1
  fi

  prompt="$(provider_prompt_file "$target")"
  if [ ! -f "$prompt" ]; then
    warn "would hand over to $target, but $prompt is missing -- run 'ralph init' on the host"
    return 1
  fi

  say "handing the loop to $target: $reason"
  say "$target runs one session playing all four roles, on $CODEX_MODEL ($CODEX_EFFORT effort)"
  [ -n "$MAX_COST" ] && warn "the \$$MAX_COST ceiling only counts Anthropic spend; $target reports tokens, not dollars"

  PROVIDER="$target"
  PROMPT="$(cat "$prompt")"
  handover="${handover:+$handover; }$reason -> $target at iteration $iteration"

  # The incoming provider gets its own clean slate on every counter it could
  # have inherited. It has not failed yet, it has not stalled yet, and it has
  # not spent any of the three attempts -- which is the point of handing it a
  # wall the other one could not get over.
  fails=0
  repeats=0
  stalls=0
  last_signature=""
  return 0
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
    printf '"provider":"%s",'       "$(json_escape "$PROVIDER")"
    printf '"started_on":"%s",'     "$(json_escape "$started_on")"
    printf '"handover":"%s",'       "$(json_escape "${handover:-}")"
    printf '"iterations":%s,'       "$iteration"
    printf '"cost_usd":"%s",'       "$total_cost"
    printf '"tokens_in":%s,'        "$total_in"
    printf '"tokens_out":%s,'       "$total_out"
    printf '"elapsed_seconds":%s,'  "$elapsed"
    printf '"workspace":"%s",'      "$(json_escape "${RALPH_PROJECT:-/workspace}")"
    printf '"finished_at":"%s"}\n'  "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$ALERT_JSON"
  {
    printf 'ralph loop: %s\n' "$reason"
    printf '%s  |  %s iteration(s)  |  %sm%ss  |  $%s%s\n' \
      "${RALPH_PROJECT:-/workspace}" "$iteration" \
      "$((elapsed / 60))" "$((elapsed % 60))" "$total_cost" \
      "$([ "$total_out" -gt 0 ] && printf ' + %s codex tokens' "$((total_in + total_out))")"
    printf 'provider: %s\n' \
      "$([ -n "${handover:-}" ] && printf '%s (started on %s; %s)' "$PROVIDER" "$started_on" "$handover" || printf '%s' "$PROVIDER")"
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
total_in=0
total_out=0
handover=""
started_on="$PROVIDER"
started="$(date +%s)"

summary() {
  local elapsed=$(($(date +%s) - started))
  say "$iteration iteration(s), $((elapsed / 60))m$((elapsed % 60))s, cost \$$total_cost"
  [ "$total_out" -gt 0 ] && say "codex used $total_in in / $total_out out tokens (no per-turn price is reported)"
  [ -n "$handover" ] && say "provider handover: $handover"
  say "transcripts in $LOG_DIR"
}
trap 'printf "\n"; warn "interrupted"; finish 130 "interrupted by hand"' INT

PROMPT_FILE_IN_USE="$(provider_prompt_file "$PROVIDER")"
[ -f "$PROMPT_FILE_IN_USE" ] \
  || die "no $PROMPT_FILE_IN_USE here -- run 'ralph init' on the host first"
command -v "$(provider_binary "$PROVIDER")" >/dev/null 2>&1 \
  || die "agent not found: $(provider_binary "$PROVIDER")"

mkdir -p "$LOG_DIR"
rm -f "$ALERT_JSON" "$ALERT_TXT"
PROMPT="$(cat "$PROMPT_FILE_IN_USE")"

while [ "$MAX" -eq 0 ] || [ "$iteration" -lt "$MAX" ]; do
  iteration=$((iteration + 1))
  stamp="$(date +%Y%m%d-%H%M%S)"
  log="$LOG_DIR/$(printf '%03d' "$iteration")-$stamp.jsonl"
  last="$LOG_DIR/$(printf '%03d' "$iteration")-$stamp.last.txt"

  if [ "$MAX" -eq 0 ]; then
    say "iteration $iteration  [$PROVIDER]  ($stamp)"
  else
    say "iteration $iteration/$MAX  [$PROVIDER]  ($stamp)"
  fi

  rc=0
  run_iteration "$PROVIDER" "$log" "$last" || rc=$?
  account "$PROVIDER" "$log"

  if [ "$rc" -ne 0 ]; then
    # A provider that has cut us off is not a broken agent, and waiting for
    # FAIL_LIMIT of them just burns the wait. Hand over on the first one.
    if limit_hit "$log" && switch_provider "$PROVIDER hit its usage limit"; then
      [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
      continue
    fi

    fails=$((fails + 1))
    warn "iteration $iteration exited $rc (consecutive failure $fails/$FAIL_LIMIT)"
    if [ "$fails" -ge "$FAIL_LIMIT" ]; then
      if switch_provider "$PROVIDER failed $fails times running"; then
        [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
        continue
      fi
      warn "the agent is not running; see $log"
      finish 1 "the agent failed $fails times running" "last exit code $rc; transcript $log"
    fi
    [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
    continue
  fi
  fails=0

  if completed "$last"; then
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
  signature="$(blocked_signature "$last")"
  if [ -n "$signature" ]; then
    if [ "$signature" = "$last_signature" ]; then
      repeats=$((repeats + 1))
    else
      repeats=1
    fi
    last_signature="$signature"
    warn "iteration $iteration ended blocked ($repeats/$REPEAT_LIMIT): $signature"
    if [ "$repeats" -ge "$REPEAT_LIMIT" ]; then
      # Three strikes is where a second set of eyes is worth most: the wall is
      # real, well documented in the progress log, and the other provider has
      # not yet had a theory about it. It then gets its own three, and no more.
      if switch_provider "three attempts spent on: $signature"; then
        [ "$SLEEP" -gt 0 ] && sleep "$SLEEP"
        continue
      fi
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
