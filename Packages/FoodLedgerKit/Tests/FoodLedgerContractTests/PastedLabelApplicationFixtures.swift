import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport

/// Application-side fixtures for pasted label PR 3: a hand-built `LabelReading` around the PR 2
/// synthetic candidate (`PastedLabelFixtures`), and a stub `LabelTextReading` that records calls.
/// Nothing here imports the parser or the adapter: the contract tests reach the reader only
/// through the application port.
enum PastedReadingFixtures {
    private typealias F = PastedLabelFixtures

    static let versions = LabelReading.Versions(parser: PastedLabelSource.parserVersion, gate: PastedLabelSource.gateVersion,
        arithmetic: PastedLabelSource.arithmeticVersion, conversion: PastedLabelSource.conversionVersion,
        formatInference: "pasted-label-format-inference-v1")

    static let energyCheck = LabelReading.Check(name: "energy", basis: "per_100g", nutrient: nil, child: nil, status: .pass)

    /// The gate's G3 findings for the synthetic table: energy and sodium (each satisfied by its
    /// calculated value) and saturates, which stays a flag.
    static let gateFlags = [
        LabelReading.Flag(code: "required_row_missing", concerns: "energy_kcal"),
        LabelReading.Flag(code: "required_row_missing", concerns: "saturates"),
        LabelReading.Flag(code: "required_row_missing", concerns: "sodium")
    ]

    static func reading(candidate: PastedLabelManifest.Candidate? = nil, format: String = "taiwan_nutrition_labelling",
                        gate: LabelReading.Gate? = LabelReading.Gate(format: "taiwan_nutrition_labelling", skipped: nil,
                                                                    hardDeclines: [], flags: gateFlags),
                        checks: [LabelReading.Check] = [energyCheck],
                        conversions: [PastedLabelManifest.Conversion] = [F.kcal, F.sodium],
                        storedHeaderID: String? = "h2") throws -> LabelReading {
        LabelReading(origin: .pastedText, textSHA256: try F.textHash(), candidate: try candidate ?? F.candidate(), format: format,
                     gate: gate, checks: checks, conversions: conversions, storedHeaderID: storedHeaderID, versions: versions)
    }

    static func review(_ reading: LabelReading) throws -> PastedLabelReview {
        guard case let .usable(review) = PastedLabelReader.classify(reading, pastedText: F.pastedText) else {
            throw PastedLabelSourceError.invalidManifest("fixture reading is not usable")
        }
        return review
    }

    static func builder(conversions: (any PastedLabelConversionChecking)? = GoldenPastedLabelConversions(),
                        at date: Date = LedgerFixtures.date) -> PastedLabelConfirmation {
        PastedLabelConfirmation(ids: RandomLedgerIDGenerator(), clock: FixedClock(value: date), encoder: LedgerFixtures.encoder,
                                digester: LedgerFixtures.digester, conversions: conversions)
    }

    static let details = PastedLabelDetails(name: "Synthetic oat crackers", brand: "Synthetic Mill", fortification: .no)
    static let locale = try! LedgerText("zh_TW")

    static func input(_ review: PastedLabelReview, details: PastedLabelDetails = details,
                      corrections: [PastedLabelManifest.Correction] = [],
                      conversions: (any PastedLabelConversionChecking)? = GoldenPastedLabelConversions()) throws -> PopulatedFoodConfirmation {
        try builder(conversions: conversions).confirmation(review, details: details, corrections: corrections, locale: locale)
    }

    static func manifest(_ input: PopulatedFoodConfirmation) throws -> PastedLabelManifest {
        guard case let .text(payload) = input.evidence[0].originalPayload,
              let manifest = PastedLabelManifest.decode(Data(payload.value.utf8)) else {
            throw PastedLabelSourceError.invalidManifest("payload")
        }
        return manifest
    }
}

/// A `LabelTextReading` that returns one reading and counts its calls.
final class StubLabelTextReader: LabelTextReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    let reading: LabelReading

    init(_ reading: LabelReading) { self.reading = reading }

    var calls: Int { lock.withLock { _calls } }

    func read(_ text: String, textSHA256: String) -> LabelReading {
        lock.withLock { _calls += 1 }
        return reading
    }
}
