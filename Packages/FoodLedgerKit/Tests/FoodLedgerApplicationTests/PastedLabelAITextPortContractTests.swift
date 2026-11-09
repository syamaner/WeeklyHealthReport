import FoodLedgerApplication
import FoodLedgerTestSupport
import Foundation
import XCTest

/// Contract test 28 (docs/pasted-label-ai-text-v1.md 11.1 and 11.5): the application's fakes pass
/// the same port contract suites as the real adapters (`FoodLabelPhotoCaptureTests` and
/// `FoodLabelTextAIReadingTests` run them over the shipped adapters).
final class PastedLabelAITextPortContractTests: XCTestCase {
    typealias Contracts = PastedLabelAITextPortContracts

    func testTheScriptedAttempterPassesTheAttemptingContract() async {
        let body = Data(#"{"id":"gen-1"}"#.utf8)
        let fake = ScriptedPastedLabelAITextAttempter(body: body)
        let violations = await Contracts.attempting(fake, body: body, sends: { fake.sends })
        XCTAssertEqual(violations, [])
    }

    func testTheScriptedReaderPassesTheReadingContract() {
        let fake = ScriptedPastedLabelAITextReader(results: [Contracts.declinedAnswer: Self.declined, Contracts.ukAnswer: Self.ukRead])
        XCTAssertEqual(Contracts.reading(fake), [])
    }

    func testTheContractsCatchABrokenFake() async {
        // A reader that drops the fabricated value instead of flagging it fails the contract.
        let dropping = ScriptedPastedLabelAITextReader(results: [Contracts.declinedAnswer: Self.declined, Contracts.ukAnswer: Self.read(withFibre: false)])
        XCTAssertFalse(Contracts.reading(dropping).isEmpty)
        // An attempter that sends a refused text fails the contract.
        struct Leaky: PastedLabelAITextAttempting {
            let route = PastedLabelAITextRoute.gemini4ArgonVertexUS
            let counter: ScriptedPastedLabelAITextAttempter
            func attempt(text: String, timeout: TimeInterval) async -> PastedLabelAITextAttemptResult {
                await counter.attempt(text: text.isEmpty ? "x" : text, timeout: timeout)
            }
        }
        let counter = ScriptedPastedLabelAITextAttempter(body: Data())
        let violations = await Contracts.attempting(Leaky(counter: counter), body: Data(), sends: { counter.sends })
        XCTAssertTrue(violations.contains("an empty text was not refused"))
    }

    // MARK: The fake's scripted results

    static let declined = PastedLabelAITextReadingResult(
        outcome: .declined, failure: nil, declineReasons: ["model:not_a_nutrition_table"], textSHA256: Contracts.ukTextSHA256,
        inferredFormat: nil, candidate: nil, gate: nil, checks: [], conversions: [], storedHeaderID: nil,
        textDetector: .init(markers: []), candidateDetector: nil, values: [], servingLines: [], servingAttention: [:],
        versions: ScriptedPastedLabelAITextReader.versions)

    static var ukRead: PastedLabelAITextReadingResult { read(withFibre: true) }

    static func range(_ needle: String, after label: String) -> Range<Int> {
        let scalars = Array(Contracts.ukText.unicodeScalars)
        let labelScalars = Array(label.unicodeScalars), needleScalars = Array(needle.unicodeScalars)
        let lineStart = (0...(scalars.count - labelScalars.count)).first { Array(scalars[$0..<($0 + labelScalars.count)]) == labelScalars }!
        let start = (lineStart...(scalars.count - needleScalars.count)).first { Array(scalars[$0..<($0 + needleScalars.count)]) == needleScalars }!
        return start..<(start + needleScalars.count)
    }

    static func read(withFibre: Bool) -> PastedLabelAITextReadingResult {
        let rows: [(String, String, String)] = [("Energy", "energy_kj", "1046kJ"), ("Energy", "energy_kcal", "250kcal"), ("Fat", "fat", "9.5g"),
                                                ("of which saturates", "saturates", "3.2g"), ("Carbohydrate", "carbohydrate", "30g"),
                                                ("of which sugars", "sugars", "12g"), ("Protein", "protein", "8.1g"), ("Salt", "salt", "0.75g")]
        var values = rows.enumerated().map { index, row in
            PastedLabelAITextReadingResult.Value(rowIndex: index, valueIndex: 0, nutrient: row.1, printedLabel: row.0, headerID: "h1",
                                                 basis: "per_100g", printedText: row.2, modelUnit: nil, read: .cell(rowID: row.1),
                                                 locator: .found(range(row.2, after: row.0)), unitCheck: .printed, reasons: [])
        }
        if withFibre {
            values.append(.init(rowIndex: 8, valueIndex: 0, nutrient: "fibre", printedLabel: "Fibre", headerID: "h1", basis: "per_100g",
                                printedText: "3g", modelUnit: nil, read: .cell(rowID: "fibre"), locator: .notFound, unitCheck: .printed,
                                reasons: [.notFound]))
        }
        let cells = values.map { value in
            PastedLabelManifest.Candidate.Cell(rowID: value.nutrient, parentRowID: nil, nutrient: value.nutrient, printedLabel: value.printedLabel,
                                               headerID: "h1", basis: "per_100g", printedText: value.printedText, comparator: "=",
                                               decimalText: String(value.printedText.prefix { $0.isNumber || $0 == "." }),
                                               unit: String(value.printedText.drop { $0.isNumber || $0 == "." }),
                                               canonicalUnit: String(value.printedText.drop { $0.isNumber || $0 == "." }),
                                               servingConversion: "not_applicable")
        }
        let candidate = PastedLabelManifest.Candidate(route: "C", inputSHA256: Contracts.ukTextSHA256, declined: false, declineReasons: [],
                                                      wouldMarkReady: true, language: "en", servingSize: nil, servingsPerPack: nil,
                                                      headers: [.init(headerID: "h1", printedText: "Per 100g", basis: "per_100g", servingConversion: nil)],
                                                      cells: cells, warnings: [])
        return PastedLabelAITextReadingResult(outcome: .reachedConfirm, failure: nil, declineReasons: [], textSHA256: Contracts.ukTextSHA256,
                                              inferredFormat: PastedLabelAITextOffer.ukFormat, candidate: candidate, gate: nil, checks: [],
                                              conversions: [], storedHeaderID: "h1", textDetector: .init(markers: []), candidateDetector: nil,
                                              values: values, servingLines: [], servingAttention: [:],
                                              versions: ScriptedPastedLabelAITextReader.versions)
    }
}
