import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerTestSupport
import XCTest

/// `NutrientValueOrigin` and the misread report builder (#93, PR 4; contract tests 33, 34 and
/// 42): one projection from a stored value's provenance, the calculated predicate and the
/// manifest's correction records and flags; and a report built only from allow-listed contents.
final class PastedLabelOriginContractTests: XCTestCase {
    private typealias F = PastedLabelFixtures

    func testEveryOriginIsProjectedFromTheStoredValueAndTheManifest() throws {
        let manifest = try F.manifest()
        let input = try F.input(manifest)
        let candidate = try XCTUnwrap(input.candidates.first)
        let stored = try XCTUnwrap(PastedLabelValueOrigins.manifest(input, candidate: candidate))
        XCTAssertEqual(stored, .v1(manifest))
        let origins = PastedLabelValueOrigins.origins(candidate.candidate.nutrients, manifest: stored)
        XCTAssertEqual(origins[.energyConsumed], .calculated(rule: "kj_to_kcal_v1"))
        XCTAssertEqual(origins[.sodium], .calculated(rule: "salt_to_sodium_v1"))
        XCTAssertEqual(origins[.protein], .correctedByYou)
        XCTAssertEqual(origins[.fiber], .enteredByYou)
        XCTAssertEqual(origins[.carbohydrates], .printed)
        XCTAssertEqual(origins[.fatTotal], .printed, "a bound is a value shape, not an origin")
        XCTAssertEqual(origins[.fatSaturated], .unknown(.notStated))
        XCTAssertEqual(origins[.vitaminC], .unknown(.notStated))
        XCTAssertEqual(origins.count, NutrientKey.allCases.count, "every value has exactly one origin")

        // A flag still shown at Log makes an unknown row "not read".
        let flagged = PastedLabelManifest(pastedText: manifest.pastedText, pastedTextSHA256: manifest.pastedTextSHA256,
            parserVersion: manifest.parserVersion, gateVersion: manifest.gateVersion, arithmeticVersion: manifest.arithmeticVersion,
            conversionVersion: manifest.conversionVersion, labelFormat: manifest.labelFormat, launchScope: manifest.launchScope,
            identityMapping: manifest.identityMapping, candidate: manifest.candidate, storedHeaderID: manifest.storedHeaderID,
            conversions: manifest.conversions, flagsShown: [.init(code: "required_row_missing", concerns: "saturates")],
            corrections: manifest.corrections, warningsShown: [], name: manifest.name, brand: manifest.brand)
        XCTAssertEqual(NutrientValueOrigin.project(.unknown(.notDeclared), key: .fatSaturated, manifest: flagged), .unknown(.notRead))
        XCTAssertEqual(NutrientValueOrigin.project(.unknown(.noCompatibleSource), key: .sugar, manifest: manifest), .unknown(.notRead),
                       "printed but unusable is not read, never not stated")
        // No other route has a pasted-label manifest.
        XCTAssertNil(PastedLabelValueOrigins.manifest(evidence: [], evidenceIDs: candidate.candidate.evidenceIDs))
    }

    /// Review Q3: a user declaration whose correction reference resolves to no record is never
    /// "Printed", and save verification refuses it before policy.
    func testAnUnresolvableCorrectionReferenceIsNeverPrintedAndIsRefusedAtSave() throws {
        let manifest = try F.manifest()
        let input = try F.input(manifest)
        let protein = try XCTUnwrap(input.candidates[0].candidate.nutrients.entries.first { $0.key == .protein }?.value)
        let declared = try XCTUnwrap(protein.provenance.first)
        XCTAssertEqual(declared.sourceKind, .manualDeclaration)
        let reference = try LedgerText((declared.manifestReference?.value ?? "").replacingOccurrences(of: "correction=0", with: "correction=99"))
        let dangling = NutrientValue.measured(try ExactNutrientValue(amount: 5.4, unit: .grams,
            sourceValue: .exact(SourceExactNutrientValue(amount: 5.4, unit: LedgerText("g"), basis: .per100Grams)),
            provenance: [NutrientProvenance(sourceKind: .manualDeclaration, sourceID: declared.sourceID,
                sourceReleaseID: declared.sourceReleaseID, evidenceID: declared.evidenceID, capturedAt: declared.capturedAt,
                manifestReference: reference)]))
        XCTAssertNotEqual(NutrientValueOrigin.project(dangling, key: .protein, manifest: manifest), .printed)
        XCTAssertEqual(NutrientValueOrigin.project(dangling, key: .protein, manifest: manifest), .enteredByYou)
        let tampered = try F.replacing(input, .protein, with: dangling)
        for harness in try LedgerFixtures.harnesses() {
            defer { harness.cleanup() }
            XCTAssertThrowsError(try F.service(harness).save(F.state(tampered), operationID: LedgerFixtures.operationID(9_960))) {
                XCTAssertEqual($0 as? FoodConfirmationSaveError, .invalidPastedLabelSource, harness.name)
            }
        }
    }

    func testTheReportBuilderUsesOnlyItsAllowList() throws {
        let manifest = try F.manifest()
        let report = PastedLabelMisreadReport(manifest: manifest)
        XCTAssertEqual(report.pastedText, manifest.pastedText)
        XCTAssertEqual(report.values.filter { if case .calculated = $0.origin { true } else { false } }.map(\.nutrient), ["energy_kcal", "sodium"])
        XCTAssertEqual(report.values.filter { $0.origin == .printed }.count, manifest.candidate.cells.count)
        XCTAssertEqual(report.servingSize, "每一份量30公克")
        XCTAssertEqual(report.servingsPerPack, "本包裝含10份")
        XCTAssertEqual(report.versions.parser, manifest.parserVersion, "the stored manifest's parser")
        let text = report.text(wording: Words())
        XCTAssertEqual(text, PastedLabelMisreadReport(manifest: manifest).text(wording: Words()), "deterministic")
        for withheld in [manifest.name, manifest.brand ?? "", "5.4", "2.0"] {
            XCTAssertFalse(text.contains(withheld), "\(withheld) is not in the allow-list")
        }
        let declined = PastedLabelMisreadReport(pastedText: "x", reading: nil, declineCodes: ["text_too_long"], warningCodes: [])
        XCTAssertEqual(declined.text(wording: Words()), "T\n\nP\nx\n\nD\ndecline:text_too_long\n\nV\nnutrition-label-text-parser-v3")
    }

    private struct Words: PastedLabelReportWording {
        func heading(_ heading: PastedLabelMisreadReport.Heading) -> String {
            switch heading { case .title: "T"; case .pastedText: "P"; case .valuesRead: "R"; case .serving: "S"
            case .declined: "D"; case .warnings: "W"; case .versions: "V" }
        }
        func value(_ value: PastedLabelMisreadReport.Value) -> String { "\(value.nutrient)=\(value.decimalText)" }
        func servingSize(_ printedText: String?) -> String { printedText ?? "-" }
        func servingsPerPack(_ printedText: String?) -> String { printedText ?? "-" }
        func decline(_ code: String) -> String { "decline:\(code)" }
        func warning(_ code: String) -> String { "warning:\(code)" }
        func versions(_ versions: PastedLabelMisreadReport.Versions) -> String { versions.parser }
        func basis(_ basis: String, origin: PastedLabelBasisOrigin) -> String { "basis:\(basis)" }
    }
}
