#!/usr/bin/env bash
# Git pre-push hook enforcing changes-verification receipt for HEAD.
set -euo pipefail

RECEIPT_FILE=".changes-verification-receipt.json"
HEAD_SHA="$(git rev-parse HEAD)"

if [[ ! -f "$RECEIPT_FILE" ]]; then
  echo "ERROR: Missing $RECEIPT_FILE. Run changes-verification before pushing." >&2
  exit 1
fi

python3 - "$RECEIPT_FILE" "$HEAD_SHA" << 'EOF'
import json
import sys

receipt_path, head_sha = sys.argv[1], sys.argv[2]
try:
    data = json.loads(open(receipt_path, encoding="utf-8").read())
except Exception as exc:
    print(f"ERROR: Could not parse {receipt_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if data.get("commit_sha") != head_sha:
    print(
        f"ERROR: Verification receipt is for {data.get('commit_sha')}, "
        f"but HEAD is {head_sha}. Re-run changes-verification.",
        file=sys.stderr,
    )
    sys.exit(1)

if data.get("passed") is not True:
    print("ERROR: Changes verification did not pass. Fix failures and re-run.", file=sys.stderr)
    sys.exit(1)

print(f"Changes verification receipt confirmed for {head_sha}.")
EOF
