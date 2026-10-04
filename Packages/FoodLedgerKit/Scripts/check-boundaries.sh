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
check_imports FoodGenericSearch '^(CoreFoundation|CryptoKit|Darwin|Foundation|Network|PDFKit|Security|SwiftSoup|FoodLedgerApplication|FoodLedgerDomain)$'
check_imports FoodInventoryImport '^(Foundation|PDFKit|FoodLedgerApplication|FoodLedgerDomain)$'
check_imports FoodLedgerPresentation '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|SwiftUI|WebKit)$'
check_imports FoodBarcodeCapture '^(AVFoundation|FoodLedgerApplication|FoodLedgerDomain|SwiftUI|Vision|VisionKit)$'
check_imports FoodLedgerArchive '^(Foundation|FoodLedgerApplication|FoodLedgerGRDB)$'
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

# Keep platform capabilities restricted to their concrete adapters.
if grep -l '^import Security$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -Ev '/(GeminiKeychainStore|PublicFoodSourceCapture)\.swift$'; then
  echo "Security belongs only in the keychain or public-source TLS adapter" >&2; exit 1
fi
if grep -l '^import WebKit$' "$package_root"/Sources/FoodLedgerPresentation/*.swift | grep -v '/FoodWebSearchSuggestions.swift$'; then
  echo "WebKit belongs only in the search-suggestion renderer" >&2; exit 1
fi

if grep -l '^import Foundation$' "$package_root"/Sources/FoodLedgerPresentation/*.swift | grep -v '/GenericFoodProposalReviewView.swift$'; then
  echo "Explicit Foundation import belongs only in the generic food review view" >&2; exit 1
fi

# Native address resolution and pinned TLS transport stay in the public-source adapter.
for capability in Darwin Network; do
  if grep -l "^import $capability$" "$package_root"/Sources/FoodGenericSearch/*.swift | grep -v '/PublicFoodSourceCapture.swift$'; then
    echo "$capability belongs only in the public-source transport adapter" >&2; exit 1
  fi
done
if grep -l '^import PDFKit$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -v '/GenericFoodPDFProjector.swift$'; then
  echo "PDFKit belongs only in the generic food PDF projector" >&2; exit 1
fi

# HTML parsing and JSON Boolean discrimination stay in concrete source adapters.
if grep -l '^import SwiftSoup$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -Ev '/(HTMLFoodSourceTableProjector|GenericFoodDocumentProjector|ManufacturerSourcePageIdentity|AlproSourceCandidateAdmission|ArlaSourceCandidateAdmission|OatlySourceCandidateAdmission|WPRecipeSourceParser)\.swift$'; then
  echo "SwiftSoup belongs only in the reviewed source HTML adapters" >&2; exit 1
fi
if grep -l '^import CoreFoundation$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -v '/OFFHTTPSearchTransport.swift$'; then
  echo "CoreFoundation belongs only in the OFF JSON transport adapter" >&2; exit 1
fi
grep -q 'exact: "2.13.9"' "$package_root/Package.swift"
grep -q '## SwiftSoup 2.13.9' "$package_root/DEPENDENCIES.md"
test -s "$package_root/Sources/FoodGenericSearch/Resources/SwiftSoup-LICENSE.txt"
