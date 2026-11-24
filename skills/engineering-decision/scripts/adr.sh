#!/usr/bin/env bash
# Deterministic helper for listing and scaffolding numbered ADRs in docs/decision/.
set -euo pipefail

DECISION_DIR="docs/decision"

usage() {
  cat <<'EOF'
Usage:
  adr.sh [--dir <path>] list
  adr.sh [--dir <path>] new "<title>" [--status <Status>] [--supersedes "<link>"]

Statuses: Proposed | Accepted | Superseded | Deprecated | Canceled
EOF
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

extract_status() {
  local file="$1"
  local val
  val="$(awk '
    /^[[:space:]]*-[[:space:]]*\*\*Status:\*\*/ {
      sub(/^[[:space:]]*-[[:space:]]*\*\*Status:\*\*[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file")"
  printf '%s' "${val:-Unknown}"
}

extract_title() {
  local file="$1"
  local fallback="$2"
  local val
  val="$(awk '
    /^#[[:space:]]*/ {
      sub(/^#[[:space:]]*([0-9]{4}:[[:space:]]*)?/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$file")"
  printf '%s' "${val:-$fallback}"
}

list_adr_files() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local f base
  for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    printf '%s\n' "$base"
  done | sort
}

next_number() {
  local dir="$1"
  local max_num=0
  local base code num
  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    code="${base%%-*}"
    num=$((10#$code))
    if (( num > max_num )); then
      max_num="$num"
    fi
  done < <(list_adr_files "$dir")
  printf '%04d' "$((max_num + 1))"
}

cmd_list() {
  local count=0
  local base code slug status title
  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    code="${base%%-*}"
    slug="${base#*-}"
    slug="${slug%.md}"
    status="$(extract_status "$DECISION_DIR/$base")"
    title="$(extract_title "$DECISION_DIR/$base" "$slug")"
    printf '%s | %-10s | %s (%s)\n' "$code" "$status" "$title" "$base"
    count=$((count + 1))
  done < <(list_adr_files "$DECISION_DIR")

  local next_code
  next_code="$(next_number "$DECISION_DIR")"
  if (( count == 0 )); then
    printf 'No decision records found in %s. Next number: %s\n' "$DECISION_DIR" "$next_code"
  else
    printf '\nTotal: %d | Next number: %s\n' "$count" "$next_code"
  fi
}

cmd_new() {
  local title=""
  local status="Accepted"
  local supersedes="None"

  while (( $# > 0 )); do
    case "$1" in
      --status)
        [[ $# -ge 2 ]] || { echo "Error: --status requires a value." >&2; exit 1; }
        status="$2"
        shift 2
        ;;
      --supersedes)
        [[ $# -ge 2 ]] || { echo "Error: --supersedes requires a value." >&2; exit 1; }
        supersedes="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "Error: unknown option '$1'." >&2
        exit 1
        ;;
      *)
        if [[ -z "$title" ]]; then
          title="$1"
        else
          title="$title $1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$title" ]]; then
    echo "Error: title is required." >&2
    exit 1
  fi

  case "$status" in
    Proposed|Accepted|Superseded|Deprecated|Canceled) ;;
    *)
      echo "Error: invalid status '$status'." >&2
      exit 1
      ;;
  esac

  local slug
  slug="$(slugify "$title")"
  if [[ -z "$slug" ]]; then
    echo "Error: title must produce a non-empty kebab-case slug." >&2
    exit 1
  fi

  local code
  code="$(next_number "$DECISION_DIR")"
  mkdir -p "$DECISION_DIR"
  local target="$DECISION_DIR/${code}-${slug}.md"
  if [[ -e "$target" ]]; then
    echo "Error: file already exists: $target" >&2
    exit 1
  fi

  local today
  today="$(date +%Y-%m-%d)"
  cat > "$target" <<EOF
# ${code}: ${title}

- **Date:** ${today}
- **Status:** ${status}
- **Supersedes:** ${supersedes}
- **Superseded by:** None
- **Related:** None

## Context

Describe the problem, technical constraints, and relevant prior decisions.

## Decision

State the chosen approach clearly and explain why it was selected.

## Alternatives Considered

- **Option A:** Brief summary and why it was not chosen.
- **Option B:** Brief summary and why it was not chosen.

## Consequences

- **Positive:** Expected benefits and improvements.
- **Negative / Trade-offs:** Costs, complexity, or follow-up work required.
EOF

  printf 'Created %s\n' "$target"
}

while (( $# > 0 )); do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || { echo "Error: --dir requires a path." >&2; exit 1; }
      DECISION_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    list)
      shift
      cmd_list "$@"
      exit 0
      ;;
    new)
      shift
      cmd_new "$@"
      exit 0
      ;;
    *)
      echo "Error: unknown command '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

usage >&2
exit 1
