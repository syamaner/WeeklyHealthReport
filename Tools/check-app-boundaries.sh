#!/usr/bin/env bash
# App-level boundary check (#200): WeeklyHealthReport/Presentation (including
# any subfolder) holds pure report and export presentation types, so it may
# import Foundation only. `@preconcurrency import Foundation` and trailing
# comments are allowed.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
presentation="$repo_root/WeeklyHealthReport/Presentation"

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(find "$presentation" -type f -name '*.swift' -print0 | sort -z)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Swift files found in $presentation" >&2
  exit 1
fi

allowed='^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+Foundation[[:space:]]*(//.*)?$'
unexpected=""
for file in "${files[@]}"; do
  while IFS= read -r line; do
    text="${line#*:}"
    if [[ ! "$text" =~ $allowed ]]; then
      unexpected+="$file:$line"$'\n'
    fi
  done < <(grep -nE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$file" || true)
done

if [[ -n "$unexpected" ]]; then
  echo "WeeklyHealthReport/Presentation may import Foundation only:" >&2
  printf '%s' "$unexpected" >&2
  exit 1
fi
echo "App presentation boundary: ${#files[@]} files import Foundation only"
