#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
app_root="$(cd "$package_root/../.." && pwd)"

# Every import form names its module the same way: `import X`, `@testable import X`,
# `@_implementationOnly import X`, `@preconcurrency import X` and `import struct X.Y` (and
# class, enum, protocol, func, var, let, typealias), with or without a trailing comment.
import_attributes='^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'

module_imports() {
  sed -nE "s/${import_attributes}([A-Za-z0-9_]+).*$/\5/p" "$@"
}

check_imports() {
  local target="$1"
  local allowed="$2"
  local unexpected
  unexpected="$(module_imports "$package_root"/Sources/"$target"/*.swift \
    | sort -u \
    | grep -Ev "$allowed" || true)"
  if [[ -n "$unexpected" ]]; then
    echo "$target has forbidden imports:" >&2
    echo "$unexpected" >&2
    exit 1
  fi
}

# Swift files under the given directories (those that exist) importing `module` in any form.
files_importing() {
  local module="$1"; shift
  local dirs=()
  local dir
  for dir in "$@"; do
    if [[ -d "$dir" ]]; then dirs+=("$dir"); fi
  done
  if [[ ${#dirs[@]} -eq 0 ]]; then return 0; fi
  grep -rlE --include='*.swift' "${import_attributes}${module}([.;[:space:]]|$)" "${dirs[@]}" || true
}

# Each top-level target declaration of Package.swift's `targets:` argument on one line, comments
# removed. Brackets are tracked, so a `.target(name:)` dependency inside a declaration never
# starts a new one, and the `targets:` lists of products are not mistaken for the argument.
package_targets() {
  # A comment starts a line or follows whitespace; `//` inside a URL string follows `:`.
  sed -E 's:(^|[[:space:]])//.*$::' "$1" | tr '\n' ' ' | awk '
    {
      s = $0; n = length(s); depth = 0; inside = 0; started = 0; out = ""
      for (k = 1; k <= n; k++) {
        c = substr(s, k, 1)
        if (!inside && depth == 1 && substr(s, k, 8) == "targets:") { inside = 1 }
        if (inside && depth == 2 && c == "." && match(substr(s, k), /^\.(testTarget|executableTarget|target)\(/)) {
          if (started) print out
          out = ""; started = 1
        }
        if (c == "(" || c == "[") depth++
        else if (c == ")" || c == "]") {
          depth--
          if (inside && depth == 1) { if (started) print out; exit }
        }
        if (started) out = out c
      }
    }'
}

# Pasted nutrition label (docs/pasted-nutrition-label-v1.md section 8.2, decision 10): only the
# adapter, the parser CLI and their tests reach NutritionLabelParsing, and only the composition
# root and the adapter's tests reach FoodLabelTextCapture. Checked over every import form, in the
# package sources, tools and tests, in the app target and its tests, and in both manifests.
# Returns non-zero with the violations on stderr.
check_label_reader_edges() {
  local pkg="$1" app="$2"
  local violations="" file line name rest dep allowed
  local scanned=("$pkg/Sources" "$pkg/Tools" "$pkg/Tests")
  for file in "$app"/WeeklyHealthReport*; do
    if [[ -d "$file" && "$file" != *.xcodeproj ]]; then scanned+=("$file"); fi
  done

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /(Sources/(NutritionLabelParsing|FoodLabelTextCapture|FoodLabelPhotoReading)|Tools/NutritionLabelTextParse|Tests/(NutritionLabelParsingTests|FoodLabelTextCaptureTests|FoodLabelPhotoReadingTests))/ ]]; then
      violations+="NutritionLabelParsing imported by $file"$'\n'
    fi
  done < <(files_importing NutritionLabelParsing "${scanned[@]}")

  # Label photo reader (docs/label-photo-ai-prefill-v1.md 17.2): only its own tests and the
  # photo capture adapter (and that adapter's tests) reach FoodLabelPhotoReading. The app is never
  # linked to it directly (below), so the composition root reaches it through the adapter, and
  # presentation and application never import it.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /(Sources/FoodLabelPhotoCapture|Tests/(FoodLabelPhotoReadingTests|FoodLabelPhotoCaptureTests))/ ]]; then
      violations+="FoodLabelPhotoReading imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelPhotoReading "${scanned[@]}")

  # Only the preparer builds a PreparedLabelImage (docs/label-photo-ai-prefill-v1.md 17.8 M6): the
  # initialiser is called only in the photo capture adapter and in tests.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /(Sources/FoodLabelPhotoCapture|Tests)/ ]]; then
      violations+="PreparedLabelImage built in $file"$'\n'
    fi
  done < <(grep -rlE --include='*.swift' 'PreparedLabelImage\(' "${scanned[@]}" 2>/dev/null || true)

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ "$file" != "$app/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" && ! "$file" =~ /Tests/FoodLabelTextCaptureTests/ ]]; then
      violations+="FoodLabelTextCapture imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelTextCapture "${scanned[@]}")

  if [[ -n "$(files_importing FoodLabelTextCapture "$pkg/Sources/FoodLedgerPresentation")" ]]; then
    violations+="FoodLedgerPresentation must not import FoodLabelTextCapture"$'\n'
  fi

  local declarations
  declarations="$(package_targets "$pkg/Package.swift")"
  # Fail closed: a manifest the scan cannot split into target declarations is not "no edges".
  if [[ -z "$declarations" || "$declarations" != *'name:'* ]]; then
    violations+="Package.swift: no target declarations could be read"$'\n'
  fi
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    name="$(sed -nE 's/^[^"]*name:[[:space:]]*"([A-Za-z0-9_]+)".*/\1/p' <<< "$line")"
    rest="$(sed -E 's/name:[[:space:]]*"[A-Za-z0-9_]+"//' <<< "$line")"
    for dep in NutritionLabelParsing FoodLabelTextCapture FoodLabelPhotoReading; do
      if [[ "$rest" != *"\"$dep\""* ]]; then continue; fi
      case "$dep" in
        NutritionLabelParsing) allowed='^(FoodLabelTextCapture|FoodLabelPhotoReading|NutritionLabelTextParse|NutritionLabelParsingTests|FoodLabelTextCaptureTests|FoodLabelPhotoReadingTests)$' ;;
        FoodLabelPhotoReading) allowed='^(FoodLabelPhotoReadingTests|FoodLabelPhotoCapture|FoodLabelPhotoCaptureTests)$' ;;
        *) allowed='^(FoodLabelTextCaptureTests)$' ;;
      esac
      if [[ ! "$name" =~ $allowed ]]; then violations+="Package.swift: $name depends on $dep"$'\n'; fi
    done
  done <<< "$declarations"

  for file in "$app"/*.xcodeproj/project.pbxproj; do
    if [[ -f "$file" ]] && grep -q 'productName = NutritionLabelParsing;' "$file"; then
      violations+="$file links NutritionLabelParsing; the app reaches it only through FoodLabelTextCapture"$'\n'
    fi
    if [[ -f "$file" ]] && grep -q 'productName = FoodLabelPhotoReading;' "$file"; then
      violations+="$file links FoodLabelPhotoReading; the app reaches it only through the composition root's adapter"$'\n'
    fi
  done

  if [[ -n "$violations" ]]; then
    printf '%s' "$violations" >&2
    return 1
  fi
}

# Contract test 48: the edge check must fail on each forbidden form. Fixtures are written to a
# temporary tree shaped like this repository; the baseline must pass and every mutation fail.
self_test_label_reader_edges() {
  local scratch status=0
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-boundaries.XXXXXX")"
  local base="$scratch/base"
  local pkg="$base/Packages/FoodLedgerKit"
  mkdir -p "$pkg/Sources/NutritionLabelParsing" "$pkg/Sources/FoodLabelTextCapture" "$pkg/Sources/FoodLedgerApplication" \
    "$pkg/Sources/FoodLedgerPresentation" "$pkg/Sources/FoodGenericSearch" "$pkg/Tools/NutritionLabelTextParse" \
    "$pkg/Tests/NutritionLabelParsingTests" "$pkg/Tests/FoodLabelTextCaptureTests" "$pkg/Tests/FoodLedgerContractTests" \
    "$pkg/Sources/FoodLabelPhotoReading" "$pkg/Tests/FoodLabelPhotoReadingTests" \
    "$base/WeeklyHealthReport/FoodLedger" "$base/WeeklyHealthReport.xcodeproj"
  cat > "$pkg/Package.swift" <<'SWIFT'
let package = Package(
    name: "FoodLedgerKit",
    products: [
        .library(name: "NutritionLabelParsing", targets: ["NutritionLabelParsing"]),
        .library(name: "FoodLabelTextCapture", targets: ["FoodLabelTextCapture"])
    ],
    dependencies: [
        .package(url: "https://example.invalid/fixture.git", exact: "1.0.0") // a URL and a trailing comment
    ],
    targets: [
        .executableTarget(name: "NutritionLabelTextParse", dependencies: ["NutritionLabelParsing"], path: "Tools/NutritionLabelTextParse"),
        .target(name: "NutritionLabelParsing"),
        .target(name: "FoodLedgerApplication", dependencies: ["FoodLedgerDomain"]),
        .target(
            name: "FoodLabelTextCapture",
            dependencies: ["FoodLedgerApplication", "NutritionLabelParsing"]
        ),
        .target(name: "FoodLabelPhotoReading", dependencies: ["NutritionLabelParsing"]),
        .testTarget(name: "FoodLabelPhotoReadingTests", dependencies: ["FoodLabelPhotoReading"]),
        .testTarget(name: "NutritionLabelParsingTests", dependencies: ["NutritionLabelParsing"]),
        .testTarget(name: "FoodLabelTextCaptureTests", dependencies: ["FoodLabelTextCapture", "NutritionLabelParsing"])
    ]
)
SWIFT
  echo 'import Foundation' > "$pkg/Sources/NutritionLabelParsing/Parser.swift"
  printf 'import FoodLedgerApplication\nimport NutritionLabelParsing\n' > "$pkg/Sources/FoodLabelTextCapture/Reader.swift"
  echo 'import Foundation' > "$pkg/Sources/FoodLedgerApplication/Port.swift"
  echo 'import NutritionLabelParsing' > "$pkg/Sources/FoodLabelPhotoReading/Matcher.swift"
  echo '@testable import FoodLabelPhotoReading' > "$pkg/Tests/FoodLabelPhotoReadingTests/MatcherTests.swift"
  echo 'import SwiftUI' > "$pkg/Sources/FoodLedgerPresentation/View.swift"
  echo 'import NutritionLabelParsing' > "$pkg/Tools/NutritionLabelTextParse/main.swift"
  echo '@testable import NutritionLabelParsing' > "$pkg/Tests/NutritionLabelParsingTests/ParserTests.swift"
  printf '@testable import FoodLabelTextCapture\nimport NutritionLabelParsing\n' > "$pkg/Tests/FoodLabelTextCaptureTests/ReaderTests.swift"
  echo 'import FoodLabelTextCapture' > "$base/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift"
  echo 'productName = FoodLabelTextCapture;' > "$base/WeeklyHealthReport.xcodeproj/project.pbxproj"
  if ! check_label_reader_edges "$pkg" "$base" 2>/dev/null; then
    echo "check-boundaries self-test: the baseline fixture must pass" >&2; status=1
  fi

  local fixture target fpkg
  for fixture in testable struct_form implementation_only package_edge package_target_edge package_byname_edge \
      package_product_edge package_adapter_edge package_unreadable app_import app_import_semicolon presentation_adapter app_link \
      photo_presentation photo_application photo_app_import photo_package_edge photo_app_link; do
    target="$scratch/$fixture"
    cp -R "$base" "$target"
    fpkg="$target/Packages/FoodLedgerKit"
    case "$fixture" in
      testable) echo '@testable import NutritionLabelParsing' > "$fpkg/Tests/FoodLedgerContractTests/Leak.swift" ;;
      struct_form) echo 'import struct NutritionLabelParsing.LabelCell' > "$fpkg/Sources/FoodLedgerApplication/Leak.swift" ;;
      implementation_only) echo '@_implementationOnly import NutritionLabelParsing' > "$fpkg/Sources/FoodGenericSearch/Leak.swift" ;;
      package_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", "NutritionLabelParsing"]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      package_target_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", .target(name: "NutritionLabelParsing")]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      package_byname_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: [.byName(name: "NutritionLabelParsing"), "FoodLedgerDomain"]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      package_product_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", .product(name: "NutritionLabelParsing", package: "FoodLedgerKit")]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      package_unreadable) echo 'let package = Package(name: "FoodLedgerKit")' > "$fpkg/Package.swift" ;;
      package_adapter_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", .target(name: "FoodLabelTextCapture")]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      app_import) echo 'import NutritionLabelParsing' > "$target/WeeklyHealthReport/Leak.swift" ;;
      app_import_semicolon) echo 'import NutritionLabelParsing; import Foundation' > "$target/WeeklyHealthReport/Leak.swift" ;;
      presentation_adapter) echo 'import FoodLabelTextCapture' > "$fpkg/Sources/FoodLedgerPresentation/Leak.swift" ;;
      app_link) echo 'productName = NutritionLabelParsing;' >> "$target/WeeklyHealthReport.xcodeproj/project.pbxproj" ;;
      photo_presentation) echo 'import FoodLabelPhotoReading' > "$fpkg/Sources/FoodLedgerPresentation/Leak.swift" ;;
      photo_application) echo 'import struct FoodLabelPhotoReading.LabelValueMatcher' > "$fpkg/Sources/FoodLedgerApplication/Leak.swift" ;;
      photo_app_import) echo 'import FoodLabelPhotoReading' >> "$target/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" ;;
      photo_package_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", "FoodLabelPhotoReading"]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      photo_app_link) echo 'productName = FoodLabelPhotoReading;' >> "$target/WeeklyHealthReport.xcodeproj/project.pbxproj" ;;
    esac
    if check_label_reader_edges "$fpkg" "$target" 2>/dev/null; then
      echo "check-boundaries self-test: the $fixture fixture must fail" >&2; status=1
    fi
  done
  rm -rf "$scratch"
  return "$status"
}

self_test_label_reader_edges
check_label_reader_edges "$package_root" "$app_root"

check_imports FoodLabelTextCapture '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'
# Label photo reader (#316, docs/label-photo-ai-prefill-v1.md 17.2): pure, no platform framework.
check_imports FoodLabelPhotoReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'
check_imports FoodLedgerDomain '^(Foundation)$'
# Pure label-text parser under evaluation (#255): no app, platform or hashing dependency.
check_imports NutritionLabelParsing '^(Foundation)$'
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
  echo "Security belongs only in the keychain and TLS capture adapters" >&2; exit 1
fi
if grep -l '^import WebKit$' "$package_root"/Sources/FoodLedgerPresentation/*.swift | grep -v '/FoodWebSearchSuggestions.swift$'; then
  echo "WebKit belongs only in the search-suggestion renderer" >&2; exit 1
fi

# HTML parsing and JSON Boolean discrimination stay in concrete source adapters.
if grep -l '^import SwiftSoup$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -Ev '/(HTMLFoodSourceTableProjector|ManufacturerSourcePageIdentity|AlproSourceCandidateAdmission|ArlaSourceCandidateAdmission|OatlySourceCandidateAdmission|WPRecipeSourceParser|GenericFoodDocumentProjector)\.swift$'; then
  echo "SwiftSoup belongs only in the reviewed source HTML adapters" >&2; exit 1
fi
if grep -l '^import CoreFoundation$' "$package_root"/Sources/FoodGenericSearch/*.swift | grep -v '/OFFHTTPSearchTransport.swift$'; then
  echo "CoreFoundation belongs only in the OFF JSON transport adapter" >&2; exit 1
fi
grep -q 'exact: "2.13.9"' "$package_root/Package.swift"
grep -q '## SwiftSoup 2.13.9' "$package_root/DEPENDENCIES.md"
test -s "$package_root/Sources/FoodGenericSearch/Resources/SwiftSoup-LICENSE.txt"

# Generic acquisition platform APIs are confined to the concrete capture/PDF adapters.
for capability in Darwin Network PDFKit; do
  case "$capability" in
    Darwin|Network) adapter='PublicFoodSourceCapture' ;;
    PDFKit) adapter='GenericFoodPDFProjector' ;;
  esac
  if grep -l "^import $capability$" "$package_root"/Sources/FoodGenericSearch/*.swift | grep -v "/$adapter.swift$"; then
    echo "$capability belongs only in $adapter" >&2; exit 1
  fi
done
if grep -l '^import Foundation$' "$package_root"/Sources/FoodLedgerPresentation/*.swift | grep -v '/GenericFoodProposalReviewView.swift$'; then
  echo "Explicit Foundation import belongs only in the generic review presentation adapter" >&2; exit 1
fi
