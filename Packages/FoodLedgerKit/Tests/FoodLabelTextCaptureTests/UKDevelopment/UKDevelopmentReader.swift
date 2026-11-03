import FoodLabelTextCapture
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation
import NutritionLabelParsing

/// **Development only** (`docs/pasted-nutrition-label-uk-english-v1.md` P1, decision 8). A copy
/// of `PastedLabelReader.read` and `classify` with the launch scope passed in, so the UK
/// development set can be read without changing the product's scope. It is never used for a
/// release check, and no product file depends on it. `UKDevelopmentReaderTests` proves that,
/// with the product's own scope, it decides every fixture exactly as `PastedLabelReader` does.
struct UKDevelopmentReader {
    static let ukScope = PastedLabelLaunchScope.enabledFormats + [LabelFormatInference.Outcome.uk.rawValue]

    let scope: [String]
    private let reader: any LabelTextReading
    private let isAsSold: @Sendable (PastedLabelManifest.Candidate) -> Bool
    private let digester: any Digesting = SHA256Digester()

    /// The P2a default: the UK scope, the UK adapter and identity v2. With the product's scope,
    /// `NutritionLabelTextReader` and `PastedLabelBasisState.isAsSold` it is the product's reader.
    init(scope: [String] = Self.ukScope, reader: any LabelTextReading = UKEnglishLabelTextReader(),
         isAsSold: @escaping @Sendable (PastedLabelManifest.Candidate) -> Bool = PastedLabelBasisStateV2.isAsSold) {
        self.scope = scope
        self.reader = reader
        self.isAsSold = isAsSold
    }

    /// The product's reader, through this copy (the parity configuration).
    static let product = UKDevelopmentReader(scope: PastedLabelLaunchScope.enabledFormats, reader: NutritionLabelTextReader(),
                                             isAsSold: PastedLabelBasisState.isAsSold)

    /// `PastedLabelReader.read`, unchanged apart from calling this type's `classify`.
    func read(_ text: String) -> PastedLabelReadOutcome {
        guard text.unicodeScalars.count <= PastedLabelManifest.maximumTextScalars else {
            return .declined(codes: [PastedLabelCodes.textTooLong], reading: nil)
        }
        guard let hash = try? digester.sha256(Data(text.utf8)) else {
            return .declined(codes: [PastedLabelCodes.unreadableTable], reading: nil)
        }
        let reading = reader.read(text, textSHA256: hash.value, assertedBases: nil)
        let outcome = classify(reading, pastedText: text)
        guard outcome.declineCodes == [PastedLabelCodes.noBasisHeader], let unheaded = reading.unheadedTable else { return outcome }
        guard let arrangements = PastedLabelBasisOptions.options(for: unheaded) else {
            return .declined(codes: [unheaded.servingSize == nil ? PastedLabelCodes.unheadedColumnsWithoutServingSize
                                     : PastedLabelCodes.unheadedColumnsServingSizeNotInGramsOrMillilitres], reading: reading)
        }
        var options: [PastedLabelBasisChoiceRequest.Option] = []
        for arrangement in arrangements {
            let asserted = reader.read(text, textSHA256: hash.value, assertedBases: arrangement.assertedBases)
            switch classify(asserted, pastedText: text) {
            case let .usable(review):
                options.append(.init(arrangement: arrangement, review: review))
            case let .declined(codes, declinedReading):
                return .declined(codes: codes, reading: declinedReading)
            case .needsBasisChoice:
                return .declined(codes: [PastedLabelCodes.assertedBasesMismatch], reading: asserted)
            }
        }
        return .needsBasisChoice(PastedLabelBasisChoiceRequest(pastedText: text, declinedReading: reading, unheaded: unheaded,
                                                               options: options))
    }

    /// `PastedLabelReader.classify` with `scope` in place of `PastedLabelLaunchScope.admits` and
    /// `isAsSold` in place of `PastedLabelBasisState.isAsSold`.
    func classify(_ reading: LabelReading, pastedText: String) -> PastedLabelReadOutcome {
        let candidate = reading.candidate
        if candidate.declined {
            let codes = candidate.declineReasons.isEmpty ? [PastedLabelCodes.unreadableTable] : candidate.declineReasons
            return .declined(codes: codes, reading: reading)
        }
        var codes: [String] = []
        if let gate = reading.gate {
            if gate.skipped != nil, gate.hardDeclines.isEmpty { codes.append(PastedLabelCodes.unreadableTable) }
            codes.append(contentsOf: gate.hardDeclines)
        }
        if reading.format == PastedLabelCodes.formatAmbiguous {
            codes.append(PastedLabelCodes.formatAmbiguous)
        } else if !scope.contains(reading.format) {
            codes.append(PastedLabelCodes.layoutNotSupported)
        } else if reading.gate == nil {
            codes.append(PastedLabelCodes.unreadableTable)
        }
        if !isAsSold(candidate) {
            codes.append(PastedLabelIdentity.basisStateNotSupported)
        }
        guard let stored = reading.storedHeaderID, candidate.headers.contains(where: { $0.headerID == stored }) else {
            codes.append(PastedLabelCodes.noTable)
            return .declined(codes: Self.unique(codes), reading: reading)
        }
        guard codes.isEmpty, let gate = reading.gate else { return .declined(codes: Self.unique(codes), reading: reading) }
        let calculated = Set(reading.conversions.map(\.nutrient))
        let flags = gate.flags.filter { flag in
            guard let nutrient = flag.nutrient, calculated.contains(nutrient) else { return true }
            return !(flag.code == PastedLabelCodes.requiredRowMissing || flag.headerID == stored)
        }
        return .usable(PastedLabelReview(pastedText: pastedText, reading: reading, storedHeaderID: stored,
                                         flags: flags, warningCodes: reading.warningCodes))
    }

    private static func unique(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        return codes.filter { seen.insert($0).inserted }
    }
}
