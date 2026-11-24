#!/usr/bin/env bash
# Deterministic task gate and hook adapter for zstack-mode (pure Bash).
# Tracks task state in <git-dir>/zstack-state.json, verifies code-review and
# .changes-verification-receipt.json match HEAD, and adapts Antigravity,
# Claude Code, and Git pre-push hooks.
set -euo pipefail

REPO="."
VERIFICATION_RECEIPT=".changes-verification-receipt.json"

usage() {
  cat <<'EOF'
Usage:
  zstack_gate.sh [--repo <path>] start --task "<summary>" [--backward-compat]
  zstack_gate.sh [--repo <path>] record-review --status pass|fail [--summary "<text>"]
  zstack_gate.sh [--repo <path>] check
  zstack_gate.sh [--repo <path>] check-cmd "<command>"
  zstack_gate.sh [--repo <path>] complete
  zstack_gate.sh [--repo <path>] status
  zstack_gate.sh [--repo <path>] stop-hook
  zstack_gate.sh [--repo <path>] pre-tool-hook
  zstack_gate.sh [--repo <path>] claude-pre-tool
  zstack_gate.sh [--repo <path>] agy-pre-tool
EOF
}

json_escape() {
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      if (NR > 1) printf "\\n"
      printf "%s", $0
    }
  '
}

json_get_str() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // ""' "$file" 2>/dev/null || true
  else
    awk -v k="$key" '
      index($0, "\"" k "\"") > 0 {
        line = $0
        sub(/^[^:]*:[[:space:]]*/, "", line)
        if (substr(line, 1, 1) == "\"") {
          sub(/^"/, "", line)
          sub(/"[[:space:]]*,?[[:space:]]*$/, "", line)
          print line
        }
        exit
      }
    ' "$file"
  fi
}

json_get_bool() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || { printf 'false'; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" 'if .[$k] == true then "true" else "false" end' "$file" 2>/dev/null || printf 'false'
  else
    awk -v k="$key" '
      index($0, "\"" k "\"") > 0 {
        if ($0 ~ /:[[:space:]]*true([[:space:]]*,?[[:space:]]*)?$/) val = "true"
      }
      END { print (val == "true" ? "true" : "false") }
    ' "$file"
  fi
}

state_path_for() {
  local repo="$1"
  local git_dir
  if git_dir="$(git -C "$repo" rev-parse --git-dir 2>/dev/null)" && [[ -n "$git_dir" ]]; then
    if [[ "$git_dir" != /* ]]; then
      git_dir="$(cd "$repo/$git_dir" && pwd)"
    fi
    printf '%s/zstack-state.json' "$git_dir"
  else
    printf '%s/.zstack-state.json' "$repo"
  fi
}

git_head() {
  git -C "$1" rev-parse HEAD 2>/dev/null || true
}

write_state() {
  local target="$1" task="$2" phase="$3" compat="$4" started="$5" rev_status="$6" rev_sha="$7" rev_summary="$8"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
{
  "task": "$(json_escape "$task")",
  "phase": "$(json_escape "$phase")",
  "backward_compatible": ${compat},
  "started_at_utc": "$(json_escape "$started")",
  "updated_at_utc": "${now}",
  "code_review_status": "$(json_escape "$rev_status")",
  "code_review_commit_sha": "$(json_escape "$rev_sha")",
  "code_review_summary": "$(json_escape "$rev_summary")"
}
EOF
}

GATE_ISSUES=()
evaluate_gates() {
  local repo="$1"
  GATE_ISSUES=()
  local st
  st="$(state_path_for "$repo")"
  if [[ ! -f "$st" ]]; then
    GATE_ISSUES+=("No active zstack-mode task state. Run \`zstack_gate.sh start --task \"...\"\` first.")
    return 1
  fi

  local head
  head="$(git_head "$repo")"
  if [[ -z "$head" ]]; then
    GATE_ISSUES+=("Repository has no valid HEAD commit.")
    return 1
  fi

  local rev_status rev_sha
  rev_status="$(json_get_str "$st" "code_review_status")"
  rev_sha="$(json_get_str "$st" "code_review_commit_sha")"
  if [[ "$rev_status" != "pass" ]]; then
    GATE_ISSUES+=("\`code-review\` gate not passed. Delegate review to an independent subagent and record pass.")
  elif [[ "$rev_sha" != "$head" ]]; then
    GATE_ISSUES+=("\`code-review\` receipt is stale (${rev_sha} != HEAD ${head}). Re-run \`code-review\` and record pass on HEAD.")
  fi

  local receipt="$repo/$VERIFICATION_RECEIPT"
  if [[ ! -f "$receipt" ]]; then
    GATE_ISSUES+=("Missing ${VERIFICATION_RECEIPT}. Run \`changes-verification\` (\`verify.sh\`) on HEAD.")
  else
    local r_passed r_sha
    r_passed="$(json_get_bool "$receipt" "passed")"
    r_sha="$(json_get_str "$receipt" "commit_sha")"
    if [[ "$r_passed" != "true" ]]; then
      GATE_ISSUES+=("\`changes-verification\` did not pass. Fix failures and re-run \`verify.sh\`.")
    elif [[ "$r_sha" != "$head" ]]; then
      GATE_ISSUES+=("\`changes-verification\` receipt is stale (${r_sha} != HEAD ${head}). Re-run \`changes-verification\` on HEAD.")
    fi
  fi

  (( ${#GATE_ISSUES[@]} == 0 ))
}

matches_pr_or_push() {
  printf '%s' "$1" | grep -Eq '(^|[[:space:]&;|])(git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)($|[[:space:]&;|])'
}

extract_stdin_field() {
  local raw="$1" jq_expr="$2" fallback_key="$3"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r "$jq_expr // \"\"" 2>/dev/null || true
  else
    printf '%s' "$raw" | awk -v k="$fallback_key" '
      {
        pat = "\"" k "\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
        if (match($0, pat)) {
          s = substr($0, RSTART, RLENGTH)
          sub(/^[^:]*:[[:space:]]*"/, "", s)
          sub(/"$/, "", s)
          print s
          exit
        }
      }
    '
  fi
}

cmd_start() {
  local task="" compat="false"
  while (( $# > 0 )); do
    case "$1" in
      --task)
        [[ $# -ge 2 ]] || { echo "Error: --task requires a value." >&2; exit 1; }
        task="$2"
        shift 2
        ;;
      --backward-compat)
        compat="true"
        shift
        ;;
      *)
        echo "Error: unknown option '$1'." >&2
        exit 1
        ;;
    esac
  done
  [[ -n "$task" ]] || { echo "Error: --task is required." >&2; exit 1; }

  local st now compat_label
  st="$(state_path_for "$REPO_ROOT")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_state "$st" "$task" "implementing" "$compat" "$now" "" "" ""
  compat_label="no (default)"
  [[ "$compat" == "true" ]] && compat_label="yes"
  printf 'Started zstack-mode task: %s (backward_compatible=%s)\n' "$task" "$compat_label"
}

cmd_record_review() {
  local status="" summary=""
  while (( $# > 0 )); do
    case "$1" in
      --status)
        [[ $# -ge 2 ]] || { echo "Error: --status requires pass|fail." >&2; exit 1; }
        status="$2"
        shift 2
        ;;
      --summary)
        [[ $# -ge 2 ]] || { echo "Error: --summary requires a value." >&2; exit 1; }
        summary="$2"
        shift 2
        ;;
      *)
        echo "Error: unknown option '$1'." >&2
        exit 1
        ;;
    esac
  done
  case "$status" in
    pass|fail) ;;
    *) echo "Error: --status must be pass or fail." >&2; exit 1 ;;
  esac

  local st head
  st="$(state_path_for "$REPO_ROOT")"
  [[ -f "$st" ]] || { echo "Error: no active zstack-mode task state. Run \`start\` first." >&2; exit 1; }
  head="$(git_head "$REPO_ROOT")"
  [[ -n "$head" ]] || { echo "Error: repository has no valid HEAD commit." >&2; exit 1; }

  local task phase compat started
  task="$(json_get_str "$st" "task")"
  phase="$(json_get_str "$st" "phase")"
  compat="$(json_get_bool "$st" "backward_compatible")"
  started="$(json_get_str "$st" "started_at_utc")"
  [[ "$status" == "pass" ]] && phase="reviewed"

  write_state "$st" "$task" "$phase" "$compat" "$started" "$status" "$head" "$summary"
  printf 'Recorded code-review=%s for HEAD %s\n' "$status" "$head"
}

cmd_check() {
  if ! evaluate_gates "$REPO_ROOT"; then
    local item
    for item in "${GATE_ISSUES[@]}"; do
      printf 'BLOCKED: %s\n' "$item" >&2
    done
    exit 1
  fi

  local st task compat started rev_status rev_sha rev_summary head
  st="$(state_path_for "$REPO_ROOT")"
  head="$(git_head "$REPO_ROOT")"
  task="$(json_get_str "$st" "task")"
  compat="$(json_get_bool "$st" "backward_compatible")"
  started="$(json_get_str "$st" "started_at_utc")"
  rev_status="$(json_get_str "$st" "code_review_status")"
  rev_sha="$(json_get_str "$st" "code_review_commit_sha")"
  rev_summary="$(json_get_str "$st" "code_review_summary")"
  write_state "$st" "$task" "awaiting_pr_approval" "$compat" "$started" "$rev_status" "$rev_sha" "$rev_summary"
  printf 'PASSED: All zstack-mode gates verified for HEAD %s. Ready to ask user about PR.\n' "$head"
}

cmd_complete() {
  local st
  st="$(state_path_for "$REPO_ROOT")"
  if [[ -f "$st" ]]; then
    local task compat started rev_status rev_sha rev_summary
    task="$(json_get_str "$st" "task")"
    compat="$(json_get_bool "$st" "backward_compatible")"
    started="$(json_get_str "$st" "started_at_utc")"
    rev_status="$(json_get_str "$st" "code_review_status")"
    rev_sha="$(json_get_str "$st" "code_review_commit_sha")"
    rev_summary="$(json_get_str "$st" "code_review_summary")"
    write_state "$st" "$task" "awaiting_task" "$compat" "$started" "$rev_status" "$rev_sha" "$rev_summary"
  fi
  echo "Task closed. zstack-mode phase set to awaiting_task."
}

cmd_status() {
  local st
  st="$(state_path_for "$REPO_ROOT")"
  if [[ ! -f "$st" ]]; then
    echo "No active zstack-mode state."
  else
    cat "$st"
  fi
}

cmd_check_cmd() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]] || ! matches_pr_or_push "$cmd"; then
    exit 0
  fi
  local st phase
  st="$(state_path_for "$REPO_ROOT")"
  [[ -f "$st" ]] || exit 0
  phase="$(json_get_str "$st" "phase")"
  [[ "$phase" == "awaiting_task" ]] && exit 0
  if evaluate_gates "$REPO_ROOT"; then
    exit 0
  fi
  printf 'zstack-mode blocked git push / PR creation:\n' >&2
  local item
  for item in "${GATE_ISSUES[@]}"; do
    printf -- '- %s\n' "$item" >&2
  done
  exit 2
}

cmd_stop_hook() {
  local raw="" cwd="" target_repo="$REPO_ROOT" st phase
  if [[ ! -t 0 ]]; then
    raw="$(cat || true)"
    cwd="$(extract_stdin_field "$raw" '.cwd' 'cwd')"
    [[ -n "$cwd" ]] && target_repo="$cwd"
  fi
  st="$(state_path_for "$target_repo")"
  [[ -f "$st" ]] || exit 0
  phase="$(json_get_str "$st" "phase")"
  if [[ "$phase" == "awaiting_task" || "$phase" == "awaiting_pr_approval" ]]; then
    exit 0
  fi
  if evaluate_gates "$target_repo"; then
    exit 0
  fi
  printf 'zstack-mode Stop gate blocked completion:\n' >&2
  local item
  for item in "${GATE_ISSUES[@]}"; do
    printf -- '- %s\n' "$item" >&2
  done
  exit 2
}

cmd_pre_tool_hook() {
  local raw cmd cwd target_repo st phase
  raw="$(cat || true)"
  cmd="$(extract_stdin_field "$raw" '.tool_input.command' 'command')"
  cwd="$(extract_stdin_field "$raw" '.cwd' 'cwd')"
  target_repo="${cwd:-$REPO_ROOT}"
  if [[ -n "$cmd" ]] && ! matches_pr_or_push "$cmd"; then
    exit 0
  fi
  st="$(state_path_for "$target_repo")"
  [[ -f "$st" ]] || exit 0
  phase="$(json_get_str "$st" "phase")"
  [[ "$phase" == "awaiting_task" ]] && exit 0
  if evaluate_gates "$target_repo"; then
    exit 0
  fi
  printf 'zstack-mode blocked git push / PR creation:\n' >&2
  local item
  for item in "${GATE_ISSUES[@]}"; do
    printf -- '- %s\n' "$item" >&2
  done
  exit 2
}

cmd_agy_pre_tool() {
  local raw cmd cwd target_repo st phase
  raw="$(cat || true)"
  cmd="$(extract_stdin_field "$raw" '.toolCall.args.CommandLine' 'CommandLine')"
  cwd="$(extract_stdin_field "$raw" '.cwd' 'cwd')"
  target_repo="${cwd:-$REPO_ROOT}"

  if ! matches_pr_or_push "$cmd"; then
    printf '{"decision": "allow"}\n'
    exit 0
  fi
  st="$(state_path_for "$target_repo")"
  if [[ ! -f "$st" ]]; then
    printf '{"decision": "allow"}\n'
    exit 0
  fi
  phase="$(json_get_str "$st" "phase")"
  if [[ "$phase" == "awaiting_task" ]]; then
    printf '{"decision": "allow"}\n'
    exit 0
  fi
  if evaluate_gates "$target_repo"; then
    printf '{"decision": "allow"}\n'
    exit 0
  fi

  local joined="" item
  for item in "${GATE_ISSUES[@]}"; do
    joined="${joined:+${joined} | }${item}"
  done
  printf '{"decision": "deny", "reason": "zstack-mode gate incomplete: %s"}\n' "$(json_escape "$joined")"
}

while (( $# > 0 )); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires a path." >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    start|record-review|check|check-cmd|complete|status|stop-hook|pre-tool-hook|claude-pre-tool|agy-pre-tool)
      SUBCMD="$1"
      shift
      break
      ;;
    *)
      echo "Error: unknown command '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "${SUBCMD:-}" ]] || { usage >&2; exit 1; }
REPO_ROOT="$(cd "$REPO" && pwd)"

case "$SUBCMD" in
  start) cmd_start "$@" ;;
  record-review) cmd_record_review "$@" ;;
  check) cmd_check "$@" ;;
  check-cmd) cmd_check_cmd "$@" ;;
  complete) cmd_complete "$@" ;;
  status) cmd_status "$@" ;;
  stop-hook) cmd_stop_hook "$@" ;;
  pre-tool-hook|claude-pre-tool) cmd_pre_tool_hook "$@" ;;
  agy-pre-tool) cmd_agy_pre_tool "$@" ;;
esac
