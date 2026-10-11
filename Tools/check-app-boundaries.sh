#!/usr/bin/env bash
# App-level boundary check (#200): WeeklyHealthReport/Presentation holds pure
# report and export presentation types, so it may import Foundation only.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
presentation="$repo_root/WeeklyHealthReport/Presentation"

shopt -s nullglob
files=("$presentation"/*.swift)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Swift files found in $presentation" >&2
  exit 1
fi

unexpected="$(grep -HnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "${files[@]}" \
  | grep -vE ':[0-9]+:import Foundation$' || true)"
if [[ -n "$unexpected" ]]; then
  echo "WeeklyHealthReport/Presentation may import Foundation only:" >&2
  echo "$unexpected" >&2
  exit 1
fi
echo "App presentation boundary: ${#files[@]} files import Foundation only"
