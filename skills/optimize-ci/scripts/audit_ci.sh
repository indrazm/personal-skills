#!/usr/bin/env bash
# Audit the last N GitHub Actions CI runs via `gh` and output a Markdown table
# breaking down every job into Waiting, Setup, and Running durations at p50 and p95.
# Uses `gh`'s built-in `--jq` plus POSIX `awk`/`sort` (zero Python or extra deps).
set -euo pipefail

REPO=""
LIMIT=150
WORKFLOW=""
FROM_TSV=""

usage() {
  cat <<'EOF'
Usage:
  audit_ci.sh [--repo <owner/name>] [--limit <N>] [--workflow <name>] [--from-tsv <path>]
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "Error: --repo requires owner/name." >&2; exit 1; }
      REPO="$2"
      shift 2
      ;;
    --limit)
      [[ $# -ge 2 ]] || { echo "Error: --limit requires an integer." >&2; exit 1; }
      LIMIT="$2"
      shift 2
      ;;
    --workflow)
      [[ $# -ge 2 ]] || { echo "Error: --workflow requires a value." >&2; exit 1; }
      WORKFLOW="$2"
      shift 2
      ;;
    --from-tsv)
      [[ $# -ge 2 ]] || { echo "Error: --from-tsv requires a file path." >&2; exit 1; }
      FROM_TSV="$2"
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

render_table() {
  local header_label="$1"
  awk -F'\t' -v hdr="$header_label" '
    function ceil_val(x,    i) {
      i = int(x)
      return (x > i ? i + 1 : i)
    }
    function sort_arr(arr, n,    i, j, tmp) {
      for (i = 2; i <= n; i++) {
        tmp = arr[i]
        j = i - 1
        while (j >= 1 && arr[j] > tmp) {
          arr[j + 1] = arr[j]
          j--
        }
        arr[j + 1] = tmp
      }
    }
    function pct(arr, n, p,    idx) {
      if (n <= 0) return 0
      idx = ceil_val((p / 100.0) * n)
      if (idx < 1) idx = 1
      if (idx > n) idx = n
      return arr[idx]
    }
    function fmt(sec,    m, r) {
      if (sec < 60.0) return sprintf("%.1fs", sec)
      m = int(sec / 60.0)
      r = sec - (m * 60.0)
      return sprintf("%dm %.1fs", m, r)
    }
    NF >= 5 {
      job = $1
      if (!(job in counts)) {
        job_order[++num_jobs] = job
        counts[job] = 0
      }
      c = ++counts[job]
      w[job, c] = $2 + 0.0
      s[job, c] = $3 + 0.0
      r[job, c] = $4 + 0.0
      t[job, c] = $5 + 0.0
    }
    END {
      if (num_jobs == 0) {
        print "No completed job samples found."
        exit 0
      }
      for (k = 1; k <= num_jobs; k++) {
        job = job_order[k]
        n = counts[job]
        delete aw; delete as_; delete ar; delete at
        for (i = 1; i <= n; i++) {
          aw[i] = w[job, i]
          as_[i] = s[job, i]
          ar[i] = r[job, i]
          at[i] = t[job, i]
        }
        sort_arr(aw, n); sort_arr(as_, n); sort_arr(ar, n); sort_arr(at, n)
        sort_key[k] = pct(at, n, 95)
        row_line[k] = sprintf("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s |",
          job, n,
          fmt(pct(aw, n, 50)), fmt(pct(aw, n, 95)),
          fmt(pct(as_, n, 50)), fmt(pct(as_, n, 95)),
          fmt(pct(ar, n, 50)), fmt(pct(ar, n, 95)),
          fmt(pct(at, n, 50)), fmt(pct(at, n, 95)))
        order[k] = k
      }
      # Sort rows by Total p95 descending
      for (i = 2; i <= num_jobs; i++) {
        idx = order[i]
        key = sort_key[idx]
        j = i - 1
        while (j >= 1 && sort_key[order[j]] < key) {
          order[j + 1] = order[j]
          j--
        }
        order[j + 1] = idx
      }
      printf "### CI Audit (%s)\n\n", hdr
      print "| Job | Samples | Waiting p50 | Waiting p95 | Setup p50 | Setup p95 | Running p50 | Running p95 | Total p50 | Total p95 |"
      print "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
      for (i = 1; i <= num_jobs; i++) {
        print row_line[order[i]]
      }
    }
  '
}

if [[ -n "$FROM_TSV" ]]; then
  render_table "${REPO:-fixture}" < "$FROM_TSV"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is required." >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

RUN_ARGS=(run list --repo "$REPO" --status completed --limit "$LIMIT" --json databaseId,workflowName --jq '.[] | "\(.databaseId)\t\(.workflowName // "workflow")"')
if [[ -n "$WORKFLOW" ]]; then
  RUN_ARGS+=(--workflow "$WORKFLOW")
fi

TMP_TSV="$(mktemp)"
trap 'rm -f "$TMP_TSV"' EXIT

RUN_COUNT=0
JQ_FILTER='
  def to_sec: if . == null or . == "" then null else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) end;
  def max0: if . < 0 then 0 else . end;
  .jobs[]?
  | select(.status == "completed" and .created_at != null and .started_at != null and .completed_at != null)
  | ((.started_at | to_sec) - (.created_at | to_sec) | max0) as $wait
  | (
      if (.steps | length) > 0 then
        reduce .steps[] as $st (
          {setup: 0, run: 0};
          if ($st.started_at != null and $st.completed_at != null) then
            ((($st.completed_at | to_sec) - ($st.started_at | to_sec)) | max0) as $d
            | if (($st.name // "") | test("^(post |complete job)"; "i")) then
                .
              elif (($st.name // "") | test("^(set up job|checkout|check out|setup|set up|install|cache|restore|configure|download|prepare)\\b"; "i")) then
                .setup += $d
              else
                .run += $d
              end
          else
            .
          end
        )
      else
        {setup: 0, run: (((.completed_at | to_sec) - (.started_at | to_sec)) | max0)}
      end
    ) as $dur
  | "\(.name // "unnamed")\t\($wait)\t\($dur.setup)\t\($dur.run)\t\($wait + $dur.setup + $dur.run)"
'

while IFS=$'\t' read -r run_id wf_name; do
  [[ -n "$run_id" ]] || continue
  RUN_COUNT=$((RUN_COUNT + 1))
  gh api "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" \
    --jq "$JQ_FILTER" 2>/dev/null \
    | awk -v wf="$wf_name" '{ printf "%s / %s\n", wf, $0 }' || true
done < <(gh "${RUN_ARGS[@]}") > "$TMP_TSV"

if (( RUN_COUNT == 0 )); then
  printf 'No completed CI runs found for %s.\n' "$REPO"
  exit 0
fi

render_table "${REPO} — last ${RUN_COUNT} completed runs" < "$TMP_TSV"
