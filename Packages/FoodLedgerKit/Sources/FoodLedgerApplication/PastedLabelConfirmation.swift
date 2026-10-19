import Foundation
import FoodLedgerDomain

public enum PastedLabelConfirmationError: Error, Equatable, Sendable {
    /// Name is required (section 2.2).
    case nameMissing
    /// The nutrient has no ledger key, or a printed cell the ledger cannot use as it stands.
    case notCorrectable(String)
    /// The value is not plain decimal text in the nutrient's ledger unit with `=`, `<` or `<=`.
    case invalidValue(String)
}

/// The identity fields the user enters on the label text screen (section 2.2).
public struct PastedLabelDetails: Equatable, Sendable {
    public let name: String
    public let brand: String?
    public let fortification: PastedLabelIdentity.FortificationAnswer
    public init(name: String, brand: String? = nil, fortification: PastedLabelIdentity.FortificationAnswer = .unanswered) {
        self.name = name; self.brand = brand; self.fortification = fortification
    }
}

/// The confirmation builder (sections 2.3, 3.2, 6.1 and 6.5). It maps a usable reading and the
/// user's inputs to a `pasted-nutrition-label-v1` manifest, then to the shared Confirm input
/// through `PastedLabelSource.confirmation`, so the values written are exactly the values save
/// and reopen verify. It never saves: the only save is the user's Log on Confirm.
///
/// - G3 to G6 are flags recorded in `flags_shown`; they never block Log.
/// - Unknown values stay unknown; corrections and entries are explicit user records stamped
///   by the injected clock.
public struct PastedLabelConfirmation: Sendable {
    private let ids: any LedgerIDGenerating
    private let clock: any LedgerClock
    private let encoder: any CanonicalEncoding
    private let digester: any Digesting
    private let conversions: (any PastedLabelConversionChecking)?

    public init(ids: any LedgerIDGenerating, clock: any LedgerClock, encoder: any CanonicalEncoding,
                digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) {
        self.ids = ids; self.clock = clock; self.encoder = encoder; self.digester = digester; self.conversions = conversions
    }

    // MARK: Corrections and entries

    /// The record for a value the user corrected or entered on Confirm, stamped now. A value
    /// that replaces a recognised cell (printed, or the printed source of a calculated value) is
    /// `corrected` and keeps that cell; a row that was not read is `entered`. `nutrient` is a
    /// reader key (`protein`, `sodium`) or `serving_size`.
    public func correction(_ nutrient: String, value: PastedLabelManifest.Correction.Value,
                           in review: PastedLabelReview) throws -> PastedLabelManifest.Correction {
        let candidate = review.reading.candidate
        let stored = review.storedHeaderID
        if nutrient == PastedLabelManifest.Correction.servingsPerPack {
            // Fillable only when the label prints no servings-per-pack line (G6); never a correction.
            guard candidate.servingsPerPack == nil else { throw PastedLabelConfirmationError.notCorrectable(nutrient) }
            guard value.comparator == "=", value.unit == "count", let count = PastedLabelSource.amount(value.decimalText), count > 0 else {
                throw PastedLabelConfirmationError.invalidValue(nutrient)
            }
            return .init(kind: .entered, nutrient: nutrient, rowID: nil, headerID: stored, recognised: nil, corrected: value, at: clock.now())
        }
        if nutrient == PastedLabelManifest.Correction.servingSize {
            guard value.comparator == "=", ["g", "ml"].contains(value.unit),
                  PastedLabelSource.quantity(value.decimalText, unit: value.unit) != nil else {
                throw PastedLabelConfirmationError.invalidValue(nutrient)
            }
            guard candidate.headers.first(where: { $0.headerID == stored })?.basis == "per_serving" else {
                throw PastedLabelConfirmationError.notCorrectable(nutrient)
            }
            if PastedLabelSource.servingQuantity(candidate.servingSize) != nil, let printed = candidate.servingSize,
               let decimal = printed.decimalText, let unit = printed.unit {
                return .init(kind: .corrected, nutrient: nutrient, rowID: nil, headerID: stored,
                             recognised: .init(printedText: printed.printedText, decimalText: decimal, unit: unit, comparator: "="),
                             corrected: value, at: clock.now())
            }
            return .init(kind: .entered, nutrient: nutrient, rowID: nil, headerID: stored, recognised: nil, corrected: value, at: clock.now())
        }
        guard let key = PastedLabelSource.ledgerKeys[nutrient] else { throw PastedLabelConfirmationError.notCorrectable(nutrient) }
        guard value.unit == key.canonicalUnit.rawValue, ["=", "<", "<="].contains(value.comparator),
              PastedLabelSource.amount(value.decimalText) != nil else {
            throw PastedLabelConfirmationError.invalidValue(nutrient)
        }
        let column = candidate.cells.filter { $0.headerID == stored && $0.basis != "reference_intake" && $0.canonicalUnit != "%" }
        let printed = column.filter { $0.nutrient == nutrient }
        let cell: PastedLabelManifest.Candidate.Cell?
        if !printed.isEmpty {
            // Ambiguous or in another unit: the ledger stores it as unknown, and the value is not
            // a recognised cell the user can correct.
            guard printed.count == 1, printed[0].canonicalUnit == key.canonicalUnit.rawValue else {
                throw PastedLabelConfirmationError.notCorrectable(nutrient)
            }
            cell = printed[0]
        } else if let conversion = review.reading.conversions.first(where: { $0.nutrient == nutrient }) {
            cell = column.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
            guard cell != nil else { throw PastedLabelConfirmationError.notCorrectable(nutrient) }
        } else {
            cell = nil
        }
        guard let cell else {
            return .init(kind: .entered, nutrient: nutrient, rowID: nil, headerID: stored, recognised: nil, corrected: value, at: clock.now())
        }
        return .init(kind: .corrected, nutrient: nutrient, rowID: cell.rowID, headerID: stored,
                     recognised: .init(printedText: cell.printedText, decimalText: cell.decimalText, unit: cell.unit, comparator: cell.comparator),
                     corrected: value, at: clock.now())
    }

    // MARK: Manifest and Confirm input

    /// The flags still shown at Log: the review's flags less any row, cell or serving line the
    /// user has since entered or corrected.
    public static func flagsShown(_ review: PastedLabelReview, corrections: [PastedLabelManifest.Correction]) -> [PastedLabelManifest.Flag] {
        let resolved = Set(corrections.map(\.nutrient))
        return review.flags.filter { flag in
            if let nutrient = flag.nutrient {
                return !(resolved.contains(nutrient) && (flag.headerID == nil || flag.headerID == review.storedHeaderID))
            }
            return !(flag.code == PastedLabelCodes.requiredServingDeclarationMissing && resolved.contains(flag.concerns)
                     && [PastedLabelManifest.Correction.servingSize, PastedLabelManifest.Correction.servingsPerPack].contains(flag.concerns))
        }.map { PastedLabelManifest.Flag(code: $0.code, concerns: $0.concerns) }
    }

    /// The manifest the user is logging, built from the reading as shown, never re-read.
    public func manifest(_ review: PastedLabelReview, details: PastedLabelDetails,
                         corrections: [PastedLabelManifest.Correction]) throws -> PastedLabelManifest {
        let name = details.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PastedLabelConfirmationError.nameMissing }
        let brand = details.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = review.reading
        func build(_ identity: PastedLabelManifest.IdentityMapping) -> PastedLabelManifest {
            PastedLabelManifest(pastedText: review.pastedText, pastedTextSHA256: reading.textSHA256,
                parserVersion: reading.versions.parser, gateVersion: reading.versions.gate,
                arithmeticVersion: reading.versions.arithmetic, conversionVersion: reading.versions.conversion,
                labelFormat: reading.format, launchScope: PastedLabelLaunchScope.enabledFormats, identityMapping: identity,
                candidate: reading.candidate, storedHeaderID: review.storedHeaderID, conversions: reading.conversions,
                flagsShown: Self.flagsShown(review, corrections: corrections), corrections: corrections,
                warningsShown: review.warningCodes, name: name, brand: brand)
        }
        // The identity's serving basis is the stored column's basis, which a serving-size entry
        // can settle (section 6.3); the basis rule reads only headers and corrections.
        let provisional = build(try .init(fortificationAnswer: details.fortification, servingBasis: .per100Grams))
        let basis = try PastedLabelSource.storedBasis(provisional)
        return build(try .init(fortificationAnswer: details.fortification, servingBasis: basis))
    }

    /// The shared Confirm input for the manifest, with fresh evidence captured now.
    public func confirmation(_ review: PastedLabelReview, details: PastedLabelDetails,
                             corrections: [PastedLabelManifest.Correction], locale: LedgerText) throws -> PopulatedFoodConfirmation {
        let manifest = try manifest(review, details: details, corrections: corrections)
        return try PastedLabelSource.confirmation(manifest: manifest, evidenceID: ids.makeID(EvidenceTag.self),
            capturedAt: clock.now(), locale: locale, encoder: encoder, digester: digester, conversions: conversions)
    }
}
