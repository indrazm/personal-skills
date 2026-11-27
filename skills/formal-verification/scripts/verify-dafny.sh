#!/usr/bin/env bash
# Deterministic Dafny verification + soundness audit gate.
# Enforces zero soundness shortcuts (assume, {:axiom}, {:verify false}, {:only})
# and zero `dafny audit` findings before running `dafny verify`.
set -euo pipefail

TIME_LIMIT=30
RESOURCE_LIMIT=""
ISOLATE=0
ALLOW_EXTERN=0
SKIP_AUDIT=0
EXTRA_DAFNY_ARGS=()
TARGETS=()

usage() {
  cat <<'EOF'
Usage:
  verify-dafny.sh [options] <file-or-dir>...

Options:
  --time-limit <seconds>     Verification time limit per assertion batch (default: 30)
  --resource-limit <rlimit>  Deterministic Z3 resource limit (e.g., 10000000)
  --isolate                  Verify each assertion in isolation (--isolate-assertions)
  --allow-extern             Allow {:extern} findings during static check (audit still runs)
  --skip-audit               Skip `dafny audit` (NOT recommended; static checks still run)
  --standard-libraries       Pass --standard-libraries to Dafny
  -h, --help                 Show this help message

Examples:
  verify-dafny.sh verification/
  verify-dafny.sh --resource-limit 10000000 verification/ledger.dfy
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --time-limit)
      [[ $# -ge 2 ]] || { echo "Error: --time-limit requires a value." >&2; exit 1; }
      TIME_LIMIT="$2"
      shift 2
      ;;
    --resource-limit)
      [[ $# -ge 2 ]] || { echo "Error: --resource-limit requires a value." >&2; exit 1; }
      RESOURCE_LIMIT="$2"
      shift 2
      ;;
    --isolate)
      ISOLATE=1
      shift
      ;;
    --allow-extern)
      ALLOW_EXTERN=1
      shift
      ;;
    --skip-audit)
      SKIP_AUDIT=1
      shift
      ;;
    --standard-libraries)
      EXTRA_DAFNY_ARGS+=("--standard-libraries")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if (( ${#TARGETS[@]} == 0 )); then
  echo "Error: specify at least one .dfy file, directory, or dfyconfig.toml." >&2
  usage >&2
  exit 1
fi

if ! command -v dafny >/dev/null 2>&1; then
  echo "Error: 'dafny' CLI not found on PATH." >&2
  echo "Install Dafny 4 (e.g., 'brew install dafny' on macOS or see https://dafny.org/latest/Installation)." >&2
  exit 1
fi

# Collect .dfy files for static soundness scan and verify targets
DFY_FILES=()
VERIFY_INPUTS=()

for target in "${TARGETS[@]}"; do
  if [[ -d "$target" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      DFY_FILES+=("$f")
      VERIFY_INPUTS+=("$f")
    done < <(find "$target" -type f -name '*.dfy' | sort)
  elif [[ -f "$target" ]]; then
    VERIFY_INPUTS+=("$target")
    if [[ "$target" == *.dfy ]]; then
      DFY_FILES+=("$target")
    elif [[ "$(basename "$target")" == "dfyconfig.toml" ]]; then
      dir="$(dirname "$target")"
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        DFY_FILES+=("$f")
      done < <(find "$dir" -type f -name '*.dfy' | sort)
    fi
  else
    echo "Error: target not found: $target" >&2
    exit 1
  fi
done

if (( ${#VERIFY_INPUTS[@]} == 0 )); then
  echo "Error: no .dfy files found in targets." >&2
  exit 1
fi

# Strip // and /* */ comments while preserving line numbers so prose in comments does not trigger false positives.
scan_file_for_shortcuts() {
  local file="$1"
  local allow_extern="$2"
  awk -v file="$file" -v allow_extern="$allow_extern" '
    BEGIN { in_block = 0; issues = 0 }
    {
      line = $0
      out = ""
      i = 1
      n = length(line)
      while (i <= n) {
        c2 = substr(line, i, 2)
        if (in_block) {
          if (c2 == "*/") {
            in_block = 0
            i += 2
          } else {
            i += 1
          }
        } else if (c2 == "/*") {
          in_block = 1
          i += 2
        } else if (c2 == "//") {
          break
        } else {
          out = out substr(line, i, 1)
          i += 1
        }
      }

      if (out ~ /(^|[^A-Za-z0-9_])assume([^A-Za-z0-9_]|$)/) {
        printf "%s:%d: forbidden `assume` statement\n", file, NR > "/dev/stderr"
        issues++
      }
      if (out ~ /\{:axiom\}/) {
        printf "%s:%d: forbidden `{:axiom}` attribute\n", file, NR > "/dev/stderr"
        issues++
      }
      if (out ~ /\{:verify[[:space:]]+false\}/) {
        printf "%s:%d: forbidden `{:verify false}` attribute\n", file, NR > "/dev/stderr"
        issues++
      }
      if (out ~ /\{:only\}/ || out ~ /@VerifyOnly/) {
        printf "%s:%d: forbidden `{:only}` / `@VerifyOnly` attribute\n", file, NR > "/dev/stderr"
        issues++
      }
      if (!allow_extern && out ~ /\{:extern/) {
        printf "%s:%d: `{:extern}` requires explicit --allow-extern opt-in\n", file, NR > "/dev/stderr"
        issues++
      }
    }
    END { exit (issues > 0 ? 1 : 0) }
  ' "$file"
}

echo "[1/3] Static soundness scan (${#DFY_FILES[@]} .dfy file(s))..."
STATIC_FAILED=0
for f in "${DFY_FILES[@]}"; do
  if ! scan_file_for_shortcuts "$f" "$ALLOW_EXTERN"; then
    STATIC_FAILED=1
  fi
done
if (( STATIC_FAILED != 0 )); then
  echo "FAILED: Forbidden proof shortcuts detected. Remove unsound escapes and prove the obligation." >&2
  exit 1
fi
echo "OK: No forbidden shortcuts found."

if (( SKIP_AUDIT == 0 )); then
  echo "[2/3] Running dafny audit (enforcing 0 findings)..."
  AUDIT_CMD=(dafny audit)
  if (( ${#EXTRA_DAFNY_ARGS[@]} > 0 )); then
    AUDIT_CMD+=("${EXTRA_DAFNY_ARGS[@]}")
  fi
  AUDIT_CMD+=("${VERIFY_INPUTS[@]}")

  AUDIT_OUT="$("${AUDIT_CMD[@]}" 2>&1)" || {
    printf '%s\n' "$AUDIT_OUT" >&2
    echo "FAILED: dafny audit exited with an error." >&2
    exit 1
  }

  # Note: `dafny audit` exits 0 even when findings > 0; check findings count explicitly.
  if ! printf '%s\n' "$AUDIT_OUT" | grep -Eq 'Dafny auditor completed with 0 findings'; then
    printf '%s\n' "$AUDIT_OUT" >&2
    echo "FAILED: dafny audit reported soundness findings (expected 0 findings)." >&2
    exit 1
  fi
  echo "OK: dafny audit completed with 0 findings."
else
  echo "[2/3] Skipping dafny audit (--skip-audit)."
fi

echo "[3/3] Running dafny verify..."
VERIFY_CMD=(dafny verify --warn-shadowing --verification-time-limit "$TIME_LIMIT")
if [[ -n "$RESOURCE_LIMIT" ]]; then
  VERIFY_CMD+=(--resource-limit "$RESOURCE_LIMIT")
fi
if (( ISOLATE == 1 )); then
  VERIFY_CMD+=(--isolate-assertions)
fi
if (( ${#EXTRA_DAFNY_ARGS[@]} > 0 )); then
  VERIFY_CMD+=("${EXTRA_DAFNY_ARGS[@]}")
fi
VERIFY_CMD+=("${VERIFY_INPUTS[@]}")

"${VERIFY_CMD[@]}"
echo "PASSED: Soundness audit and Dafny verification succeeded."
