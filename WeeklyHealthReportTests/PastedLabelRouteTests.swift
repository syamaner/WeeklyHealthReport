import XCTest
import SwiftUI
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
@testable import WeeklyHealthReport

/// Pasted nutrition label PR 4 (#93) at app level, through the composition root and the real
/// on-device reader (contract tests 23 and 24): Add food → Paste nutrition label → read →
/// Confirm → Log, and a declined paste → edit → read → Confirm. Every label text here is
/// synthetic, in the Taiwan template shape of the evaluation; none is a real product label.
@MainActor
final class PastedLabelRouteTests: XCTestCase {
    private static let rows = [
        "熱量  167.7 大卡  419.2 大卡",
        "蛋白質  6.0 公克  15.1 公克",
        "脂肪  3.8 公克  9.6 公克",
        "　飽和脂肪  0.5 公克  1.3 公克",
        "　反式脂肪  < 0.1 公克  < 0.1 公克",
        "碳水化合物  29.2 公克  72.9 公克",
        "　糖  < 0.5 公克  < 0.5 公克",
        "　膳食纖維  3.8 公克  9.6 公克",
        "鈉  101 毫克  252 毫克"
    ]

    private static func taiwan(_ rows: [String] = rows, header: String = "　　　　每份  每100公克", pack: String? = "本包裝含 2 份") -> String {
        (["營養標示", "每一份量 40 公克"] + [pack].compactMap { $0 } + [header] + rows).joined(separator: "\n") + "\n"
    }

    private static let base = taiwan()
    private static let kilojoulesOnly = taiwan(["熱量  701.7 kJ  1754 kJ"] + rows.dropFirst())
    /// A supplement marker in the header (gate G2).
    private static let supplement = taiwan(header: "　　　　營養補充 每份  每100公克")

    func testAddFoodPasteNutritionLabelReadConfirmAndLog() throws {
        let root = try makeRoot()
        let model = root.pastedLabelTextModel(locale: Locale(identifier: "en_GB"))
        model.name = "Synthetic oat crackers"
        model.fortification = .no
        model.text = Self.base
        let source = try XCTUnwrap(model.readLabel(), "\(model.declineMessages)")
        XCTAssertFalse(root.searchDiagnostics.pastedLabelLines.isEmpty, "Developer tools show the reading while the screen is open")
        XCTAssertTrue(source.isEditable)
        XCTAssertEqual(source.sourceLine, "From pasted label · per 100 g · Traditional Chinese, Taiwan layout")
        XCTAssertEqual(source.rows.first { $0.id == "protein" }?.value, "15.1 g")
        XCTAssertEqual(source.rows.first { $0.id == "protein" }?.origin, .printed)
        XCTAssertEqual(source.readButNotUsed.map(\.title), ["反式脂肪"], "trans fat is read but not stored (#270)")

        let confirm = root.model(for: try XCTUnwrap(source.input), prefillSourceQuantity: false)
        let view = root.pastedLabelConfirmation(confirm, source: source, editLabelText: {}, leave: {})
        XCTAssertTrue(confirm.missingSourceDetails.isEmpty, "Fortified? answered: no sourceIdentityMissing")
        XCTAssertNil(source.setValue("fibre", text: "9.8", unit: "g"), "printed 9.6, corrected by the user")
        XCTAssertEqual(confirm.state.selectedCandidate.candidate.nutrients.entries.first { $0.key == .fiber }?.value.provenance.first?.sourceKind,
                       .manualDeclaration, "a correction replaces Confirm's source input")
        confirm.send(.setQuantity(40, .grams))
        XCTAssertTrue(confirm.canLog, confirm.blockedReason ?? "")
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            render(NavigationStack { PastedLabelTextView(model: model, openConfirm: { _ in }, search: {}, scanBarcode: {}, leave: {}) }
                .environment(\.dynamicTypeSize, size), "Pasted label - label text \(name)")
            render(NavigationStack { view }.environment(\.dynamicTypeSize, size), "Pasted label - Confirm \(name)")
        }
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult, confirm.state.phase == .editing ? (confirm.blockedReason ?? "") : "\(confirm.state.phase)")
        model.dismissed()
        XCTAssertTrue(root.searchDiagnostics.pastedLabelLines.isEmpty, "cleared when the screen closes")
        XCTAssertEqual(model.text, "")

        // The saved entry, Edit and Recent foods show the stored label read-only, never re-read.
        let detail = try XCTUnwrap(try root.foodLogService.savedEntry(saved.logItem.logItemID))
        XCTAssertEqual(detail.valueOrigins[.fiber], .correctedByYou)
        XCTAssertEqual(detail.valueOrigins[.protein], .printed)
        XCTAssertEqual(PastedLabelSavedEntryText.originLines(detail), ["Fibre: Corrected by you"])
        let reopened = try XCTUnwrap(try root.model(reopening: saved.logItem.logItemID))
        let stored = try XCTUnwrap(PastedLabelSourceModel.stored(reopened.state))
        XCTAssertFalse(stored.isEditable)
        XCTAssertEqual(stored.rows.map(\.origin), source.rows.map(\.origin))
        let relog = try XCTUnwrap(try root.model(relogging: saved.logItem.logItemID))
        XCTAssertNotNil(PastedLabelSourceModel.stored(relog.state))
        // Identity and bytes, not Date equality (a store round trip can differ below a millisecond).
        XCTAssertEqual(relog.state.input.evidence.map(\.evidenceID), saved.evidence.map(\.evidenceID), "re-log reuses the stored evidence")
        XCTAssertEqual(relog.state.input.evidence.map(\.byteHash), saved.evidence.map(\.byteHash))
    }

    func testADeclinedPasteCanBeEditedAndReadAgain() throws {
        let root = try makeRoot()
        let model = root.pastedLabelTextModel(locale: Locale(identifier: "en_GB"))
        model.name = "Synthetic oat crackers"
        model.text = Self.supplement
        XCTAssertNil(model.readLabel())
        XCTAssertEqual(model.declineMessages, ["This looks like a supplement panel, which the app does not read."])
        XCTAssertEqual(model.text, Self.supplement, "the text is kept")
        XCTAssertTrue(root.searchDiagnostics.pastedLabelLines.first?.contains("not_a_food_nutrition_panel") == true)
        XCTAssertEqual(try root.intakeProjection(for: Date()).summary.itemCount, 0, "a decline writes nothing")
        model.text = Self.base
        let source = try XCTUnwrap(model.readLabel())
        XCTAssertTrue(model.declineMessages.isEmpty)
        XCTAssertEqual(source.pastedText, Self.base)
        // Fortified? left unanswered: the existing details requirement, never a block on reading.
        let confirm = root.model(for: try XCTUnwrap(source.input), prefillSourceQuantity: false)
        XCTAssertEqual(confirm.missingSourceDetails, [.fortification])
    }

    func testAKilojouleOnlyLabelShowsCalculatedEnergyEverywhere() throws {
        let root = try makeRoot()
        let model = root.pastedLabelTextModel(locale: Locale(identifier: "en_GB"))
        model.name = "Synthetic oat crackers"
        model.fortification = .no
        model.text = Self.kilojoulesOnly
        let source = try XCTUnwrap(model.readLabel(), "\(model.declineMessages)")
        let energy = try XCTUnwrap(source.rows.first { $0.id == "energy_kcal" })
        XCTAssertEqual(energy.origin, .calculated(rule: "kj_to_kcal_v1"))
        XCTAssertTrue(energy.value.hasPrefix("about "))
        XCTAssertTrue(energy.originText.hasPrefix("Calculated from 1754 kJ (printed)"))
        let confirm = root.model(for: try XCTUnwrap(source.input), prefillSourceQuantity: false)
        _ = root.pastedLabelConfirmation(confirm, source: source, editLabelText: {}, leave: {})
        confirm.send(.setQuantity(100, .grams))
        confirm.log()
        let saved = try XCTUnwrap(confirm.savedResult)
        let detail = try XCTUnwrap(try root.foodLogService.savedEntry(saved.logItem.logItemID))
        XCTAssertEqual(detail.valueOrigins[.energyConsumed], .calculated(rule: "kj_to_kcal_v1"))
        XCTAssertTrue(PastedLabelSavedEntryText.reportText(detail)?.contains("Calculated from 1754 kJ (printed), kcal = kJ ÷ 4.184") == true)
        let day = try root.intakeProjection(for: saved.logItemVersion.occurredAt)
        XCTAssertEqual(day.summary.totals.first { $0.key == .energyConsumed }?.includesEstimates, true,
                       "a calculated contribution marks the day total as including estimates")
    }

    func testAddFoodOffersThePasteNutritionLabelRow() throws {
        let root = try makeRoot()
        var opened = false
        let view = AddFoodView(recents: [], search: { _ in }, scanBarcode: {}, pasteOrDictate: {}, pasteLabel: { opened = true },
                               favourites: {}, relog: { _ in })
        let action = try XCTUnwrap(Mirror(reflecting: view).descendant("pasteLabel") as? () -> Void)
        action()
        XCTAssertTrue(opened)
        XCTAssertEqual(PastedLabelText.addFoodRow, "Paste nutrition label")
        XCTAssertNotNil(Mirror(reflecting: AddFoodFlowView(root: root)).descendant("root"))
        for (size, name) in [(DynamicTypeSize.large, "standard"), (.accessibility3, "accessibility3")] {
            render(NavigationStack { view }.environment(\.dynamicTypeSize, size), "Add food - paste nutrition label row \(name)")
        }
    }

    // MARK: Helpers

    private func makeRoot() throws -> FoodLedgerCompositionRoot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let name = "pasted-label-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults)
    }

    private func render<V: View>(_ content: V, _ name: String) {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(image.size.width, 390)
        window.isHidden = true
    }
}
