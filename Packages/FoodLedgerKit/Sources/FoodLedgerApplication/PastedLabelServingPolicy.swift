import Foundation
import FoodLedgerDomain

/// Closed serving policy for pasted labels (contract section 6.3), a sibling of
/// `food-source-declared-serving-v1`. Two append-only method versions, chosen by the stored
/// column and never by the user:
///
/// `pasted-label-serving-v1`, a stored per-serving column:
/// - case 2, `perServing(q)` with q in grams or millilitres: servings are converted through the
///   printed serving size (n servings = n × q), recorded as a quantity conversion whose method
///   is v1; an amount in q's unit is also accepted, as for any basis;
/// - case 3, `perServing(1 count)` (no readable serving size): servings only.
///
/// `pasted-label-serving-v2` (owner, in session, 19 October 2026), a stored per 100 g (per
/// 100 ml) column with an exact serving size q in grams (millilitres), printed, or corrected or
/// entered by the user on Confirm: n servings are the quantity n × q, scaled against the per-100
/// basis, recorded exactly like a v1 conversion but under v2. A serving size in the other unit,
/// or one printed as approximate ("about"), offers no servings. Grams or millilitres are
/// accepted as for any per-100 basis.
///
/// Nothing is inferred: no weight is ever given to a case 3 serving, and no serving size is
/// taken from the other column. The source must be a pasted-label release; save verification of
/// its manifest still runs before policy. v1 is unchanged: its records keep their bytes and
/// decode, reopen and re-save exactly as before.
public enum PastedLabelServingPolicy {
    /// The per-serving method (stored column per serving).
    public static let version = "pasted-label-serving-v1"
    /// The per-100 method (stored column per 100 g or per 100 ml, with a qualifying serving size).
    public static let per100Version = "pasted-label-serving-v2"
    /// Append-only: every method a stored pasted-label servings conversion may name.
    public static let admittedVersions = [version, per100Version]

    /// Printed approximation markers that disqualify a printed serving size under v2 (contract
    /// section 6.3; fixed for v2, any change is a new version). They are looked for only in the
    /// serving-size segment (`servingSegment`): English words matched whole and
    /// case-insensitively, the other marks as substrings, and a numeric range.
    public static let approximateWords: Set<String> = ["about", "approx", "approximately", "around", "circa", "roughly"]
    public static let approximateMarks = ["約", "约", "~", "～", "〜", "≈", "≒", "±"]
    /// A numeric range within the segment: a digit, up to three non-space unit characters (so "30g-35g" and
    /// "30公克至35公克" count), optional spaces, one of - – ~ ～ 〜 至, optional spaces, a digit.
    static let rangePattern = try! NSRegularExpression(pattern: #"[0-9][^0-9\s]{0,3}\s*[-–~～〜至]\s*[0-9]"#)
    /// A listed word or a non-range mark written straight after the quantity: optional spaces, an
    /// optional opening bracket, optional spaces, then the word (whole, any case, an optional "."
    /// and closing bracket after it) or one of 約 约 ≈ ≒. "30g approx.", "30g (about 2 biscuits)"
    /// and "30公克（約2片）" are approximate under this rule.
    static let trailingWordPattern = try! NSRegularExpression(
        pattern: #"^\s*[(（]?\s*(?:(?:about|approx|approximately|around|circa|roughly)(?![A-Za-z])\.?\s*[)）]?|[約约≈≒])"#,
        options: [.caseInsensitive])

    /// The serving quantity and the method that applies to the selection, or nil.
    public static func resolved(_ input: PopulatedFoodConfirmation,
                                candidate: PopulatedFoodCandidate) -> (serving: PositiveQuantity, method: String)? {
        let source = candidate.candidate
        guard input.sourceReleases.contains(where: { $0.sourceReleaseID == source.sourceReleaseID
                  && $0.sourceID.value == PastedLabelSource.sourceID }),
              let manifest = manifest(input, candidate: candidate) else { return nil }
        switch source.identity.servingBasis {
        case let .perServing(serving): return (serving, version)
        case .per100Grams: return per100Serving(manifest, unit: .grams).map { ($0, per100Version) }
        case .per100Millilitres: return per100Serving(manifest, unit: .millilitres).map { ($0, per100Version) }
        case .perUnit, .named, .unknown: return nil
        }
    }

    /// The serving quantity when either method applies.
    public static func serving(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PositiveQuantity? {
        resolved(input, candidate: candidate)?.serving
    }

    /// The method a servings amount is recorded under for this selection.
    public static func method(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> String? {
        resolved(input, candidate: candidate)?.method
    }

    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate) != nil
    }

    /// Case 3: the serving has no weight or volume, so only servings are offered.
    public static func servingsOnly(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate)?.unit == .count
    }

    /// The whole-pack amount option (contract section 2.3): the servings in one pack, from a
    /// printed exact servings-per-pack line or, when none is printed, the value the user entered
    /// (shown "Entered by you"). Offered whenever servings convert through a serving quantity in
    /// grams or millilitres: a per-serving column under v1, or a per-100 column with a qualifying
    /// serving size under v2. A whole pack is then logged as that many servings, through the same
    /// conversion as any servings amount. "About" is never a whole pack.
    public static func wholePack(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PastedLabelWholePack? {
        guard let serving = serving(input, candidate: candidate), serving.unit != .count,
              let manifest = manifest(input, candidate: candidate) else { return nil }
        if let printed = manifest.candidate.servingsPerPack {
            guard !printed.approximate, let count = PastedLabelSource.amount(printed.decimalText), count > 0 else { return nil }
            return PastedLabelWholePack(servings: count, origin: .printed)
        }
        guard let index = manifest.corrections.firstIndex(where: { $0.nutrient == PastedLabelManifest.Correction.servingsPerPack }),
              let count = PastedLabelSource.amount(manifest.corrections[index].corrected.decimalText), count > 0 else { return nil }
        return PastedLabelWholePack(servings: count, origin: .enteredByYou(correctionIndex: index))
    }

    /// The conversion recorded for n servings through a serving quantity in grams or millilitres:
    /// n × q in q's unit, citing the pasted release and its manifest evidence, under `method`
    /// (v1 unless given). Nil for a case 3 serving, where servings are stored as counted.
    public static func conversion(servings: PositiveQuantity, serving: PositiveQuantity, candidate: PopulatedFoodCandidate,
                                  method: String = version) throws -> QuantityConversionDraft? {
        guard servings.unit == .count, serving.unit != .count else { return nil }
        return QuantityConversionDraft(convertedQuantity: try PositiveQuantity(value: servings.value * serving.value, unit: serving.unit),
            methodVersion: try LedgerText(method), sourceReleaseID: candidate.candidate.sourceReleaseID,
            evidenceID: candidate.candidate.evidenceIDs.first)
    }

    /// Reopen verification of a stored conversion that names an admitted pasted-label method: it
    /// must be exactly the conversion this policy records for its source quantity on this label,
    /// under the method the stored column selects.
    public static func verifies(_ stored: QuantityConversionVersion, input: PopulatedFoodConfirmation,
                                candidate: PopulatedFoodCandidate) -> Bool {
        guard let resolved = resolved(input, candidate: candidate), stored.methodVersion.value == resolved.method,
              let expected = try? conversion(servings: stored.sourceQuantity, serving: resolved.serving, candidate: candidate,
                                             method: resolved.method) else { return false }
        return stored.convertedQuantity == expected.convertedQuantity && stored.sourceReleaseID == expected.sourceReleaseID
            && stored.evidenceID == expected.evidenceID
    }

    /// Whether a saved amount was entered in a pasted label's servings: a count recorded through
    /// either method's conversion, or (v1 case 3) a count with no conversion on a pasted-label
    /// release. A count on a pasted label with an ordinary measured conversion is not servings.
    public static func isServingsAmount(enteredUnit: QuantityUnit, conversion: QuantityConversionVersion?, sourceID: String?) -> Bool {
        guard enteredUnit == .count else { return false }
        if let conversion { return admittedVersions.contains(conversion.methodVersion.value) }
        return sourceID == PastedLabelSource.sourceID
    }

    /// The serving size a stored servings amount went through, and where it came from (printed,
    /// corrected by you or entered by you). Nil when servings carry no weight or volume (v1 case 3).
    public static func storedServingSize(_ manifest: PastedLabelManifest, basis: ResolutionBasis)
        -> (quantity: PositiveQuantity, origin: NutrientValueOrigin)? {
        let entry = manifest.corrections.first { $0.nutrient == PastedLabelManifest.Correction.servingSize }
        let origin: NutrientValueOrigin = entry.map { $0.kind == .corrected ? .correctedByYou : .enteredByYou } ?? .printed
        switch basis {
        case let .perServing(quantity) where quantity.unit != .count: return (quantity, origin)
        case .per100Grams: return per100Serving(manifest, unit: .grams).map { ($0, origin) }
        case .per100Millilitres: return per100Serving(manifest, unit: .millilitres).map { ($0, origin) }
        default: return nil
        }
    }

    /// The manifest bound to the candidate through its pasted-label evidence.
    static func manifest(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PastedLabelManifest? {
        guard let evidence = input.evidence.first(where: { candidate.candidate.evidenceIDs.contains($0.evidenceID)
                  && $0.captureMethodVersion.value == PastedLabelManifest.version }),
              case let .text(payload) = evidence.originalPayload else { return nil }
        return PastedLabelManifest.decode(Data(payload.value.utf8))
    }

    /// v2: the user's serving-size correction or entry when there is one (validated as for any
    /// column), else the printed serving size unless it is printed as approximate; only in the
    /// unit of the per-100 basis.
    static func per100Serving(_ manifest: PastedLabelManifest, unit: QuantityUnit) -> PositiveQuantity? {
        let size: PositiveQuantity?
        do {
            if let corrected = try PastedLabelSource.servingSizeCorrection(manifest) {
                size = corrected
            } else if let printed = manifest.candidate.servingSize, let segment = servingSegment(printed), !approximate(segment) {
                size = PastedLabelSource.servingQuantity(printed)
            } else {
                size = nil
            }
        } catch {
            return nil
        }
        guard let size, size.unit == unit else { return nil }
        return size
    }

    /// The serving-size segment of a printed serving-size line (contract section 6.3), located
    /// exactly as `nutrition-label-text-parser-v2` located the recorded quantity
    /// (`PastedLabelServingSizeGrammar`, pinned to the parser by a parity test):
    /// 1. the value is the label pattern's capture group;
    /// 2. the quantity is the first quantity match inside the first bracketed group of the value,
    ///    else the first quantity match in the value, and must be the recorded `decimal_text` and
    ///    `unit` (otherwise nil, which never offers servings);
    /// 3. the segment runs from the start of the value to the end of that quantity, plus a tail
    ///    written straight after it: a tolerance or range whose number is followed by the same
    ///    unit or ends the value ("30g-35g", "30 g ± 2 g", "30g±2"), or a listed word or
    ///    non-range mark (`trailingWordPattern`). Anything else after the quantity is not scanned.
    public static func servingSegment(_ size: PastedLabelManifest.Candidate.ServingSize) -> String? {
        guard let decimal = size.decimalText, let unit = size.unit else { return nil }
        let text = size.printedText
        typealias G = PastedLabelServingSizeGrammar
        guard let label = G.label.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(label.range(at: 1), in: text) else { return nil }
        let value = String(text[valueRange])
        let whole = NSRange(value.startIndex..., in: value)
        var quantity: NSTextCheckingResult?
        if let bracket = G.parenthesised.firstMatch(in: value, range: whole) {
            quantity = G.quantity.firstMatch(in: value, range: bracket.range(at: 1))
        }
        quantity = quantity ?? G.quantity.firstMatch(in: value, range: whole)
        guard let match = quantity, let range = Range(match.range, in: value),
              let number = Range(match.range(at: 1), in: value), let matchedUnit = Range(match.range(at: 2), in: value),
              String(value[number]) == decimal, String(value[matchedUnit]) == unit else { return nil }
        let after = String(value[range.upperBound...])
        let afterRange = NSRange(after.startIndex..., in: after)
        let tolerance = try? NSRegularExpression(pattern: #"^\s*[±\-–~～〜至]\s*[0-9][0-9.]*\s*(?:"#
            + NSRegularExpression.escapedPattern(for: unit) + #"(?![\p{L}])|$)"#)
        if let match = tolerance?.firstMatch(in: after, range: afterRange), let tail = Range(match.range, in: after) {
            return String(value[..<range.upperBound]) + String(after[tail])
        }
        guard let word = trailingWordPattern.firstMatch(in: after, range: afterRange), let tail = Range(word.range, in: after) else {
            return String(value[..<range.upperBound])
        }
        // Inside a bracket, a marker followed by a count of something that is not a weight or
        // volume ("（約2片）", "(about 2 biscuits)") qualifies that count, not the serving size.
        let marker = String(after[tail])
        let rest = String(after[tail.upperBound...])
        if marker.contains(where: { $0 == "(" || $0 == "（" }), countsPieces(rest) {
            return String(value[..<range.upperBound])
        }
        return String(value[..<range.upperBound]) + marker
    }

    /// A number followed by a token that is not a weight or volume unit: optional spaces, a
    /// number, optional spaces, a letter, where the number and token are not a weight or volume
    /// (`weightOrVolumePattern`).
    static func countsPieces(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return countPattern.firstMatch(in: text, range: range) != nil && weightOrVolumePattern.firstMatch(in: text, range: range) == nil
    }

    static let countPattern = try! NSRegularExpression(pattern: #"^\s*[0-9]+(?:\.[0-9]+)?\s*\p{L}"#)
    /// The grammar's units (g, ml, mL, 公克, 毫升, 克, not followed by a letter), plus a closed
    /// list of other weight and volume words that keep a bracketed marker approximate.
    static let weightOrVolumePattern = try! NSRegularExpression(
        pattern: #"^\s*[0-9]+(?:\.[0-9]+)?\s*(?:(?:g|ml|mL|公克|毫升|克)(?![\p{L}])|(?:grams?|gramme?s?|millilit(?:re|er)s?|mg|kg|oz|l|litres?|liters?|毫克|公斤|公升|升)(?![\p{L}]))"#,
        options: [.caseInsensitive])

    /// Whether a serving-size segment is approximate: a listed mark, a listed whole English word,
    /// or a numeric range.
    public static func approximate(_ segment: String) -> Bool {
        if approximateMarks.contains(where: { segment.contains($0) }) { return true }
        if rangePattern.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)) != nil { return true }
        let words = segment.lowercased().split { !($0.isASCII && $0.isLetter) }.map(String.init)
        return words.contains { approximateWords.contains($0) }
    }
}

/// The servings in one pack and where that number came from.
public struct PastedLabelWholePack: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case printed
        /// Entered on Confirm, recorded as the manifest's correction at this index.
        case enteredByYou(correctionIndex: Int)
    }
    public let servings: Double
    public let origin: Origin
    public init(servings: Double, origin: Origin) { self.servings = servings; self.origin = origin }
}

extension FoodConfirmationState {
    /// The pasted-label serving quantity when `pasted-label-serving-v1` or `-v2` applies to the selection.
    public var pastedLabelServing: PositiveQuantity? { PastedLabelServingPolicy.serving(input, candidate: selectedCandidate) }

    /// The pasted-label serving method that applies to the selection, if any.
    var pastedLabelServingMethod: String? { PastedLabelServingPolicy.method(input, candidate: selectedCandidate) }

    /// Whether the entered amount is in servings under a pasted-label serving method.
    var logsPastedLabelServings: Bool { pastedLabelServing != nil && quantity.unit == .count }

    /// Servings must be a plain count: no direct weight, plate or conversion other than the
    /// applicable method's own (kept on a reopened entry). Case 3 accepts nothing but servings.
    /// A conversion naming a pasted-label method the selection does not use is never accepted.
    var pastedLabelServingMisuse: Bool {
        let method = pastedLabelServingMethod
        if let named = quantity.conversion?.methodVersion.value, named != method,
           PastedLabelServingPolicy.admittedVersions.contains(named) {
            return true
        }
        guard let serving = pastedLabelServing else { return false }
        if quantity.unit != .count { return serving.unit == .count }
        return quantity.directWeight != nil || quantity.plateChoice != .foodOnly
            || (quantity.conversion.map { $0.methodVersion.value != method } ?? false)
    }

    /// The quantity the save path records. Servings of a pasted label carry the method's
    /// conversion through a weight or volume serving, recomputed from the count (never a stale
    /// draft), and none in case 3. A conversion naming a pasted-label method that does not
    /// apply is refused on any path.
    func policyQuantity() throws -> FoodQuantityDraft {
        guard logsPastedLabelServings, let serving = pastedLabelServing, let method = pastedLabelServingMethod else {
            if let named = quantity.conversion?.methodVersion.value, named != pastedLabelServingMethod,
               PastedLabelServingPolicy.admittedVersions.contains(named) {
                throw FoodLedgerValidationError.invalidUnit
            }
            return quantity
        }
        guard !pastedLabelServingMisuse else { throw FoodLedgerValidationError.invalidUnit }
        var draft = quantity
        draft.conversion = try PastedLabelServingPolicy.conversion(servings: quantity.calculationInput(), serving: serving,
                                                                   candidate: selectedCandidate, method: method)
        return draft
    }
}
