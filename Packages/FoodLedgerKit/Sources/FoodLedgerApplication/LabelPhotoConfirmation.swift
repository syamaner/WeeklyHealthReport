import Foundation
import FoodLedgerDomain

public enum LabelPhotoConfirmationError: Error, Equatable, Sendable {
    /// The reading declines (its codes), or has no stored column.
    case notUsable([String])
    /// The reading, the reply and the prepared image do not belong together.
    case mismatch(String)
    /// Name is required (section 2.2).
    case nameMissing
    /// Not an attention item of this review.
    case notAnItem(String)
    /// The value cannot be corrected here: another column than the stored one, a repeated or
    /// differently-unit row, or a printed servings-per-pack line (the pasted rules).
    case notCorrectable(String)
    /// The value is not plain decimal text in the nutrient's ledger unit with `=`, `<` or `<=`.
    case invalidValue(String)
    /// Log is disabled until every attention item is resolved (P12).
    case unresolved([String])
    /// The built entry did not verify against its own manifest (fails closed).
    case notVerified
}

/// What Confirm shows for one label photo read, and the user's resolutions so far
/// (docs/label-photo-ai-prefill-v1.md P12, 7.3, 8.1, 17.5 and 17.16). A value: every action
/// returns a new review. Nothing here saves.
public struct LabelPhotoReview: Equatable, Sendable {
    public let reading: LabelPhotoReading
    public let image: LabelPhotoManifest.Image
    public let request: LabelPhotoManifest.Request
    public let response: LabelPhotoManifest.Response
    public let locations: LabelPhotoManifest.Locations
    public let storedHeaderID: String
    /// The gate's G3 to G6 flags, all of them, as shown with the reading.
    public let flags: [PastedLabelManifest.Flag]
    /// The failed `label-arithmetic-checks-v2` results (the per serving against per 100 check is
    /// its `serving_scaling`, called not copied).
    public let checksFailed: [LabelPhotoManifest.FailedCheck]
    /// The attention items and check groups, from the same rule the verifier recomputes.
    public let findings: LabelPhotoAttention.Findings
    /// Each resolved item's record, keyed by item.
    public internal(set) var resolutions: [String: LabelPhotoManifest.Attention]
    /// The user's corrections and entries, in the order made.
    public internal(set) var corrections: [PastedLabelManifest.Correction]

    init(reading: LabelPhotoReading, image: LabelPhotoManifest.Image, request: LabelPhotoManifest.Request,
         response: LabelPhotoManifest.Response, locations: LabelPhotoManifest.Locations, storedHeaderID: String,
         flags: [PastedLabelManifest.Flag], checksFailed: [LabelPhotoManifest.FailedCheck], findings: LabelPhotoAttention.Findings) {
        self.reading = reading; self.image = image; self.request = request; self.response = response; self.locations = locations
        self.storedHeaderID = storedHeaderID; self.flags = flags; self.checksFailed = checksFailed; self.findings = findings
        resolutions = [:]; corrections = []
    }

    /// The items still needing the user, in order. Log is enabled only when this is empty.
    public var unresolved: [String] { LabelPhotoAttention.unresolved(findings, resolutions: resolutions.mapValues(\.resolution)) }
    public var canLog: Bool { unresolved.isEmpty }

    /// The item a cell or serving line is, and the cell behind a cell item.
    func cell(_ item: String) -> PastedLabelManifest.Candidate.Cell? {
        reading.candidate.cells.first { LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID) == item }
    }

    /// Nutrient and column pairs the user left unknown: every cell of that nutrient in that column
    /// leaves the stored values, as in the verifier's projection.
    var leftUnknownColumns: Set<String> {
        Set(resolutions.values.filter { $0.resolution == .leftUnknown }.compactMap { cell($0.item).map { $0.nutrient + "@" + $0.headerID } })
    }

    func isLeftUnknown(_ conversion: PastedLabelManifest.Conversion) -> Bool {
        let unknown = leftUnknownColumns
        let source = reading.candidate.cells.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
        return source.map { unknown.contains($0.nutrient + "@" + $0.headerID) } == true
            || unknown.contains(conversion.nutrient + "@" + conversion.sourceHeaderID)
    }

    /// The shown-conversions rule (17.16): a conversion whose source (or target) the user left
    /// unknown is no longer shown or stored.
    public var conversionsShown: [PastedLabelManifest.Conversion] { reading.conversions.filter { !isLeftUnknown($0) } }
    /// The conversions that now read "Left unknown".
    public var conversionsLeftUnknown: [PastedLabelManifest.Conversion] { reading.conversions.filter(isLeftUnknown) }
}

/// The label photo Confirm builder (docs/label-photo-ai-prefill-v1.md P12, 7.3, 8.1, 17.3 and
/// 17.16). It turns a read (the reading of the reply's wire text, the prepared image, the request
/// record and the locator's records) into a review, applies the user's resolutions, and builds the
/// manifest and the shared Confirm input, which it verifies with the same verifier save and reopen
/// use before handing it on. It never saves: the only save is the user's Log.
public struct LabelPhotoConfirmation: Sendable {
    private let clock: any LedgerClock
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting
    private let conversions: (any PastedLabelConversionChecking)?

    public init(clock: any LedgerClock, encoder: any CanonicalEncoding, digester: any Digesting,
                conversions: (any PastedLabelConversionChecking)?) {
        self.clock = clock; self.encoder = encoder; self.digester = digester; self.conversions = conversions
    }

    private var now: Int64 { PastedLabelBasisChoice.milliseconds(clock.now()) }

    // MARK: Review

    public func review(reading: LabelPhotoReading, image: PreparedLabelImage, reply: LabelPhotoWireReply,
                       request: LabelPhotoManifest.Request, locations: LabelPhotoManifest.Locations) throws -> LabelPhotoReview {
        guard reading.isUsable, let stored = reading.storedHeaderID else {
            throw LabelPhotoConfirmationError.notUsable(reading.hardDeclines)
        }
        guard reading.imageSHA256 == image.sha256, reading.candidate.inputSHA256 == image.sha256 else {
            throw LabelPhotoConfirmationError.mismatch("image")
        }
        guard reply.wireText.utf8.count <= LabelPhotoManifest.maximumWireBytes else { throw LabelPhotoConfirmationError.mismatch("wire") }
        let response = LabelPhotoManifest.Response(model: reply.model, provider: reply.provider, generationID: reply.generationID,
            finishReason: reply.finishReason, attempts: reply.attempts, usage: reply.usage, requestedAt: reply.requestedAt,
            completedAt: reply.completedAt, wireText: reply.wireText, wireSHA256: try digester.sha256(Data(reply.wireText.utf8)).value)
        let flags = (reading.gate?.flags ?? []).map { PastedLabelManifest.Flag(code: $0.code, concerns: $0.concerns) }
        let failed = reading.checks.filter { $0.status == .fail }
            .map { LabelPhotoManifest.FailedCheck(name: $0.name, basis: $0.basis, nutrient: $0.nutrient, child: $0.child) }
        var review = LabelPhotoReview(reading: reading, image: image.manifestImage, request: request, response: response, locations: locations,
                                      storedHeaderID: stored, flags: flags, checksFailed: failed,
                                      findings: LabelPhotoAttention.Findings(items: [], checks: []))
        // The attention set comes from the same function the verifier recomputes, which also
        // requires exactly one location record per cell and printed serving line.
        let provisional = try manifest(review, details: PastedLabelDetails(name: "provisional"), attention: [])
        let findings = try LabelPhotoSource.attention(provisional)
        review = LabelPhotoReview(reading: reading, image: review.image, request: request, response: response, locations: locations,
                                  storedHeaderID: stored, flags: flags, checksFailed: failed, findings: findings)
        return review
    }

    // MARK: Resolutions

    /// "Matches the photo" on one item.
    public func check(_ item: String, in review: LabelPhotoReview) throws -> LabelPhotoReview {
        try resolve(item, .checked, correction: nil, in: review)
    }

    /// "I've checked them" on a failed check: every implicated item without a resolution becomes checked.
    public func checkGroup(_ group: LabelPhotoAttention.CheckGroup, in review: LabelPhotoReview) throws -> LabelPhotoReview {
        guard review.findings.checks.contains(group) else { throw LabelPhotoConfirmationError.notAnItem(group.check.name) }
        var updated = review
        for id in group.itemIDs where updated.resolutions[id] == nil { updated = try resolve(id, .checked, correction: nil, in: updated) }
        return updated
    }

    /// "Leave unknown": the value, and every value of its nutrient in its column, is stored unknown,
    /// and any conversion from it reads "Left unknown".
    public func leaveUnknown(_ item: String, in review: LabelPhotoReview) throws -> LabelPhotoReview {
        try resolve(item, .leftUnknown, correction: nil, in: review)
    }

    /// "Correct": the user's value for a cell of the stored column or the serving size line. An
    /// attention item becomes `corrected` (or `entered` for a serving size whose printed text gave
    /// no amount); a value that was not an item is still recorded as the user's correction.
    public func correct(_ item: String, value: PastedLabelManifest.Correction.Value, in review: LabelPhotoReview) throws -> LabelPhotoReview {
        let correction = try correction(item, value: value, in: review)
        guard review.findings.items.contains(where: { $0.id == item }) else {
            var updated = review
            updated.replaceCorrection(for: item, with: correction)
            return updated
        }
        return try resolve(item, correction.kind == .entered ? .entered : .corrected, correction: correction, in: review)
    }

    /// Fills a serving line the label does not print (the pasted rule: servings per pack only when
    /// absent). Not an attention item; it clears the matching G6 flag's purpose but not the flag.
    public func enter(_ line: String, value: PastedLabelManifest.Correction.Value, in review: LabelPhotoReview) throws -> LabelPhotoReview {
        let candidate = review.reading.candidate
        let printed = line == PastedLabelManifest.Correction.servingSize ? candidate.servingSize != nil : candidate.servingsPerPack != nil
        guard [PastedLabelManifest.Correction.servingSize, PastedLabelManifest.Correction.servingsPerPack].contains(line), !printed else {
            throw LabelPhotoConfirmationError.notCorrectable(line)
        }
        var updated = review
        updated.replaceCorrection(for: line, with: try correction(line, value: value, in: review))
        return updated
    }

    private func resolve(_ item: String, _ resolution: LabelPhotoAttention.Resolution, correction: PastedLabelManifest.Correction?,
                         in review: LabelPhotoReview) throws -> LabelPhotoReview {
        guard let found = review.findings.items.first(where: { $0.id == item }) else { throw LabelPhotoConfirmationError.notAnItem(item) }
        var updated = review
        updated.replaceCorrection(for: item, with: correction)
        updated.resolutions[item] = LabelPhotoManifest.Attention(item: item, reasons: found.reasons, resolution: resolution, at: now)
        return updated
    }

    /// The record for a user value, stamped now, under the pasted rules: only the stored column,
    /// a nutrient printed once there in its ledger unit, or the serving lines.
    func correction(_ item: String, value: PastedLabelManifest.Correction.Value,
                    in review: LabelPhotoReview) throws -> PastedLabelManifest.Correction {
        let candidate = review.reading.candidate
        let stored = review.storedHeaderID
        let at = clock.now()
        if item == PastedLabelManifest.Correction.servingsPerPack {
            guard candidate.servingsPerPack == nil else { throw LabelPhotoConfirmationError.notCorrectable(item) }
            guard value.comparator == "=", value.unit == "count", let count = PastedLabelSource.amount(value.decimalText), count > 0 else {
                throw LabelPhotoConfirmationError.invalidValue(item)
            }
            return .init(kind: .entered, nutrient: item, rowID: nil, headerID: stored, recognised: nil, corrected: value, at: at)
        }
        if item == PastedLabelManifest.Correction.servingSize {
            guard value.comparator == "=", ["g", "ml"].contains(value.unit), PastedLabelSource.quantity(value.decimalText, unit: value.unit) != nil else {
                throw LabelPhotoConfirmationError.invalidValue(item)
            }
            if PastedLabelSource.servingQuantity(candidate.servingSize) != nil, let printed = candidate.servingSize,
               let decimal = printed.decimalText, let unit = printed.unit {
                return .init(kind: .corrected, nutrient: item, rowID: nil, headerID: stored,
                             recognised: .init(printedText: printed.printedText, decimalText: decimal, unit: unit, comparator: "="),
                             corrected: value, at: at)
            }
            return .init(kind: .entered, nutrient: item, rowID: nil, headerID: stored, recognised: nil, corrected: value, at: at)
        }
        guard let cell = review.cell(item) else { throw LabelPhotoConfirmationError.notAnItem(item) }
        guard cell.headerID == stored, cell.basis != "reference_intake", cell.canonicalUnit != "%",
              let key = PastedLabelSource.ledgerKeys[cell.nutrient], cell.canonicalUnit == key.canonicalUnit.rawValue,
              candidate.cells.filter({ $0.headerID == stored && $0.nutrient == cell.nutrient }).count == 1 else {
            throw LabelPhotoConfirmationError.notCorrectable(item)
        }
        guard value.unit == key.canonicalUnit.rawValue, ["=", "<", "<="].contains(value.comparator),
              PastedLabelSource.amount(value.decimalText) != nil else {
            throw LabelPhotoConfirmationError.invalidValue(item)
        }
        return .init(kind: .corrected, nutrient: cell.nutrient, rowID: cell.rowID, headerID: stored,
                     recognised: .init(printedText: cell.printedText, decimalText: cell.decimalText, unit: cell.unit, comparator: cell.comparator),
                     corrected: value, at: at)
    }

    // MARK: Manifest and Confirm input

    /// The manifest as logged: the reading as shown, never re-read; only the conversions still shown.
    public func manifest(_ review: LabelPhotoReview, details: PastedLabelDetails, capturedAt: Date? = nil) throws -> LabelPhotoManifest {
        let unresolved = review.unresolved
        guard unresolved.isEmpty else { throw LabelPhotoConfirmationError.unresolved(unresolved) }
        // Each record is stamped between the answer and the capture (8.2.5), even if the clock moved.
        let captured = capturedAt.map(PastedLabelBasisChoice.milliseconds)
        let records = review.findings.items.compactMap { item -> LabelPhotoManifest.Attention? in
            guard let record = review.resolutions[item.id] else { return nil }
            let at = max(review.response.completedAt, captured.map { min(record.at, $0) } ?? record.at)
            return LabelPhotoManifest.Attention(item: record.item, reasons: record.reasons, resolution: record.resolution, at: at)
        }
        return try manifest(review, details: details, attention: records)
    }

    private func manifest(_ review: LabelPhotoReview, details: PastedLabelDetails,
                          attention: [LabelPhotoManifest.Attention]) throws -> LabelPhotoManifest {
        let name = details.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LabelPhotoConfirmationError.nameMissing }
        let brand = details.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = review.reading
        func build(_ identity: PastedLabelManifest.IdentityMapping) -> LabelPhotoManifest {
            LabelPhotoManifest(image: review.image, request: review.request, response: review.response, mappingVersion: reading.versions.mapping,
                gateVersion: reading.versions.gate, arithmeticVersion: reading.versions.arithmetic, conversionVersion: reading.versions.conversion,
                identityMapping: identity, candidate: reading.candidate, locations: review.locations, storedHeaderID: review.storedHeaderID,
                conversions: review.conversionsShown, flagsShown: review.flags, checksFailed: review.checksFailed,
                warningsShown: review.checksFailed.map(\.warningCode), corrections: review.corrections, attention: attention,
                name: name, brand: brand)
        }
        // The identity's serving basis is the stored column's, through the shared basis rule.
        let provisional = build(try .init(fortificationAnswer: details.fortification, servingBasis: .per100Grams))
        let basis = try PastedLabelSource.storedBasis(LabelPhotoSource.projection(provisional))
        return build(try .init(fortificationAnswer: details.fortification, servingBasis: basis))
    }

    /// Confirm's display input while items are still unresolved: each unresolved item is shown as
    /// left unknown, so no value the user has not checked is counted, and it is never zero. It is
    /// for display only. Log stays disabled until `review.canLog` (the source model's blocker), and
    /// the Log path builds its input with `confirmation`, which refuses an unresolved review.
    public func preview(_ review: LabelPhotoReview, details: PastedLabelDetails, imageEvidenceID: EvidenceID,
                        manifestEvidenceID: EvidenceID, locale: LedgerText) throws -> PopulatedFoodConfirmation {
        var shown = review
        for item in review.unresolved { shown = try leaveUnknown(item, in: shown) }
        return try confirmation(shown, details: details, imageEvidenceID: imageEvidenceID, manifestEvidenceID: manifestEvidenceID,
                                attachment: nil, locale: locale)
    }

    /// The shared Confirm input for Log, verified with the save verifier before it is returned.
    /// The image evidence carries `attachment` once the bytes are persisted (17.3).
    public func confirmation(_ review: LabelPhotoReview, details: PastedLabelDetails, imageEvidenceID: EvidenceID,
                             manifestEvidenceID: EvidenceID, attachment: AttachmentDescriptor?,
                             locale: LedgerText) throws -> PopulatedFoodConfirmation {
        // The capture is never earlier than the answer.
        let now = max(clock.now(), Date(timeIntervalSince1970: TimeInterval(review.response.completedAt) / 1_000))
        let manifest = try manifest(review, details: details, capturedAt: now)
        let input = try LabelPhotoSource.confirmation(manifest: manifest, imageEvidenceID: imageEvidenceID,
            manifestEvidenceID: manifestEvidenceID, attachment: attachment, capturedAt: now, locale: locale, encoder: encoder,
            digester: digester, conversions: conversions)
        guard let candidate = input.candidates.first,
              LabelPhotoSource.verify(input, candidate: candidate, encoder: encoder, digester: digester, conversions: conversions) else {
            throw LabelPhotoConfirmationError.notVerified
        }
        return input
    }
}

extension LabelPhotoReview {
    /// One correction per item: a new one replaces the old, and nil removes it.
    mutating func replaceCorrection(for item: String, with correction: PastedLabelManifest.Correction?) {
        let cell = cell(item)
        corrections.removeAll { existing in
            if let cell { return existing.rowID == cell.rowID && existing.headerID == cell.headerID }
            return existing.rowID == nil && existing.nutrient == item
        }
        if let correction { corrections.append(correction) }
    }
}
