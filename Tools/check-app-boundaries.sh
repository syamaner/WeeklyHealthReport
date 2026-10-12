#!/usr/bin/env bash
# App-level boundary checks.
# - WeeklyHealthReport/Presentation (including any subfolder) holds pure report
#   and export presentation types, so it may import Foundation only (#200).
#   `@preconcurrency import Foundation` and trailing comments are allowed.
# - WeeklyHealthReport/Models holds pure domain rules, so it never imports
#   HealthKit, SwiftUI or UIKit (#199, today-so-far contract section 7).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
presentation="$repo_root/WeeklyHealthReport/Presentation"
models="$repo_root/WeeklyHealthReport/Models"

swift_files() {
  find "$1" -type f -name '*.swift' -print0 | sort -z
}

import_lines() {
  grep -nE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' "$1" || true
}

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(swift_files "$presentation")

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
  done < <(import_lines "$file")
done

if [[ -n "$unexpected" ]]; then
  echo "WeeklyHealthReport/Presentation may import Foundation only:" >&2
  printf '%s' "$unexpected" >&2
  exit 1
fi

model_files=()
while IFS= read -r -d '' file; do
  model_files+=("$file")
done < <(swift_files "$models")

if [[ ${#model_files[@]} -eq 0 ]]; then
  echo "No Swift files found in $models" >&2
  exit 1
fi

denied='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?(HealthKit|SwiftUI|UIKit)([.[:space:]]|$)'
forbidden=""
for file in "${model_files[@]}"; do
  while IFS= read -r line; do
    text="${line#*:}"
    if [[ "$text" =~ $denied ]]; then
      forbidden+="$file:$line"$'\n'
    fi
  done < <(import_lines "$file")
done

if [[ -n "$forbidden" ]]; then
  echo "WeeklyHealthReport/Models may not import HealthKit, SwiftUI or UIKit:" >&2
  printf '%s' "$forbidden" >&2
  exit 1
fi

echo "App presentation boundary: ${#files[@]} files import Foundation only"
echo "App model boundary: ${#model_files[@]} files import no HealthKit, SwiftUI or UIKit"
