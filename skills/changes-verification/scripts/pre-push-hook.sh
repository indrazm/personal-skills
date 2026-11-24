#!/usr/bin/env bash
# Git pre-push hook enforcing changes-verification receipt for HEAD (pure Bash).
set -euo pipefail

RECEIPT_FILE=".changes-verification-receipt.json"
HEAD_SHA="$(git rev-parse HEAD)"

if [[ ! -f "$RECEIPT_FILE" ]]; then
  echo "ERROR: Missing $RECEIPT_FILE. Run changes-verification before pushing." >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  RECEIPT_SHA="$(jq -r '.commit_sha // ""' "$RECEIPT_FILE" 2>/dev/null || true)"
  RECEIPT_PASSED="$(jq -r 'if .passed == true then "true" else "false" end' "$RECEIPT_FILE" 2>/dev/null || true)"
else
  RECEIPT_SHA="$(awk -F'"' '/"commit_sha"[[:space:]]*:/ { print $4; exit }' "$RECEIPT_FILE")"
  RECEIPT_PASSED="$(awk '/"passed"[[:space:]]*:[[:space:]]*true/ { val="true" } END { print (val == "true" ? "true" : "false") }' "$RECEIPT_FILE")"
fi

if [[ -z "$RECEIPT_SHA" ]]; then
  echo "ERROR: Could not parse commit_sha from $RECEIPT_FILE." >&2
  exit 1
fi

if [[ "$RECEIPT_SHA" != "$HEAD_SHA" ]]; then
  echo "ERROR: Verification receipt is for $RECEIPT_SHA, but HEAD is $HEAD_SHA. Re-run changes-verification." >&2
  exit 1
fi

if [[ "$RECEIPT_PASSED" != "true" ]]; then
  echo "ERROR: Changes verification did not pass. Fix failures and re-run." >&2
  exit 1
fi

echo "Changes verification receipt confirmed for $HEAD_SHA."
