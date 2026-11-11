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
    if [[ ! "$file" =~ /(Sources/(NutritionLabelParsing|FoodLabelTextCapture|FoodLabelPhotoReading|FoodLabelTextAIReading|UKNutritionLabelParsing)|Tools/NutritionLabelTextParse|Tests/(NutritionLabelParsingTests|FoodLabelTextCaptureTests|FoodLabelPhotoReadingTests|FoodLabelTextAIReadingTests|UKNutritionLabelParsingTests))/ ]]; then
      violations+="NutritionLabelParsing imported by $file"$'\n'
    fi
  done < <(files_importing NutritionLabelParsing "${scanned[@]}")

  # UK English reader (#371 P2a, docs/pasted-nutrition-label-uk-english-v1-p2.md section 1): only
  # the text capture adapter, its tests and the target's own tests reach UKNutritionLabelParsing.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /(Sources/FoodLabelTextCapture|Tests/(FoodLabelTextCaptureTests|UKNutritionLabelParsingTests))/ ]]; then
      violations+="UKNutritionLabelParsing imported by $file"$'\n'
    fi
  done < <(files_importing UKNutritionLabelParsing "${scanned[@]}")

  # Label photo reader (docs/label-photo-ai-prefill-v1.md 17.2): only its own tests and the
  # photo capture adapter (and that adapter's tests) reach FoodLabelPhotoReading. The app is never
  # linked to it directly (below), so the composition root reaches it through the adapter, and
  # presentation and application never import it. The text reader's tests import it for the
  # mapping parity test (docs/pasted-label-ai-text-v1.md 11.1); the text reader itself never does.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /(Sources/FoodLabelPhotoCapture|Tests/(FoodLabelPhotoReadingTests|FoodLabelPhotoCaptureTests|FoodLabelTextAIReadingTests))/ ]]; then
      violations+="FoodLabelPhotoReading imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelPhotoReading "${scanned[@]}")

  # Pasted label AI text reader (#416 A2, docs/pasted-label-ai-text-v1.md 11.1): only the
  # composition root and the target's own tests import it; application and presentation never do.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ "$file" != "$app/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" && ! "$file" =~ /Tests/FoodLabelTextAIReadingTests/ ]]; then
      violations+="FoodLabelTextAIReading imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelTextAIReading "${scanned[@]}")

  # Label photo capture adapters (17.2): only the composition root and the target's own tests
  # import it, and presentation never does.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ "$file" != "$app/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" && ! "$file" =~ /Tests/FoodLabelPhotoCaptureTests/ ]]; then
      violations+="FoodLabelPhotoCapture imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelPhotoCapture "${scanned[@]}")

  # Within FoodLabelPhotoCapture each framework stays in its adapter file (17.2): ImageIO,
  # CoreGraphics and UniformTypeIdentifiers in the preparer, Vision in the locator, Network in the
  # connectivity adapter, and URL loading only in the transport. Every import form counts
  # (attributes, `import struct X.Y`, trailing comments, indentation), as for check_imports.
  local capture="$pkg/Sources/FoodLabelPhotoCapture" base modules
  if [[ -d "$capture" ]]; then
    while IFS= read -r file; do
      if [[ -z "$file" ]]; then continue; fi
      base="${file##*/}"
      modules="$(module_imports "$file" | sort -u)"
      if grep -qxE '(ImageIO|CoreGraphics|UniformTypeIdentifiers)' <<< "$modules" && [[ "$base" != "ImageIOLabelImagePreparer.swift" ]]; then
        violations+="$file imports an image framework outside the preparer"$'\n'
      fi
      if grep -qxE 'Vision' <<< "$modules" && [[ "$base" != "VisionLabelValueLocator.swift" ]]; then
        violations+="$file imports Vision outside the locator"$'\n'
      fi
      if grep -qxE 'Network' <<< "$modules" && [[ "$base" != "NWPathConnectivityStatus.swift" ]]; then
        violations+="$file imports Network outside the connectivity adapter"$'\n'
      fi
      if grep -qE 'URLSession|NSURLConnection|CFNetwork|CFStream|Data\(contentsOf:|String\(contentsOf:' "$file" && [[ "$base" != "OpenRouterTransport.swift" ]]; then
        violations+="$file loads a URL outside the transport"$'\n'
      fi
    done < <(find "$capture" -name '*.swift' -type f)
  fi

  # Label photo UI (17.2, 17.19): only the composition root and the target's own tests import it,
  # and presentation never does. AVFoundation stays in the source buttons (camera authorisation
  # status only), and the UI never loads a URL.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ "$file" != "$app/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" && ! "$file" =~ /Tests/FoodLabelPhotoUITests/ ]]; then
      violations+="FoodLabelPhotoUI imported by $file"$'\n'
    fi
  done < <(files_importing FoodLabelPhotoUI "${scanned[@]}")
  local photoUI="$pkg/Sources/FoodLabelPhotoUI"
  if [[ -d "$photoUI" ]]; then
    while IFS= read -r file; do
      if [[ -z "$file" ]]; then continue; fi
      base="${file##*/}"
      modules="$(module_imports "$file" | sort -u)"
      if grep -qxE 'AVFoundation' <<< "$modules" && [[ "$base" != "LabelPhotoSourceButtons.swift" ]]; then
        violations+="$file imports AVFoundation outside the source buttons"$'\n'
      fi
      if grep -qE 'URLSession|NSURLConnection|CFNetwork|CFStream|Data\(contentsOf:|String\(contentsOf:' "$file"; then
        violations+="$file loads a URL in the label photo UI"$'\n'
      fi
    done < <(find "$photoUI" -name '*.swift' -type f)
  fi

  # Only the preparer builds a PreparedLabelImage (docs/label-photo-ai-prefill-v1.md 17.8 M6): its
  # initialiser is private to LabelPhotoPorts.swift, and the package factory there is called only
  # in the preparer's own file and in tests.
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ ! "$file" =~ /Tests/ && "$file" != */Sources/FoodLabelPhotoCapture/ImageIOLabelImagePreparer.swift \
          && "$file" != */Sources/FoodLedgerApplication/LabelPhotoPorts.swift ]]; then
      violations+="PreparedLabelImage built in $file"$'\n'
    fi
  done < <(grep -rlE --include='*.swift' 'PreparedLabelImageFactory|PreparedLabelImage(\.init)?\(' "${scanned[@]}" 2>/dev/null || true)

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
    for dep in NutritionLabelParsing UKNutritionLabelParsing FoodLabelTextCapture FoodLabelPhotoReading FoodLabelPhotoCapture FoodLabelPhotoUI FoodLabelTextAIReading; do
      if [[ "$rest" != *"\"$dep\""* ]]; then continue; fi
      case "$dep" in
        NutritionLabelParsing) allowed='^(FoodLabelTextCapture|FoodLabelPhotoReading|FoodLabelTextAIReading|UKNutritionLabelParsing|NutritionLabelTextParse|NutritionLabelParsingTests|FoodLabelTextCaptureTests|FoodLabelPhotoReadingTests|FoodLabelTextAIReadingTests|UKNutritionLabelParsingTests)$' ;;
        UKNutritionLabelParsing) allowed='^(FoodLabelTextCapture|FoodLabelTextCaptureTests|UKNutritionLabelParsingTests)$' ;;
        FoodLabelPhotoReading) allowed='^(FoodLabelPhotoReadingTests|FoodLabelPhotoCapture|FoodLabelPhotoCaptureTests|FoodLabelTextAIReadingTests)$' ;;
        FoodLabelPhotoCapture) allowed='^(FoodLabelPhotoCaptureTests)$' ;;
        FoodLabelPhotoUI) allowed='^(FoodLabelPhotoUITests)$' ;;
        FoodLabelTextAIReading) allowed='^(FoodLabelTextAIReadingTests)$' ;;
        *) allowed='^(FoodLabelTextCaptureTests)$' ;;
      esac
      if [[ ! "$name" =~ $allowed ]]; then violations+="Package.swift: $name depends on $dep"$'\n'; fi
    done
  done <<< "$declarations"

  for file in "$app"/*.xcodeproj/project.pbxproj; do
    if [[ -f "$file" ]] && grep -q 'productName = NutritionLabelParsing;' "$file"; then
      violations+="$file links NutritionLabelParsing; the app reaches it only through FoodLabelTextCapture"$'\n'
    fi
    if [[ -f "$file" ]] && grep -q 'productName = UKNutritionLabelParsing;' "$file"; then
      violations+="$file links UKNutritionLabelParsing; the app reaches it only through FoodLabelTextCapture"$'\n'
    fi
    # The app may link FoodLabelTextAIReading (wired at the composition root); it still never
    # links NutritionLabelParsing directly (above).
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
    "$pkg/Sources/FoodLabelTextAIReading" "$pkg/Tests/FoodLabelTextAIReadingTests" \
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
        .target(name: "FoodLabelTextAIReading", dependencies: ["FoodLedgerApplication", "NutritionLabelParsing"]),
        .testTarget(name: "FoodLabelTextAIReadingTests", dependencies: ["FoodLabelTextAIReading", "FoodLabelPhotoReading", "NutritionLabelParsing"]),
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
  printf 'import FoodLedgerApplication\nimport NutritionLabelParsing\n' > "$pkg/Sources/FoodLabelTextAIReading/Reader.swift"
  printf '@testable import FoodLabelTextAIReading\n@testable import FoodLabelPhotoReading\nimport NutritionLabelParsing\n' \
    > "$pkg/Tests/FoodLabelTextAIReadingTests/ParityTests.swift"
  echo 'import SwiftUI' > "$pkg/Sources/FoodLedgerPresentation/View.swift"
  echo 'import NutritionLabelParsing' > "$pkg/Tools/NutritionLabelTextParse/main.swift"
  echo '@testable import NutritionLabelParsing' > "$pkg/Tests/NutritionLabelParsingTests/ParserTests.swift"
  printf '@testable import FoodLabelTextCapture\nimport NutritionLabelParsing\n' > "$pkg/Tests/FoodLabelTextCaptureTests/ReaderTests.swift"
  printf 'import FoodLabelTextCapture\nimport FoodLabelTextAIReading\n' > "$base/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift"
  printf 'productName = FoodLabelTextCapture;\nproductName = FoodLabelTextAIReading;\n' > "$base/WeeklyHealthReport.xcodeproj/project.pbxproj"
  if ! check_label_reader_edges "$pkg" "$base" 2>/dev/null; then
    echo "check-boundaries self-test: the baseline fixture must pass" >&2; status=1
  fi

  local fixture target fpkg
  for fixture in testable struct_form implementation_only package_edge package_target_edge package_byname_edge \
      package_product_edge package_adapter_edge package_unreadable app_import app_import_semicolon presentation_adapter app_link \
      photo_presentation photo_application photo_app_import photo_package_edge photo_app_link \
      uk_application uk_testable uk_app_import uk_package_edge uk_library uk_app_link \
      text_application text_presentation text_imports_photo text_photo_package_edge text_package_edge text_app_import; do
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
      uk_application) echo 'import UKNutritionLabelParsing' > "$fpkg/Sources/FoodLedgerApplication/Leak.swift" ;;
      uk_testable) echo '@testable import UKNutritionLabelParsing' > "$fpkg/Tests/FoodLedgerContractTests/Leak.swift" ;;
      uk_app_import) echo 'import UKNutritionLabelParsing' >> "$target/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" ;;
      uk_package_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", "UKNutritionLabelParsing"]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      uk_library)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", .product(name: "UKNutritionLabelParsing", package: "FoodLedgerKit")]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      uk_app_link) echo 'productName = UKNutritionLabelParsing;' >> "$target/WeeklyHealthReport.xcodeproj/project.pbxproj" ;;
      # Pasted label AI text reader (#416 A2, docs/pasted-label-ai-text-v1.md 11.1).
      text_application) echo 'import FoodLabelTextAIReading' > "$fpkg/Sources/FoodLedgerApplication/Leak.swift" ;;
      text_presentation) echo '@testable import FoodLabelTextAIReading' > "$fpkg/Sources/FoodLedgerPresentation/Leak.swift" ;;
      text_imports_photo) echo 'import struct FoodLabelPhotoReading.LabelPhotoWire' > "$fpkg/Sources/FoodLabelTextAIReading/Leak.swift" ;;
      text_photo_package_edge)
        sed 's/.target(name: "FoodLabelTextAIReading", dependencies: \["FoodLedgerApplication", "NutritionLabelParsing"\])/.target(name: "FoodLabelTextAIReading", dependencies: ["FoodLedgerApplication", "NutritionLabelParsing", "FoodLabelPhotoReading"])/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      text_package_edge)
        sed 's/dependencies: \["FoodLedgerDomain"\]/dependencies: ["FoodLedgerDomain", .product(name: "FoodLabelTextAIReading", package: "FoodLedgerKit")]/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      text_app_import) echo 'import FoodLabelTextAIReading' > "$target/WeeklyHealthReport/Leak.swift" ;;
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

check_imports FoodLabelTextCapture '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing|UKNutritionLabelParsing)$'
# UK English reader (#371 P2a): pure, over the frozen parser's public API only.
check_imports UKNutritionLabelParsing '^(Foundation|NutritionLabelParsing)$'
if grep -qE '\.library\(name:[[:space:]]*"UKNutritionLabelParsing"' "$package_root/Package.swift"; then
  echo "UKNutritionLabelParsing must not be a library product; it is reached only through FoodLabelTextCapture" >&2; exit 1
fi
# Label photo reader (#316, docs/label-photo-ai-prefill-v1.md 17.2): pure, no platform framework.
check_imports FoodLabelPhotoReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'
# Pasted label AI text reader (#416 A2, docs/pasted-label-ai-text-v1.md 11.1): pure, and never the photo reader.
check_imports FoodLabelTextAIReading '^(Foundation|FoodLedgerApplication|FoodLedgerDomain|NutritionLabelParsing)$'
# Label photo capture adapters (17.2): platform frameworks, each confined to its adapter file above.
check_imports FoodLabelPhotoCapture '^(CoreGraphics|Foundation|ImageIO|Network|UniformTypeIdentifiers|Vision|FoodLedgerApplication|FoodLedgerDomain|FoodLabelPhotoReading)$'
# Label photo UI (17.2, 17.19): camera, PhotosPicker, crop, the photo pane and the Paste control
# (#454, docs/nutrition-label-entry-v1.md section 6).
check_imports FoodLabelPhotoUI '^(AVFoundation|Foundation|FoodLedgerApplication|FoodLedgerDomain|PhotosUI|SwiftUI|UIKit|UniformTypeIdentifiers)$'

# Clipboard reads (#454, docs/nutrition-label-entry-v1.md section 6): within the package sources,
# PasteButton, NSItemProvider and UIPasteboard appear only in FoodLabelPhotoUI/LabelPastePicker.swift,
# and FoodLedgerPresentation never names UTType, UniformTypeIdentifiers or NSItemProvider. Only
# SOURCES (the package's Sources directory) is scanned, so the app target's clipboard writes, such
# as Copy all, are out of scope. Prints each violation.
clipboard_violations() {
  local sources="$1" file
  if [[ ! -d "$sources" ]]; then echo "$sources: missing"; return 0; fi
  while IFS= read -r file; do
    [[ -z "$file" || "$file" == "$sources/FoodLabelPhotoUI/LabelPastePicker.swift" ]] || echo "$file reads the clipboard outside LabelPastePicker.swift"
  done < <(grep -rlE --include='*.swift' '\b(PasteButton|NSItemProvider|UIPasteboard)\b' "$sources" || true)
  if [[ -d "$sources/FoodLedgerPresentation" ]]; then
    while IFS= read -r file; do
      [[ -z "$file" ]] || echo "$file names a content type or item provider in presentation"
    done < <(grep -rlE --include='*.swift' '\b(UTType|UniformTypeIdentifiers|NSItemProvider)\b' "$sources/FoodLedgerPresentation" || true)
  fi
}
self_test_clipboard() {
  local scratch status=0 fixture
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-boundaries-clipboard.XXXXXX")"
  local base="$scratch/base" sources
  mkdir -p "$base/Packages/FoodLedgerKit/Sources/FoodLabelPhotoUI" "$base/Packages/FoodLedgerKit/Sources/FoodLedgerPresentation" \
    "$base/Packages/FoodLedgerKit/Sources/FoodLedgerApplication" "$base/WeeklyHealthReport/Views"
  sources="$base/Packages/FoodLedgerKit/Sources"
  printf 'import UniformTypeIdentifiers\nlet types: [UTType] = [.image]\nlet button = PasteButton(supportedContentTypes: types) { (providers: [NSItemProvider]) in }\nlet board = UIPasteboard.general\n' \
    > "$sources/FoodLabelPhotoUI/LabelPastePicker.swift"
  printf 'import SwiftUI\nenum NutritionLabelPasteEvent { case loading }\n' > "$sources/FoodLedgerPresentation/NutritionLabelEntryModel.swift"
  # The app target's existing clipboard writes are never flagged.
  printf 'import UniformTypeIdentifiers\nUIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]])\n' > "$base/WeeklyHealthReport/Views/DailyExportView.swift"
  printf 'UIPasteboard.general.string = text\n' > "$base/WeeklyHealthReport/Views/HealthReportView.swift"
  if [[ -n "$(clipboard_violations "$sources")" ]]; then
    echo "check-boundaries self-test: the clipboard baseline (LabelPastePicker.swift and the app's writes) must pass" >&2; status=1
  fi
  for fixture in paste_button_ui item_provider_application pasteboard_presentation renamed_picker utype_presentation \
                 uniform_types_presentation item_provider_presentation; do
    cp -R "$base" "$scratch/$fixture"
    sources="$scratch/$fixture/Packages/FoodLedgerKit/Sources"
    case "$fixture" in
      paste_button_ui) echo 'let button = PasteButton(payloadType: String.self) { _ in }' > "$sources/FoodLabelPhotoUI/LabelPhotoSourceButtons.swift" ;;
      item_provider_application) echo 'let provider = NSItemProvider()' > "$sources/FoodLedgerApplication/Leak.swift" ;;
      pasteboard_presentation) echo 'let text = UIPasteboard.general.string' > "$sources/FoodLedgerPresentation/NutritionLabelEntryView.swift" ;;
      renamed_picker) mv "$sources/FoodLabelPhotoUI/LabelPastePicker.swift" "$sources/FoodLabelPhotoUI/LabelPastePickers.swift" ;;
      utype_presentation) echo 'let types: [UTType] = []' > "$sources/FoodLedgerPresentation/Leak.swift" ;;
      uniform_types_presentation) echo '@preconcurrency import UniformTypeIdentifiers' > "$sources/FoodLedgerPresentation/Leak.swift" ;;
      item_provider_presentation) echo 'func load(_ provider: NSItemProvider) {}' >> "$sources/FoodLedgerPresentation/NutritionLabelEntryModel.swift" ;;
    esac
    if [[ -z "$(clipboard_violations "$sources")" ]]; then
      echo "check-boundaries self-test: the clipboard $fixture fixture must fail" >&2; status=1
    fi
  done
  rm -rf "$scratch"
  return "$status"
}
self_test_clipboard

# Your food database store (#424 P1b, docs/personal-food-database-import-v1-phase-1.md 3.1, change 9):
# Foundation, the application and the domain only; no network API; imported only by the
# composition root and the target's own tests; no other package target depends on it.
check_personal_database_edges() {
  local pkg="$1" app="$2" violations="" file line
  local dir="$pkg/Sources/FoodLedgerPersonalDatabase"
  if [[ -d "$dir" ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then violations+="FoodLedgerPersonalDatabase imports $line"$'\n'; fi
    done < <(find "$dir" -name '*.swift' -exec sed -nE "s/${import_attributes}([A-Za-z0-9_]+).*$/\5/p" {} + \
      | sort -u | grep -Ev '^(Foundation|FoodLedgerApplication|FoodLedgerDomain)$' || true)
    while IFS= read -r file; do
      if [[ -n "$file" ]]; then violations+="FoodLedgerPersonalDatabase names a network API in $file"$'\n'; fi
    # `contentsOf:` covers Foundation's URL-loading initialisers (Data, String); local reads go by path.
    done < <(grep -rlE --include='*.swift' '(URLSession|URLRequest|NWConnection|NWPathMonitor|contentsOf:)' "$dir" || true)
  fi
  local scanned=("$pkg/Sources" "$pkg/Tests" "$pkg/Tools" "$app/WeeklyHealthReport" "$app/WeeklyHealthReportTests")
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then continue; fi
    if [[ "$file" != "$app/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift" && ! "$file" =~ /Tests/FoodLedgerPersonalDatabaseTests/ ]]; then
      violations+="FoodLedgerPersonalDatabase imported by $file"$'\n'
    fi
  done < <(files_importing FoodLedgerPersonalDatabase "${scanned[@]}")
  # The declaration's own name is its first `name:`; only the target itself and its tests are
  # exempt, whatever dependency form (string or nested `.target(name:)`) another target uses.
  local own
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    own="$(sed -nE 's/^[^"]*name:[[:space:]]*"([^"]+)".*$/\1/p' <<<"$line")"
    if [[ "$own" != "FoodLedgerPersonalDatabase" && "$own" != "FoodLedgerPersonalDatabaseTests" ]]; then
      violations+="a package target depends on FoodLedgerPersonalDatabase: ${line:0:80}"$'\n'
    fi
  done < <(package_targets "$pkg/Package.swift" | grep -E '"FoodLedgerPersonalDatabase"' || true)
  if [[ -n "$violations" ]]; then
    printf '%s' "$violations" >&2
    return 1
  fi
}

self_test_personal_database_edges() {
  local scratch status=0
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-boundaries-pfd.XXXXXX")"
  local base="$scratch/base" pkg="$scratch/base/Packages/FoodLedgerKit"
  mkdir -p "$pkg/Sources/FoodLedgerPersonalDatabase" "$pkg/Sources/FoodLedgerApplication" "$pkg/Sources/FoodLedgerPresentation" \
    "$pkg/Tests/FoodLedgerPersonalDatabaseTests" "$base/WeeklyHealthReport/FoodLedger" "$base/WeeklyHealthReportTests"
  cat > "$pkg/Package.swift" <<'SWIFT'
let package = Package(
    name: "FoodLedgerKit",
    targets: [
        .target(name: "FoodLedgerApplication", dependencies: ["FoodLedgerDomain"]),
        .target(name: "FoodLedgerPersonalDatabase", dependencies: ["FoodLedgerApplication", "FoodLedgerDomain"]),
        .target(name: "FoodLedgerPresentation", dependencies: ["FoodLedgerApplication"]),
        .testTarget(name: "FoodLedgerPersonalDatabaseTests", dependencies: ["FoodLedgerPersonalDatabase"])
    ]
)
SWIFT
  printf 'import FoodLedgerApplication\nimport FoodLedgerDomain\nimport Foundation\n' > "$pkg/Sources/FoodLedgerPersonalDatabase/Store.swift"
  echo 'import FoodLedgerDomain' > "$pkg/Sources/FoodLedgerApplication/Port.swift"
  echo 'import SwiftUI' > "$pkg/Sources/FoodLedgerPresentation/View.swift"
  echo '@testable import FoodLedgerPersonalDatabase' > "$pkg/Tests/FoodLedgerPersonalDatabaseTests/StoreTests.swift"
  echo 'import FoodLedgerPersonalDatabase' > "$base/WeeklyHealthReport/FoodLedger/FoodLedgerCompositionRoot.swift"
  if ! check_personal_database_edges "$pkg" "$base" 2>/dev/null; then
    echo "check-boundaries self-test: the personal database baseline must pass" >&2; status=1
  fi
  local fixture target fpkg
  for fixture in grdb_import network_import url_session url_load application_import presentation_import app_import app_test_import package_edge nested_package_edge; do
    target="$scratch/$fixture"
    rm -rf "$target"; cp -R "$base" "$target"
    fpkg="$target/Packages/FoodLedgerKit"
    case "$fixture" in
      grdb_import) echo 'import GRDB' >> "$fpkg/Sources/FoodLedgerPersonalDatabase/Store.swift" ;;
      network_import) echo '@preconcurrency import Network' >> "$fpkg/Sources/FoodLedgerPersonalDatabase/Store.swift" ;;
      url_session) echo 'let session = URLSession.shared' >> "$fpkg/Sources/FoodLedgerPersonalDatabase/Store.swift" ;;
      url_load) echo 'let page = try Data(contentsOf: URL(string: "https://example.invalid")!)' >> "$fpkg/Sources/FoodLedgerPersonalDatabase/Store.swift" ;;
      application_import) echo 'import FoodLedgerPersonalDatabase' > "$fpkg/Sources/FoodLedgerApplication/Leak.swift" ;;
      presentation_import) echo 'import struct FoodLedgerPersonalDatabase.FilePersonalFoodDatabaseStore' > "$fpkg/Sources/FoodLedgerPresentation/Leak.swift" ;;
      app_import) echo 'import FoodLedgerPersonalDatabase' > "$target/WeeklyHealthReport/Leak.swift" ;;
      app_test_import) echo '@testable import FoodLedgerPersonalDatabase' > "$target/WeeklyHealthReportTests/Leak.swift" ;;
      package_edge)
        sed 's/.target(name: "FoodLedgerPresentation", dependencies: \["FoodLedgerApplication"\])/.target(name: "FoodLedgerPresentation", dependencies: ["FoodLedgerApplication", "FoodLedgerPersonalDatabase"])/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
      nested_package_edge)
        sed 's/.target(name: "FoodLedgerPresentation", dependencies: \["FoodLedgerApplication"\])/.target(name: "FoodLedgerPresentation", dependencies: ["FoodLedgerApplication", .target(name: "FoodLedgerPersonalDatabase")])/' \
          "$pkg/Package.swift" > "$fpkg/Package.swift" ;;
    esac
    if check_personal_database_edges "$fpkg" "$target" 2>/dev/null; then
      echo "check-boundaries self-test: the personal database $fixture fixture must fail" >&2; status=1
    fi
  done
  rm -rf "$scratch"
  return "$status"
}

self_test_personal_database_edges
check_personal_database_edges "$package_root" "$app_root"
clipboard_unexpected="$(clipboard_violations "$package_root/Sources")"
if [[ -n "$clipboard_unexpected" ]]; then
  echo "$clipboard_unexpected" >&2
  exit 1
fi
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

# Pasted label AI text evaluation core (#416 A1, docs/pasted-label-ai-text-v1.md 5): the case
# format, converters and bar tooling outside the package import Foundation and CryptoKit only.
# The scan covers that one directory (every Swift file under it); the self-test proves a
# forbidden import in any form fails.
tool_import_violations() {
  local dir="$1" allowed="$2"
  if [[ ! -d "$dir" ]]; then echo "$dir: missing"; return 0; fi
  find "$dir" -name '*.swift' -type f -print0 | xargs -0 sed -nE "s/${import_attributes}([A-Za-z0-9_]+).*$/\5/p" \
    | sort -u | grep -Ev "$allowed" || true
}
eval_core_allowed='^(CryptoKit|Foundation)$'
self_test_eval_core_imports() {
  local scratch status=0 fixture
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-boundaries-eval.XXXXXX")"
  mkdir -p "$scratch/base/Nested"
  printf 'import Foundation\nimport CryptoKit\n' > "$scratch/base/Case.swift"
  echo '@preconcurrency import Foundation // comment' > "$scratch/base/Nested/Strict.swift"
  if [[ -n "$(tool_import_violations "$scratch/base" "$eval_core_allowed")" ]]; then
    echo "check-boundaries self-test: the eval core baseline must pass" >&2; status=1
  fi
  for fixture in testable struct_form nested; do
    cp -R "$scratch/base" "$scratch/$fixture"
    case "$fixture" in
      testable) echo '@testable import FoodLedgerApplication' > "$scratch/$fixture/Leak.swift" ;;
      struct_form) echo 'import struct FoodLabelPhotoReading.LabelPhotoWire' > "$scratch/$fixture/Leak.swift" ;;
      nested) echo 'import NutritionLabelParsing' > "$scratch/$fixture/Nested/Leak.swift" ;;
    esac
    if [[ -z "$(tool_import_violations "$scratch/$fixture" "$eval_core_allowed")" ]]; then
      echo "check-boundaries self-test: the eval core $fixture fixture must fail" >&2; status=1
    fi
  done
  rm -rf "$scratch"
  return "$status"
}
self_test_eval_core_imports
eval_core_unexpected="$(tool_import_violations "$app_root/Tools/PastedLabelAITextEval/Sources/PastedLabelAITextEvalCore" "$eval_core_allowed")"
if [[ -n "$eval_core_unexpected" ]]; then
  echo "PastedLabelAITextEvalCore has forbidden imports:" >&2
  echo "$eval_core_unexpected" >&2
  exit 1
fi

# Pasted label AI text evaluation harness, CLI and held-out runner (#416 A2 to A4,
# docs/pasted-label-ai-text-v1.md 5.2 and 5.5): the shipped application, capture and text reader
# modules plus the pure core, nothing else. The shipped live transport may be named in exactly one
# file, PastedLabelAITextEvalHarness/LiveTransport.swift (A3's `send --live`, A4's held-out run); no
# file in the tool, that one included, may load URLs itself.
eval_harness_allowed='^(CryptoKit|Foundation|FoodLedgerApplication|FoodLabelPhotoCapture|FoodLabelTextAIReading|PastedLabelAITextEvalCore|PastedLabelAITextEvalHarness)$'
url_loading_pattern='URLSession|NSURLConnection|CFNetwork|CFStream'
live_transport_type_pattern='\bOpenRouterTransport\b'
# Prints every file under SOURCES (the tool's Sources directory) that loads URLs, or that names the
# live transport other than SOURCES/PastedLabelAITextEvalHarness/LiveTransport.swift.
tool_live_transport() {
  local sources="$1" allowed file
  if [[ ! -d "$sources" ]]; then echo "$sources: missing"; return 0; fi
  allowed="$sources/PastedLabelAITextEvalHarness/LiveTransport.swift"
  grep -rlE --include='*.swift' "$url_loading_pattern" "$sources" || true
  while IFS= read -r file; do
    [[ -z "$file" || "$file" == "$allowed" ]] || echo "$file"
  done < <(grep -rlE --include='*.swift' "$live_transport_type_pattern" "$sources" || true)
}
self_test_eval_harness() {
  local scratch status=0 fixture
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-boundaries-harness.XXXXXX")"
  mkdir -p "$scratch/base/PastedLabelAITextEvalHarness" "$scratch/base/PastedLabelAITextEval" "$scratch/base/PastedLabelAITextHeldOut"
  printf 'import FoodLabelPhotoCapture\nimport FoodLabelTextAIReading\nimport PastedLabelAITextEvalCore\n' > "$scratch/base/PastedLabelAITextEvalHarness/Send.swift"
  printf 'import FoodLabelPhotoCapture\nlet transport = OpenRouterTransport()\n' > "$scratch/base/PastedLabelAITextEvalHarness/LiveTransport.swift"
  printf 'import PastedLabelAITextEvalHarness\n' > "$scratch/base/PastedLabelAITextEval/main.swift"
  printf 'import PastedLabelAITextEvalHarness\nlet connection = LiveTransport.connection(key: key)\n' > "$scratch/base/PastedLabelAITextHeldOut/main.swift"
  if [[ -n "$(tool_import_violations "$scratch/base" "$eval_harness_allowed")" || -n "$(tool_live_transport "$scratch/base")" ]]; then
    echo "check-boundaries self-test: the eval harness baseline (the live transport in LiveTransport.swift only) must pass" >&2; status=1
  fi
  for fixture in parser photo_reader live_transport live_transport_type url_session cli_live_transport nested_live_transport \
                 renamed_live_transport allowed_file_url_session allowed_file_configuration allowed_file_cfnetwork \
                 heldout_parser heldout_photo_reader heldout_live_transport heldout_url_session; do
    cp -R "$scratch/base" "$scratch/$fixture"
    local harness="$scratch/$fixture/PastedLabelAITextEvalHarness"
    case "$fixture" in
      parser) echo 'import NutritionLabelParsing' > "$harness/Leak.swift" ;;
      photo_reader) echo '@testable import FoodLabelPhotoReading' > "$harness/Leak.swift" ;;
      live_transport) echo 'let transport = OpenRouterTransport()' > "$harness/Leak.swift" ;;
      live_transport_type) echo 'let transport: OpenRouterTransport = .init()' > "$harness/Leak.swift" ;;
      url_session) echo 'let session = URLSession.shared' > "$harness/Leak.swift" ;;
      cli_live_transport) echo 'let transport = OpenRouterTransport()' > "$scratch/$fixture/PastedLabelAITextEval/LiveTransport.swift" ;;
      nested_live_transport)
        mkdir -p "$harness/Nested"; echo 'let transport = OpenRouterTransport()' > "$harness/Nested/LiveTransport.swift" ;;
      renamed_live_transport)
        mv "$harness/LiveTransport.swift" "$harness/LiveTransports.swift" ;;
      allowed_file_url_session) echo 'let session = URLSession.shared' >> "$harness/LiveTransport.swift" ;;
      allowed_file_configuration) echo 'let configuration = URLSessionConfiguration.ephemeral' >> "$harness/LiveTransport.swift" ;;
      allowed_file_cfnetwork) echo 'import CFNetwork' >> "$harness/LiveTransport.swift" ;;
      heldout_parser) echo 'import NutritionLabelParsing' > "$scratch/$fixture/PastedLabelAITextHeldOut/Leak.swift" ;;
      heldout_photo_reader) echo '@testable import FoodLabelPhotoReading' >> "$scratch/$fixture/PastedLabelAITextHeldOut/main.swift" ;;
      heldout_live_transport) echo 'let transport = OpenRouterTransport()' >> "$scratch/$fixture/PastedLabelAITextHeldOut/main.swift" ;;
      heldout_url_session) echo 'let session = URLSession.shared' > "$scratch/$fixture/PastedLabelAITextHeldOut/Leak.swift" ;;
    esac
    if [[ -z "$(tool_import_violations "$scratch/$fixture" "$eval_harness_allowed")" && -z "$(tool_live_transport "$scratch/$fixture")" ]]; then
      echo "check-boundaries self-test: the eval harness $fixture fixture must fail" >&2; status=1
    fi
  done
  rm -rf "$scratch"
  return "$status"
}
self_test_eval_harness
for dir in PastedLabelAITextEvalHarness PastedLabelAITextEval PastedLabelAITextHeldOut; do
  harness_dir="$app_root/Tools/PastedLabelAITextEval/Sources/$dir"
  harness_unexpected="$(tool_import_violations "$harness_dir" "$eval_harness_allowed")"
  if [[ -n "$harness_unexpected" ]]; then
    echo "$dir has forbidden imports:" >&2
    echo "$harness_unexpected" >&2
    exit 1
  fi
done
live_transport_files="$(tool_live_transport "$app_root/Tools/PastedLabelAITextEval/Sources")"
if [[ -n "$live_transport_files" ]]; then
  echo "PastedLabelAITextEval loads URLs, or names the live transport outside PastedLabelAITextEvalHarness/LiveTransport.swift:" >&2
  echo "$live_transport_files" >&2
  exit 1
fi

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
