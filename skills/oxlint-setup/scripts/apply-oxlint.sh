#!/usr/bin/env bash
# Copy standard oxlint plugin (14 custom rules + tests), .oxlintrc.json, and .oxfmtrc.json
# into a target repository.
set -euo pipefail

TARGET="."
FORCE=0

usage() {
  cat <<'EOF'
Usage:
  apply-oxlint.sh [--repo <path>] [--force]

Copies:
  assets/oxlint/        -> <repo>/tooling/oxlint/
  assets/.oxlintrc.json -> <repo>/.oxlintrc.json
  assets/.oxfmtrc.json  -> <repo>/.oxfmtrc.json
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires a path." >&2; exit 1; }
      TARGET="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"
TARGET_ROOT="$(cd "$TARGET" && pwd)"

copy_file() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && "$FORCE" -ne 1 ]]; then
    echo "Skipped existing file (pass --force to overwrite): $dst"
    return 0
  fi
  cp "$src" "$dst"
  echo "Copied $dst"
}

if [[ -d "$TARGET_ROOT/tooling/oxlint" && "$FORCE" -ne 1 ]]; then
  echo "Skipped existing directory (pass --force to overwrite): $TARGET_ROOT/tooling/oxlint"
else
  mkdir -p "$TARGET_ROOT/tooling"
  rm -rf "$TARGET_ROOT/tooling/oxlint"
  cp -R "$ASSETS_DIR/oxlint" "$TARGET_ROOT/tooling/oxlint"
  echo "Copied $TARGET_ROOT/tooling/oxlint"
fi

copy_file "$ASSETS_DIR/.oxlintrc.json" "$TARGET_ROOT/.oxlintrc.json"
copy_file "$ASSETS_DIR/.oxfmtrc.json" "$TARGET_ROOT/.oxfmtrc.json"
