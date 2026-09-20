#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"

check_imports() {
  local target="$1"
  local allowed="$2"
  local unexpected
  unexpected="$(sed -n 's/^import \([A-Za-z0-9_]*\)$/\1/p' "$package_root"/Sources/"$target"/*.swift \
    | sort -u \
    | grep -Ev "$allowed" || true)"
  if [[ -n "$unexpected" ]]; then
    echo "$target has forbidden imports:" >&2
    echo "$unexpected" >&2
    exit 1
  fi
}

check_imports FoodLedgerDomain '^(Foundation)$'
check_imports FoodLedgerApplication '^(CryptoKit|Foundation|FoodLedgerDomain)$'
check_imports FoodLedgerPresentation '^(FoodLedgerApplication|FoodLedgerDomain|SwiftUI)$'
check_imports FoodBarcodeCapture '^(AVFoundation|FoodLedgerApplication|FoodLedgerDomain|SwiftUI|Vision|VisionKit)$'
check_imports FoodLedgerTestSupport '^(Foundation|FoodLedgerApplication|FoodLedgerDomain)$'
check_imports FoodLedgerGRDB '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|GRDB)$'

if grep -RnsE '^import (GRDB|SwiftUI|UIKit|HealthKit)$' \
  "$package_root/Sources/FoodLedgerDomain" \
  "$package_root/Sources/FoodLedgerApplication"; then
  echo "Domain/application boundary imports infrastructure or presentation" >&2
  exit 1
fi

if grep -RnsE '^import GRDB$' "$package_root/Sources/FoodLedgerPresentation"; then
  echo "Presentation imports persistence infrastructure" >&2
  exit 1
fi

grep -q 'exact: "7.11.1"' "$package_root/Package.swift"
grep -q 'Licence: MIT' "$package_root/DEPENDENCIES.md"
