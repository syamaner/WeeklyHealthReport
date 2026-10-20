import Foundation
import FoodLedgerDomain

/// Closed serving policy for pasted labels (contract section 6.3), a sibling of
/// `food-source-declared-serving-v1`. Three append-only method versions, chosen by the stored
/// column and the manifest's parser version (`methods(parserVersion:)`), never by the user:
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
/// `pasted-label-serving-v3` (reader v3 section 5.6, decision 12), a stored per 100 g (per
/// 100 ml) column of a parser-v3 manifest: v2's rules, with the serving value located by
/// parser v3's grammar (`PastedLabelServingSizeGrammarV3`), cut at a pack phrase on the same line,
/// and a bilingual line scanned for approximation outside the segment too.
///
/// Nothing is inferred: no weight is ever given to a case 3 serving, and no serving size is
/// taken from the other column. The source must be a pasted-label release; save verification of
/// its manifest still runs before policy. v1 is unchanged: its records keep their bytes and
/// decode, reopen and re-save exactly as before.
public enum PastedLabelServingPolicy {
    /// The per-serving method (stored column per serving).
    public static let version = "pasted-label-serving-v1"
    /// The per-100 method of a parser-v2 manifest (stored column per 100 g or per 100 ml, with a
    /// qualifying serving size).
    public static let per100Version = "pasted-label-serving-v2"
    /// The per-100 method of a parser-v3 manifest (reader v3 section 5.6).
    public static let per100VersionV3 = "pasted-label-serving-v3"
    /// Append-only: every method a stored pasted-label servings conversion may name.
    public static let admittedVersions = [version, per100Version, per100VersionV3]

    /// The closed method table of reader v3 section 5.6: the methods for a per-serving and a per
    /// 100 g or ml stored column, by the manifest's `parser_version`. Any other parser version has
    /// none: Confirm offers no servings and no whole pack, a servings conversion is refused at
    /// save and a stored one fails reopen.
    public static func methods(parserVersion: String) -> (perServing: String, per100: String)? {
        switch parserVersion {
        case PastedLabelSource.parserVersionV2: (version, per100Version)
        case PastedLabelSource.parserVersionV3: (version, per100VersionV3)
        default: nil
        }
    }

    /// Printed approximation markers that disqualify a printed serving size under v2 (contract
    /// section 6.3; fixed for v2). They are looked for only in the serving-size segment
    /// (`servingSegment`): English words matched whole and case-insensitively, the other marks as
    /// substrings, and a numeric range (`rangePattern`).
    public static let approximateWords: Set<String> = ["about", "approx", "approximate", "approximately", "around", "ca", "circa",
                                                       "roughly"]
    public static let approximateMarks = ["約", "约", "~", "～", "〜", "≈", "≒", "±", "+/-", "+-", "左右", "上下"]
    /// The range marks: every dash punctuation character (`\p{Pd}`: hyphen-minus, hyphen,
    /// non-breaking hyphen, figure dash, en dash, em dash, horizontal bar, small and full-width
    /// hyphen-minus, wave dash and the rest), the minus sign −, box-drawing ─, swung dash ⁓, wavy
    /// low line ﹏, the tildes ~ ～, 至 and 到; 一 and ー only between digits (OCR); and the whole
    /// word "to" (any case).
    static let rangeMarks = #"(?:[\p{Pd}−─⁓﹏~～〜至到]|(?<=[0-9]\s{0,2})[一ー](?=\s{0,2}[0-9])|(?<![A-Za-z])to(?![A-Za-z]))"#
    /// A numeric range within the segment: a digit, optional spaces, up to three non-space unit
    /// characters, optional spaces, a range mark, optional spaces, a digit ("25-30g", "30g-35g",
    /// "30 g - 35 g", "25 to 30 g", "30公克至35公克"). Groups 1 and 2 are the two numbers.
    static let rangePattern = try! NSRegularExpression(
        pattern: #"([0-9][0-9.]*)\s*[^0-9\s]{0,3}?\s*"# + rangeMarks + #"\s*([0-9][0-9.]*)"#, options: [.caseInsensitive])
    /// Separators allowed before a trailing word or mark: spaces, `,` `，` `、` `/` `／`.
    static let separators = #"[\s,，、/／]*"#
    /// A listed word (whole, any case, an optional "." and closing bracket after it) or one of
    /// 約 约 ≈ ≒ 左右.
    static let marker = #"(?:(?:about|approx|approximate|approximately|around|ca|circa|roughly)(?![A-Za-z])\.?\s*[)）]?|[約约≈≒]|左右|上下)"#
    /// A word or mark written straight after the quantity, after optional separators and an
    /// optional opening bracket: "30g approx.", "30g, approx.", "30公克，約", "30公克 左右",
    /// "30g (approx.)". Inside a bracket it is subject to the piece-count exception (`countsPieces`).
    static let trailingWordPattern = try! NSRegularExpression(pattern: "^" + separators + #"[(（]?\s*"# + marker,
                                                              options: [.caseInsensitive])
    /// A word or mark after a bracket next to the quantity: after a whole bracket group that
    /// follows the quantity ("30g (2 biscuits) approx.", "30g (2 biscuits) (approx.)"), or after
    /// the closing bracket of the group the quantity was bound in ("2 biscuits (30g) approx.",
    /// "2片（30公克）約"), with optional separators and an optional opening bracket before it.
    static let afterBracketWordPattern = try! NSRegularExpression(
        pattern: #"^(?:\s*[(（][^)）]*[)）]|\s*[)）])"# + separators + #"[(（]?\s*"# + marker, options: [.caseInsensitive])
    /// The closed weight and volume units, matched case-insensitively and not followed by a
    /// letter: the grammar's g, ml, mL, 公克, 毫升, 克, plus gram(s), gramme(s), gm, gms,
    /// millilitre(s), milliliter(s), mg, kg, oz, ounce(s), fl oz, fl. oz, l, litre(s), liter(s),
    /// 毫克, 公斤, 公升, 升.
    static let weightOrVolumeUnits = #"(?:g|ml|公克|毫升|克|grams?|grammes?|gms?|millilit(?:re|er)s?|mg|kg|oz|ounces?|fl\.?\s*oz|l|litres?|liters?|毫克|公斤|公升|升)(?![\p{L}])"#

    /// The serving quantity and the method that applies to the selection, or nil.
    public static func resolved(_ input: PopulatedFoodConfirmation,
                                candidate: PopulatedFoodCandidate) -> (serving: PositiveQuantity, method: String)? {
        let source = candidate.candidate
        guard input.sourceReleases.contains(where: { $0.sourceReleaseID == source.sourceReleaseID
                  && $0.sourceID.value == PastedLabelSource.sourceID }),
              let manifest = manifest(input, candidate: candidate),
              let methods = methods(parserVersion: manifest.parserVersion) else { return nil }
        switch source.identity.servingBasis {
        case let .perServing(serving): return (serving, methods.perServing)
        case .per100Grams: return per100Serving(manifest, unit: .grams).map { ($0, methods.per100) }
        case .per100Millilitres: return per100Serving(manifest, unit: .millilitres).map { ($0, methods.per100) }
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
        guard methods(parserVersion: manifest.parserVersion) != nil else { return nil }
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

    /// v2 and v3: the user's serving-size correction or entry when there is one (validated as for
    /// any column), else the printed serving size if the manifest's method reads it as exact; only
    /// in the unit of the per-100 basis.
    static func per100Serving(_ manifest: PastedLabelManifest, unit: QuantityUnit) -> PositiveQuantity? {
        let size: PositiveQuantity?
        do {
            if let corrected = try PastedLabelSource.servingSizeCorrection(manifest) {
                size = corrected
            } else if let printed = manifest.candidate.servingSize, exactness(printed, parserVersion: manifest.parserVersion) == .exact {
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
    /// 3. the segment runs from the start of the value to the end of that quantity, plus at most
    ///    one tail, tried in order: ± or +/- (always); a range mark whose number is followed by the
    ///    same unit, a listed weight or volume unit, or the end of the value; a listed word or mark
    ///    after a bracket next to the quantity (`afterBracketWordPattern`); a listed word or mark
    ///    straight after the quantity (`trailingWordPattern`), except a bracketed marker on a piece
    ///    count (`countsPieces`). Anything else after the quantity is not scanned.
    public static func servingSegment(_ size: PastedLabelManifest.Candidate.ServingSize) -> String? {
        located(size)?.segment
    }

    /// The segment and the position of the recorded quantity's number in it (the segment is a
    /// prefix of the value, so positions are shared).
    static func located(_ size: PastedLabelManifest.Candidate.ServingSize) -> (segment: String, number: NSRange)? {
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
        let numberRange = match.range(at: 1)
        let base = String(value[..<range.upperBound])
        return (base + segmentTail(String(value[range.upperBound...]), unit: unit), numberRange)
    }

    /// The tail v2 step 3 adds to the segment from the text after the recorded quantity, or "".
    static func segmentTail(_ after: String, unit: String) -> String {
        let afterRange = NSRange(after.startIndex..., in: after)
        func matched(_ pattern: NSRegularExpression?) -> String? {
            pattern?.firstMatch(in: after, range: afterRange).flatMap { Range($0.range, in: after) }.map { String(after[$0]) }
        }
        // ± straight after the quantity always joins it: "30g ± 2%", "30 g ±".
        if let tolerance = matched(plusMinusPattern) { return tolerance }
        // A tilde or wave dash with no number after it joins it: "30g ~", "30g 〜" (not "30g ~ 2 pieces").
        if let tilde = matched(trailingTildePattern) { return tilde }
        // A range mark joins it when its number is followed by the same unit, any listed weight or
        // volume unit, or the end of the value: "30g-35g", "30g-35 grams", "30g~35".
        let rangeTail = try? NSRegularExpression(pattern: #"^\s*"# + rangeMarks + #"\s*[0-9][0-9.]*\s*(?:"#
            + NSRegularExpression.escapedPattern(for: unit) + #"(?![\p{L}])|"# + weightOrVolumeUnits + "|$)", options: [.caseInsensitive])
        if let tail = matched(rangeTail) { return tail }
        if let tail = matched(afterBracketWordPattern) { return tail }
        guard let tail = matched(trailingWordPattern) else { return "" }
        // Inside a bracket, a marker followed by a count of something that is not a weight or
        // volume ("（約2片）", "(about 2 biscuits)") qualifies that count, not the serving size.
        let rest = String(after.dropFirst(tail.count))
        if tail.contains(where: { $0 == "(" || $0 == "（" }), countsPieces(rest) { return "" }
        return tail
    }

    static let plusMinusPattern = try! NSRegularExpression(pattern: #"^\s*(?:±|\+/-|\+-)"#)
    /// A tilde ~, full-width tilde ～ or wave dash 〜 after the quantity with no number after it.
    static let trailingTildePattern = try! NSRegularExpression(pattern: #"^\s*+[~～〜]\s*+(?![0-9])"#)
    /// "c." or "c.a." directly before a number (at most one space between): "c. 30g", "c.30g",
    /// "c.a. 30g". A bare "c" is not a marker (it may be a cup), nor is "c." before anything else.
    static let circaAbbreviationPattern = try! NSRegularExpression(pattern: #"(?<![A-Za-z])c\.(?:a\.)?\s?[0-9]"#,
                                                                   options: [.caseInsensitive])

    /// A number followed by a token that is not a weight or volume: optional spaces, a number,
    /// optional spaces, a letter, where the number and token are not a listed weight or volume
    /// (`weightOrVolumeUnits`).
    static func countsPieces(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return countPattern.firstMatch(in: text, range: range) != nil && weightOrVolumePattern.firstMatch(in: text, range: range) == nil
    }

    static let countPattern = try! NSRegularExpression(pattern: #"^\s*[0-9]+(?:\.[0-9]+)?\s*\p{L}"#)
    static let weightOrVolumePattern = try! NSRegularExpression(pattern: #"^\s*[0-9]+(?:\.[0-9]+)?\s*"# + weightOrVolumeUnits,
                                                                options: [.caseInsensitive])

    /// How v2 reads a printed serving size: the one decision used by the policy and shown on
    /// Confirm (contract section 6.3).
    public enum Exactness: Equatable, Sendable {
        case exact
        /// A listed word or mark, ± or +/-.
        case approximate
        /// A numeric range. `own` is the serving size's own range, shown on Confirm; nil when the
        /// range is elsewhere in the segment ("2-3 biscuits (30g)", "1 bar - 30g"). Either way no
        /// servings are offered.
        case range(own: PrintedRange?)
        /// The recorded quantity cannot be found in the printed line (or none was read).
        case unmatched
    }

    /// The two printed numbers of a serving size's own range.
    public struct PrintedRange: Equatable, Sendable {
        public let low: String
        public let high: String
        public init(low: String, high: String) { self.low = low; self.high = high }
    }

    public static func exactness(_ size: PastedLabelManifest.Candidate.ServingSize) -> Exactness {
        guard let (segment, number) = located(size) else { return .unmatched }
        let matches = rangePattern.matches(in: segment, range: NSRange(segment.startIndex..., in: segment))
        guard !matches.isEmpty else { return approximate(segment) ? .approximate : .exact }
        let recorded = size.unit.flatMap(unitFamily)
        return .range(own: matches.lazy.compactMap { ownRange($0, in: segment, number: number, recordedUnit: recorded) }.first)
    }

    /// How the method for `parserVersion` reads a printed serving size (reader v3 section 5.6):
    /// v2's reading for a parser-v2 manifest, v3's for a parser-v3 manifest, and `unmatched` (no
    /// servings) for any other parser version.
    public static func exactness(_ size: PastedLabelManifest.Candidate.ServingSize, parserVersion: String) -> Exactness {
        switch parserVersion {
        case PastedLabelSource.parserVersionV2: exactness(size)
        case PastedLabelSource.parserVersionV3: exactnessV3(size)
        default: .unmatched
        }
    }

    // MARK: pasted-label-serving-v3 (reader v3 section 5.6)

    /// The serving value of a parser-v3 serving line: the label pattern's capture group (step 2),
    /// cut at the first pack phrase with trailing spaces and `,` `，` `、` `/` `／` removed (step 3).
    public static func valueV3(_ printedText: String) -> String? {
        typealias G = PastedLabelServingSizeGrammarV3
        guard let label = G.label.firstMatch(in: printedText, range: NSRange(printedText.startIndex..., in: printedText)),
              let valueRange = Range(label.range(at: 1), in: printedText) else { return nil }
        let value = String(printedText[valueRange])
        guard let pack = G.packPhrase.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let packRange = Range(pack.range, in: value) else { return value }
        var head = String(value[..<packRange.lowerBound])
        while let last = head.last, last.isWhitespace || ",，、/／".contains(last) { head.removeLast() }
        return head
    }

    /// Steps 4 and 5: the quantity located as v2 does, in the value from step 3, and the segment
    /// as v2 step 3, with one v3 tail rule first: a tilde or wave dash followed by a bracketed or
    /// 約/about piece count ("30公克～約2片", "30公克～（2片）") is that count, as the bracket
    /// piece-count exception, so the segment ends at the quantity. A tilde before a weight or
    /// volume ("30g ~ 35g", "30公克～約35公克") is still a range or a mark.
    public static func locatedV3(_ size: PastedLabelManifest.Candidate.ServingSize) -> (segment: String, number: NSRange, value: String)? {
        guard let decimal = size.decimalText, let unit = size.unit, let value = valueV3(size.printedText) else { return nil }
        typealias G = PastedLabelServingSizeGrammarV3
        let whole = NSRange(value.startIndex..., in: value)
        var quantity: NSTextCheckingResult?
        if let bracket = G.parenthesised.firstMatch(in: value, range: whole) {
            quantity = G.quantity.firstMatch(in: value, range: bracket.range(at: 1))
        }
        quantity = quantity ?? G.quantity.firstMatch(in: value, range: whole)
        guard let match = quantity, let range = Range(match.range, in: value),
              let number = Range(match.range(at: 1), in: value), let matchedUnit = Range(match.range(at: 2), in: value),
              String(value[number]) == decimal, String(value[matchedUnit]) == unit else { return nil }
        let numberRange = match.range(at: 1)
        let base = String(value[..<range.upperBound])
        let after = String(value[range.upperBound...])
        if let tilde = tildePiecesPattern.firstMatch(in: after, range: NSRange(after.startIndex..., in: after)),
           let tail = Range(tilde.range, in: after), countsPieces(String(after[tail.upperBound...])) {
            return (base, numberRange, value)
        }
        return (base + segmentTail(after, unit: unit), numberRange, value)
    }

    /// A tilde or wave dash, then an opening bracket, a 約/about-type marker or both, before a count.
    static let tildePiecesPattern = try! NSRegularExpression(
        pattern: #"^\s*[~～〜]\s*(?:[(（]\s*(?:"# + markerWord + #"\s*)?|"# + markerWord + #"\s*)"#, options: [.caseInsensitive])
    static let markerWord = #"(?:(?:about|approx|approximate|approximately|around|ca|circa|roughly)(?![A-Za-z])\.?|[約约])"#

    /// v3's range: v2's, with a listed weight or volume unit allowed between the low number and
    /// the mark as well as up to three other characters ("25 grams - 30g" is a range).
    static let rangePatternV3 = try! NSRegularExpression(
        pattern: #"([0-9][0-9.]*)\s*(?:"# + weightOrVolumeUnits + #"|[^0-9\s]{0,3}?)\s*"# + rangeMarks + #"\s*([0-9][0-9.]*)"#,
        options: [.caseInsensitive])
    static let lowUnitPatternV3 = try! NSRegularExpression(
        pattern: #"\s*("# + weightOrVolumeUnits + #"|[^0-9\s]{0,3}?)\s*"# + rangeMarks + #"\s*[0-9]"#, options: [.caseInsensitive])
    static let bilingualPattern = try! NSRegularExpression(pattern: "[A-Za-z]{2,}")

    /// Steps 6 and 7: approximate when the segment holds anything v2 lists, or, for a bilingual
    /// value (a run of two or more ASCII letters), when anywhere in the value from step 3 holds
    /// one of v2's words or marks; a range whose other end has no unit is shown as the recorded
    /// quantity with the range note unless it is the "25-30g" pattern.
    static func exactnessV3(_ size: PastedLabelManifest.Candidate.ServingSize) -> Exactness {
        guard let (segment, number, value) = locatedV3(size) else { return .unmatched }
        let matches = rangePatternV3.matches(in: segment, range: NSRange(segment.startIndex..., in: segment))
        if !matches.isEmpty {
            let recorded = size.unit.flatMap(unitFamily)
            return .range(own: matches.lazy.compactMap { ownRangeV3($0, in: segment, number: number, recordedUnit: recorded) }.first)
        }
        if approximate(segment) { return .approximate }
        if bilingualPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil, approximateMarksOrWords(value) {
            return .approximate
        }
        return .exact
    }

    /// v2's words and marks only (no range), anywhere in a text.
    static func approximateMarksOrWords(_ text: String) -> Bool {
        if approximateMarks.contains(where: { text.contains($0) }) { return true }
        if circaAbbreviationPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
        let words = text.lowercased().split { !($0.isASCII && $0.isLetter) }.map(String.init)
        return words.contains { approximateWords.contains($0) }
    }

    /// v3's own range: as v2, except that when the recorded quantity is the low number the high
    /// number must carry a unit of the same family ("30g-35g"; not "30g - 2" or "30g~35"), and a
    /// listed unit word may stand after the low number ("25 grams - 30g").
    static func ownRangeV3(_ match: NSTextCheckingResult, in segment: String, number: NSRange, recordedUnit: String?) -> PrintedRange? {
        guard let recordedUnit, let low = Range(match.range(at: 1), in: segment),
              let high = Range(match.range(at: 2), in: segment) else { return nil }
        let range = PrintedRange(low: String(segment[low]), high: String(segment[high]))
        if match.range(at: 1).location == number.location {
            let afterHigh = segment[high.upperBound...].drop { $0.isWhitespace }.prefix { $0.isLetter }
            return !afterHigh.isEmpty && unitFamily(String(afterHigh)) == recordedUnit ? range : nil
        }
        guard match.range(at: 2).location == number.location else { return nil }
        let start = match.range(at: 1).location + match.range(at: 1).length
        let rest = NSRange(location: start, length: (segment as NSString).length - start)
        guard let between = lowUnitPatternV3.firstMatch(in: segment, options: [.anchored, .withTransparentBounds], range: rest),
              let unit = Range(between.range(at: 1), in: segment) else { return nil }
        let text = segment[unit]
        return text.isEmpty || unitFamily(String(text)) == recordedUnit ? range : nil
    }

    /// Whether a range is the serving size's own (what Confirm shows; any range refuses
    /// servings), so both numbers are in the recorded unit: its low number is the recorded
    /// quantity (the range tail after it, "30g-35g") and the high number has no unit or the same
    /// unit; or its high number is the recorded quantity and nothing but spaces and no unit or the
    /// same unit stands between the low number and the mark ("25-30g", "25 g - 30 g", "25g-30g",
    /// "25公克-30克"; not "1 bar - 30g", "1 oz - 28g", "1 kg-30g" or "1 l - 250ml"). Same unit
    /// means the same unit family: g, 公克, 克, gram(s), gramme(s); or ml, mL, 毫升, millilitre(s),
    /// milliliter(s).
    static func ownRange(_ match: NSTextCheckingResult, in segment: String, number: NSRange, recordedUnit: String?) -> PrintedRange? {
        guard let recordedUnit, let low = Range(match.range(at: 1), in: segment),
              let high = Range(match.range(at: 2), in: segment) else { return nil }
        func sameUnit(_ text: Substring) -> Bool { text.isEmpty || unitFamily(String(text)) == recordedUnit }
        let range = PrintedRange(low: String(segment[low]), high: String(segment[high]))
        if match.range(at: 1).location == number.location {
            let afterHigh = segment[high.upperBound...].drop { $0.isWhitespace }.prefix { $0.isLetter }
            return sameUnit(afterHigh) ? range : nil
        }
        guard match.range(at: 2).location == number.location else { return nil }
        let start = match.range(at: 1).location + match.range(at: 1).length
        let rest = NSRange(location: start, length: (segment as NSString).length - start)
        guard let between = lowUnitPattern.firstMatch(in: segment, options: [.anchored, .withTransparentBounds], range: rest),
              let unit = Range(between.range(at: 1), in: segment) else { return nil }
        return sameUnit(segment[unit]) ? range : nil
    }

    /// The unit family of a printed unit: "g" or "ml", else nil.
    static func unitFamily(_ unit: String) -> String? {
        switch unit.lowercased() {
        case "g", "公克", "克", "gram", "grams", "gramme", "grammes": "g"
        case "ml", "毫升", "millilitre", "millilitres", "milliliter", "milliliters": "ml"
        default: nil
        }
    }

    /// The characters between a range's low number and its mark (group 1).
    static let lowUnitPattern = try! NSRegularExpression(pattern: #"\s*([^0-9\s]{0,3}?)\s*"# + rangeMarks + #"\s*[0-9]"#,
                                                         options: [.caseInsensitive])

    /// Whether a serving-size segment is approximate: a listed mark, a listed whole English word,
    /// or a numeric range.
    public static func approximate(_ segment: String) -> Bool {
        if approximateMarks.contains(where: { segment.contains($0) }) { return true }
        let whole = NSRange(segment.startIndex..., in: segment)
        if rangePattern.firstMatch(in: segment, range: whole) != nil { return true }
        if circaAbbreviationPattern.firstMatch(in: segment, range: whole) != nil { return true }
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
