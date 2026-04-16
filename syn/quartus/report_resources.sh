#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <revision>" >&2
  exit 1
fi

rev="$1"
summary="output_files/${rev}.fit.summary"
sta="output_files/${rev}.sta.rpt"

if [ ! -f "$summary" ]; then
  echo "missing $summary" >&2
  exit 1
fi

require_line() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  local line

  line=$(grep -m 1 -E "$pattern" "$file" || true)
  if [ -z "$line" ]; then
    echo "missing ${label} in ${file}" >&2
    exit 1
  fi

  printf '%s\n' "$line"
}

echo "Revision: $rev"
require_line '^Fitter Status' "$summary" "Fitter Status"
require_line '^Logic utilization' "$summary" "Logic utilization"
require_line '^Total registers' "$summary" "Total registers"
require_line '^Total block memory bits' "$summary" "Total block memory bits"
require_line '^(Total )?RAM Blocks' "$summary" "RAM Blocks"

if [ -f "$sta" ]; then
  require_line 'Worst-case setup slack is' "$sta" "Worst-case setup slack"
  grep -m 1 -E 'Worst-case hold slack is' "$sta" || true
fi
