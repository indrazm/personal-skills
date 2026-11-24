#!/usr/bin/env bash
# Deterministic pre-PR changes verification runner.
# Inspects git state, changed files, and CI definitions, runs all specified
# test/CI commands, and writes .changes-verification-receipt.json tied to HEAD.
set -euo pipefail

REPO="."
BASE_REF=""
STRICT=0
DISCOVER_ONLY=0
COMMANDS=()

usage() {
  cat <<'EOF'
Usage:
  verify.sh [--repo <path>] [--base <ref>] [--strict] [--discover-only] [--cmd "<command>"]...
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

json_string_array() {
  local first=1
  local item
  printf '['
  for item in "$@"; do
    if (( first )); then
      first=0
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

while (( $# > 0 )); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires a path." >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || { echo "Error: --base requires a git ref." >&2; exit 1; }
      BASE_REF="$2"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --discover-only)
      DISCOVER_ONLY=1
      shift
      ;;
    --cmd)
      [[ $# -ge 2 ]] || { echo "Error: --cmd requires a command string." >&2; exit 1; }
      COMMANDS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$REPO" && pwd)"

if ! HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
  echo "Error: not inside a valid git repository with commits." >&2
  exit 1
fi

DIRTY_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ "$trimmed" == "?? .changes-verification-receipt.json" ]] && continue
  DIRTY_FILES+=("$line")
done < <(git -C "$REPO_ROOT" status --short)

if [[ -z "$BASE_REF" ]]; then
  for candidate in origin/main main origin/master master; do
    if git -C "$REPO_ROOT" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      BASE_REF="$candidate"
      break
    fi
  done
fi

CHANGED_FILES=()
if [[ -n "$BASE_REF" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && CHANGED_FILES+=("$f")
  done < <(git -C "$REPO_ROOT" diff --name-only "${BASE_REF}...HEAD" 2>/dev/null || true)
else
  if git -C "$REPO_ROOT" rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    while IFS= read -r f; do
      [[ -n "$f" ]] && CHANGED_FILES+=("$f")
    done < <(git -C "$REPO_ROOT" diff --name-only "HEAD~1..HEAD" 2>/dev/null || true)
  else
    while IFS= read -r f; do
      [[ -n "$f" ]] && CHANGED_FILES+=("$f")
    done < <(git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true)
  fi
fi

CI_FILES=()
CI_COMMANDS=()

if [[ -d "$REPO_ROOT/.github/workflows" ]]; then
  for wf in "$REPO_ROOT/.github/workflows"/*.yml "$REPO_ROOT/.github/workflows"/*.yaml; do
    [[ -f "$wf" ]] || continue
    wf_name="$(basename "$wf")"
    CI_FILES+=(".github/workflows/$wf_name")
    while IFS= read -r cmd_line; do
      [[ -n "$cmd_line" ]] && CI_COMMANDS+=("[$wf_name] $cmd_line")
    done < <(awk '
      function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
      function rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
      function indent_of(s,    m) {
        match(s, /^[ ]*/)
        return RLENGTH
      }
      {
        line = $0
        sub(/\r$/, "", line)
        if (in_block) {
          trimmed = ltrim(rtrim(line))
          if (trimmed == "") next
          ind = indent_of(line)
          if (ind <= base_indent) {
            if (block != "") print block
            block = ""
            in_block = 0
          } else {
            if (substr(trimmed, 1, 1) != "#") {
              block = (block == "" ? trimmed : block " && " trimmed)
            }
            next
          }
        }
        if (line ~ /^[ ]*(-[ ]+)?run:[ ]*/) {
          base_indent = indent_of(line)
          cmd = line
          sub(/^[ ]*(-[ ]+)?run:[ ]*/, "", cmd)
          cmd = rtrim(cmd)
          if (cmd ~ /^(\||\|-|\|\+|>|>-|>\+)$/) {
            in_block = 1
            block = ""
          } else if (cmd != "") {
            print cmd
          }
        }
      }
      END {
        if (in_block && block != "") print block
      }
    ' "$wf")
  done
fi

for rel in .gitlab-ci.yml .circleci/config.yml Makefile pyproject.toml; do
  if [[ -f "$REPO_ROOT/$rel" ]]; then
    CI_FILES+=("$rel")
  fi
done

if [[ -f "$REPO_ROOT/package.json" ]]; then
  CI_FILES+=("package.json")
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && CI_COMMANDS+=("$entry")
    done < <(jq -r '
      (.scripts // {}) | to_entries[]
      | select(.key | test("test|lint|type|check|build"))
      | "[package.json:\(.key)] \(.value)"
    ' "$REPO_ROOT/package.json" 2>/dev/null || true)
  else
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && CI_COMMANDS+=("$entry")
    done < <(awk '
      /"scripts"[[:space:]]*:/ { in_scripts = 1; next }
      in_scripts && /^[[:space:]]*}/ { in_scripts = 0; next }
      in_scripts && /"[^"]*(test|lint|type|check|build)[^"]*"[[:space:]]*:[[:space:]]*"/ {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        key = line
        sub(/".*$/, "", key)
        val = line
        sub(/^[^"]*":[[:space:]]*"/, "", val)
        sub(/"[[:space:]]*,?[[:space:]]*$/, "", val)
        printf "[package.json:%s] %s\n", key, val
      }
    ' "$REPO_ROOT/package.json")
  fi
fi

printf 'HEAD SHA: %s\n' "$HEAD_SHA"
printf 'Base Ref: %s\n' "${BASE_REF:-N/A}"
printf 'Dirty Working Tree Items: %d\n' "${#DIRTY_FILES[@]}"
printf 'Changed Files (%d):\n' "${#CHANGED_FILES[@]}"
for f in "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}"; do
  printf '  - %s\n' "$f"
done

if (( ${#CI_FILES[@]} > 0 )); then
  ci_joined="$(IFS=', '; printf '%s' "${CI_FILES[*]}")"
  printf 'CI Files Found (%d): %s\n' "${#CI_FILES[@]}" "$ci_joined"
else
  printf 'CI Files Found (0): None\n'
fi

if (( ${#CI_COMMANDS[@]} > 0 )); then
  printf 'Extracted CI / Script Commands:\n'
  for c in "${CI_COMMANDS[@]}"; do
    printf '  - %s\n' "$c"
  done
fi

if (( DISCOVER_ONLY )); then
  exit 0
fi

if (( STRICT )) && (( ${#DIRTY_FILES[@]} > 0 )); then
  echo "Error: --strict enabled and working tree has uncommitted changes." >&2
  exit 1
fi

if (( ${#COMMANDS[@]} == 0 )); then
  echo "Error: at least one --cmd check must be provided." >&2
  exit 1
fi

ALL_PASSED=1
CHECK_JSON_ITEMS=()

for cmd in "${COMMANDS[@]}"; do
  printf '\n>>> Running: %s\n' "$cmd"
  set +e
  (cd "$REPO_ROOT" && sh -c "$cmd")
  rc=$?
  set -e
  if (( rc == 0 )); then
    passed_bool="true"
    printf '<<< PASSED: %s\n' "$cmd"
  else
    passed_bool="false"
    ALL_PASSED=0
    printf '<<< FAILED (exit %d): %s\n' "$rc" "$cmd" >&2
  fi
  CHECK_JSON_ITEMS+=("    {\"command\": \"$(json_escape "$cmd")\", \"exit_code\": ${rc}, \"passed\": ${passed_bool}}")
done

TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIRTY_BOOL="false"
(( ${#DIRTY_FILES[@]} > 0 )) && DIRTY_BOOL="true"
PASSED_BOOL="false"
(( ALL_PASSED == 1 )) && PASSED_BOOL="true"

BASE_REF_JSON="null"
if [[ -n "$BASE_REF" ]]; then
  BASE_REF_JSON="\"$(json_escape "$BASE_REF")\""
fi

CHANGED_JSON="$(json_string_array "${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}")"
CI_FILES_JSON="$(json_string_array "${CI_FILES[@]+"${CI_FILES[@]}"}")"

RECEIPT_PATH="$REPO_ROOT/.changes-verification-receipt.json"
{
  printf '{\n'
  printf '  "commit_sha": "%s",\n' "$(json_escape "$HEAD_SHA")"
  printf '  "base_ref": %s,\n' "$BASE_REF_JSON"
  printf '  "timestamp_utc": "%s",\n' "$TIMESTAMP_UTC"
  printf '  "dirty_tree": %s,\n' "$DIRTY_BOOL"
  printf '  "changed_files": %s,\n' "$CHANGED_JSON"
  printf '  "ci_files_found": %s,\n' "$CI_FILES_JSON"
  printf '  "executed_checks": [\n'
  idx=0
  total="${#CHECK_JSON_ITEMS[@]}"
  for entry in "${CHECK_JSON_ITEMS[@]}"; do
    idx=$((idx + 1))
    if (( idx < total )); then
      printf '%s,\n' "$entry"
    else
      printf '%s\n' "$entry"
    fi
  done
  printf '  ],\n'
  printf '  "passed": %s\n' "$PASSED_BOOL"
  printf '}\n'
} > "$RECEIPT_PATH"

printf '\nWrote receipt: %s (passed=%s)\n' "$RECEIPT_PATH" "$PASSED_BOOL"
(( ALL_PASSED == 1 )) && exit 0 || exit 1
