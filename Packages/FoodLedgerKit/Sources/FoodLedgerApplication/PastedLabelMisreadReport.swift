import Foundation
import FoodLedgerDomain

/// The words of a misread report. The presentation owns every word, through the one origin
/// formatter, so "about", "Calculated" and the source wording match Confirm; the builder owns
/// only what the report may contain and its order (section 8.1).
public protocol PastedLabelReportWording: Sendable {
    func heading(_ heading: PastedLabelMisreadReport.Heading) -> String
    func value(_ value: PastedLabelMisreadReport.Value) -> String
    func servingSize(_ printedText: String?) -> String
    func servingsPerPack(_ printedText: String?) -> String
    func decline(_ code: String) -> String
    func warning(_ code: String) -> String
    func versions(_ versions: PastedLabelMisreadReport.Versions) -> String
    /// The stored column's basis when the user chose it (reader v3 section 8.4.11), through the
    /// one basis formatter.
    func basis(_ basis: String, origin: PastedLabelBasisOrigin) -> String
}

/// Report a misread (`docs/pasted-nutrition-label-v1.md` section 9.1): a pure, deterministic
/// builder over an allow-list of contents. It takes no name, brand, other entry, health data,
/// note or identifier, so none can reach the report. It never sends anything: the presentation
/// shows the text in an editable preview and only the user's Share opens the system share sheet.
public struct PastedLabelMisreadReport: Equatable, Sendable {
    public enum Heading: String, CaseIterable, Sendable {
        case title, pastedText = "pasted_text", valuesRead = "values_read", serving
        case declined, warnings, versions
    }

    /// One value read, with its printed source text, basis and origin (printed or calculated).
    public struct Value: Equatable, Sendable {
        public let nutrient: String
        public let printedLabel: String
        public let printedText: String
        public let basis: String
        public let comparator: String
        public let decimalText: String
        public let unit: String
        public let origin: NutrientValueOrigin
        /// For a calculated value: the printed operand, its unit and the factor.
        public let conversion: PastedLabelManifest.Conversion?
    }

    public struct Versions: Equatable, Sendable {
        public let parser: String
        public let gate: String
        public let arithmetic: String
        public let conversion: String
    }

    /// The allow-listed contents. Built from a reading (Confirm, a decline) or a stored
    /// manifest (a saved entry); never from the ledger.
    public let pastedText: String
    public let values: [Value]
    public let servingSize: String?
    public let servingsPerPack: String?
    public let declineCodes: [String]
    public let warningCodes: [String]
    public let versions: Versions
    /// The stored column's basis and its origin, only when the user chose it (8.4.11); a printed
    /// basis already shows on every value line.
    public let chosenBasis: (basis: String, origin: PastedLabelBasisOrigin)?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pastedText == rhs.pastedText && lhs.values == rhs.values && lhs.servingSize == rhs.servingSize
            && lhs.servingsPerPack == rhs.servingsPerPack && lhs.declineCodes == rhs.declineCodes
            && lhs.warningCodes == rhs.warningCodes && lhs.versions == rhs.versions
            && lhs.chosenBasis?.basis == rhs.chosenBasis?.basis && lhs.chosenBasis?.origin == rhs.chosenBasis?.origin
    }

    /// A reading on Confirm or a decline. A decline before any reading (too long, no digest)
    /// still reports the text, the codes and the reader versions in force.
    public init(pastedText: String, reading: LabelReading?, declineCodes: [String], warningCodes: [String],
                basisOrigin: PastedLabelBasisOrigin = .printed) {
        let versions = reading.map { Versions(parser: $0.versions.parser, gate: $0.versions.gate,
                                              arithmetic: $0.versions.arithmetic, conversion: $0.versions.conversion) }
            ?? Versions(parser: PastedLabelSource.parserVersion, gate: PastedLabelSource.gateVersion,
                        arithmetic: PastedLabelSource.arithmeticVersion, conversion: PastedLabelSource.conversionVersion)
        let stored = reading.flatMap { reading in reading.candidate.headers.first { $0.headerID == reading.storedHeaderID } }
        self.init(pastedText: pastedText, candidate: reading?.candidate, conversions: reading?.conversions ?? [],
                  declineCodes: declineCodes, warningCodes: warningCodes, versions: versions,
                  chosenBasis: basisOrigin.isChosen ? stored.map { ($0.basis, basisOrigin) } : nil)
    }

    /// The report for a review on Confirm: its reading, warnings and basis origin.
    public init(review: PastedLabelReview) {
        self.init(pastedText: review.pastedText, reading: review.reading, declineCodes: [], warningCodes: review.warningCodes,
                  basisOrigin: review.basisOrigin)
    }

    /// A logged v1 entry's stored manifest.
    public init(manifest: PastedLabelManifest) { self.init(manifest: .v1(manifest)) }

    /// A logged entry's stored manifest.
    public init(manifest: PastedLabelEvidenceManifest) {
        self.init(pastedText: manifest.pastedText, candidate: manifest.candidate, conversions: manifest.conversions,
                  declineCodes: [], warningCodes: manifest.warningsShown,
                  versions: Versions(parser: manifest.parserVersion, gate: manifest.gateVersion,
                                     arithmetic: manifest.arithmeticVersion, conversion: manifest.conversionVersion),
                  chosenBasis: manifest.basisOrigin.isChosen
                    ? manifest.candidate.headers.first { $0.headerID == manifest.storedHeaderID }.map { ($0.basis, manifest.basisOrigin) } : nil)
    }

    private init(pastedText: String, candidate: PastedLabelManifest.Candidate?, conversions: [PastedLabelManifest.Conversion],
                 declineCodes: [String], warningCodes: [String], versions: Versions,
                 chosenBasis: (basis: String, origin: PastedLabelBasisOrigin)?) {
        self.chosenBasis = chosenBasis
        self.pastedText = pastedText
        self.declineCodes = declineCodes
        self.warningCodes = warningCodes
        self.versions = versions
        servingSize = candidate?.servingSize?.printedText
        servingsPerPack = candidate?.servingsPerPack?.printedText
        let headers = Dictionary((candidate?.headers ?? []).map { ($0.headerID, $0.basis) }, uniquingKeysWith: { first, _ in first })
        var values: [Value] = (candidate?.cells ?? []).map { cell in
            Value(nutrient: cell.nutrient, printedLabel: cell.printedLabel, printedText: cell.printedText,
                  basis: headers[cell.headerID] ?? cell.basis, comparator: cell.comparator, decimalText: cell.decimalText,
                  unit: cell.unit, origin: .printed, conversion: nil)
        }
        for conversion in conversions {
            let source = candidate?.cells.first { $0.rowID == conversion.sourceRowID && $0.headerID == conversion.sourceHeaderID }
            values.append(Value(nutrient: conversion.nutrient, printedLabel: source?.printedLabel ?? conversion.sourceRowID,
                                printedText: source?.printedText ?? conversion.operandText,
                                basis: headers[conversion.sourceHeaderID] ?? "", comparator: conversion.comparator ?? "=",
                                decimalText: conversion.storedText, unit: PastedLabelSource.ledgerKeys[conversion.nutrient]?.canonicalUnit.rawValue ?? "",
                                origin: .calculated(rule: conversion.rule), conversion: conversion))
        }
        self.values = values
    }

    /// The report text, in a fixed order. Deterministic: the same contents and wording give the
    /// same text.
    public func text(wording: any PastedLabelReportWording) -> String {
        var lines = [wording.heading(.title), "", wording.heading(.pastedText), pastedText, ""]
        if !declineCodes.isEmpty {
            lines += [wording.heading(.declined)] + declineCodes.map(wording.decline) + [""]
        }
        if !values.isEmpty {
            let basis = chosenBasis.map { [wording.basis($0.basis, origin: $0.origin)] } ?? []
            lines += [wording.heading(.valuesRead)] + basis + values.map(wording.value) + [""]
            lines += [wording.heading(.serving), wording.servingSize(servingSize), wording.servingsPerPack(servingsPerPack), ""]
        }
        if !warningCodes.isEmpty {
            lines += [wording.heading(.warnings)] + warningCodes.map(wording.warning) + [""]
        }
        lines += [wording.heading(.versions), wording.versions(versions)]
        return lines.joined(separator: "\n")
    }
}
