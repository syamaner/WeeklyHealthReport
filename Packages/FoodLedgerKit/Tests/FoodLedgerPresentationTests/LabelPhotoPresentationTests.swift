import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import Foundation
import XCTest

/// The label photo screen and Confirm source models (docs/label-photo-ai-prefill-v1.md 4.1, 7, 9
/// and 14): synthetic fixtures and closures only; no network, no image framework.
@MainActor
final class LabelPhotoPresentationTests: XCTestCase {
    // MARK: Fixtures

    final class Clock: LedgerClock, @unchecked Sendable {
        var value = Date(timeIntervalSince1970: 1_792_900_000)
        func now() -> Date { value }
    }

    struct NoConversions: PastedLabelConversionChecking {
        func storedTextMatches(_ record: PastedLabelManifest.Conversion) -> Bool { false }
    }

    static let digester = SHA256Digester()
    static let imageBytes = Data("synthetic prepared label photo".utf8)
    static var image: PreparedLabelImage {
        try! PreparedLabelImageFactory.make(bytes: imageBytes, pixelWidth: 900, pixelHeight: 900, jpegQuality: "0.85", digester: digester)
    }

    static func cell(_ nutrient: String, _ label: String, _ header: String, _ printed: String, _ decimal: String, _ unit: String,
                     _ canonical: String) -> PastedLabelManifest.Candidate.Cell {
        .init(rowID: nutrient, parentRowID: nil, nutrient: nutrient, printedLabel: label, headerID: header,
              basis: header == "h1" ? "per_serving" : "per_100g", printedText: printed, comparator: "=", decimalText: decimal,
              unit: unit, canonicalUnit: canonical, servingConversion: header == "h1" ? "30公克" : "not_applicable")
    }

    static func candidate() -> PastedLabelManifest.Candidate {
        let cells = [
            cell("energy_kcal", "熱量", "h1", "111大卡", "111", "大卡", "kcal"), cell("energy_kcal", "熱量", "h2", "370大卡", "370", "大卡", "kcal"),
            cell("protein", "蛋白質", "h1", "1.6公克", "1.6", "公克", "g"), cell("protein", "蛋白質", "h2", "5.8公克", "5.8", "公克", "g"),
            cell("fat", "脂肪", "h1", "2.0公克", "2.0", "公克", "g"), cell("fat", "脂肪", "h2", "6.7公克", "6.7", "公克", "g"),
        ]
        return PastedLabelManifest.Candidate(route: "C", inputSHA256: image.sha256, declined: false, declineReasons: [], wouldMarkReady: true,
            language: "zh-Hant", servingSize: .init(printedText: "每一份量30公克", decimalText: "30", unit: "公克", canonicalUnit: "g"),
            servingsPerPack: nil,
            headers: [.init(headerID: "h1", printedText: "每份", basis: "per_serving", servingConversion: "30公克"),
                      .init(headerID: "h2", printedText: "每100公克", basis: "per_100g", servingConversion: nil)],
            cells: cells, warnings: [])
    }

    static func reading() -> LabelPhotoReading {
        LabelPhotoReading(imageSHA256: image.sha256, candidate: candidate(), inferredFormat: LabelPhotoReading.labelFormat,
            gate: .init(format: LabelPhotoReading.labelFormat, skipped: nil, hardDeclines: [], flags: []), checks: [], conversions: [],
            storedHeaderID: "h2",
            versions: .init(mapping: "label-photo-wire-mapping-v1", gate: "label-capture-decline-gate-v2",
                            arithmetic: "label-arithmetic-checks-v2", conversion: "pasted-label-conversions-v1"))
    }

    /// Protein per 100 g not found; everything else found.
    static func locations() -> LabelPhotoManifest.Locations {
        let items = candidate().cells.map { LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID) } + ["serving_size"]
        let region = LabelPhotoManifest.Region(x: "0.4", y: "0.3", w: "0.1", h: "0.05")
        return .init(locatorVersion: "label-photo-vision-locate-v3", visionRevision: 3, languages: ["zh-Hant", "en-US"], records: items.map {
            $0 == "protein@h2" ? .init(item: $0, status: .notFound, region: nil) : .init(item: $0, status: .found, region: region)
        })
    }

    static func request() -> LabelPhotoManifest.Request {
        .init(model: "google/gemini-4-argon", endpoint: "google-vertex", reasoningLimit: 500, maxOutputTokens: 1_200,
              instructionVersion: LabelPhotoManifest.instructionVersion, instructionSHA256: String(repeating: "a", count: 64),
              wireSchemaVersion: "label-photo-wire-schema-v1", wireSchemaSHA256: String(repeating: "b", count: 64),
              catalogueCheck: .init(at: 1_792_899_000_000, slug: "google/gemini-4-argon", endpoint: "google-vertex",
                                    inputModalities: ["text", "image"], zeroDataRetention: true, promptPrice: "0.000002", completionPrice: "0.00001"))
    }

    static func reply() -> LabelPhotoWireReply {
        .init(wireText: "{}", model: "google/gemini-4-argon", provider: "Google Vertex", generationID: "gen-1", finishReason: "stop",
              attempts: 1, usage: .init(promptTokens: 2_000, completionTokens: 600, reasoningTokens: nil, costUSD: "0.01"),
              requestedAt: 1_792_899_900_000, completedAt: 1_792_899_910_000)
    }

    let clock = Clock()
    var builder: LabelPhotoConfirmation {
        LabelPhotoConfirmation(clock: clock, encoder: FoundationCanonicalJSONEncoder(), digester: Self.digester, conversions: NoConversions())
    }

    func review() throws -> LabelPhotoReview {
        try builder.review(reading: Self.reading(), image: Self.image, reply: Self.reply(), request: Self.request(), locations: Self.locations())
    }

    func source(fortification: PastedLabelIdentity.FortificationAnswer = .no) throws -> LabelPhotoSourceModel {
        try LabelPhotoSourceModel(review: review(), imageBytes: Self.imageBytes,
            details: PastedLabelDetails(name: "Synthetic crackers", brand: nil, fortification: fortification), builder: builder,
            imageEvidenceID: try EvidenceID("00000000-0000-4000-8000-000000009301"),
            manifestEvidenceID: try EvidenceID("00000000-0000-4000-8000-000000009300"), locale: try LedgerText("zh_TW"))
    }

    // MARK: Confirm source

    func testAnUnresolvedItemBlocksLogAndShowsInWords() throws {
        let model = try source()
        XCTAssertFalse(model.canLog)
        XCTAssertEqual(model.blocker, "Check the 1 highlighted value against the photo.")
        XCTAssertEqual(model.attentionSummary, "1 value needs your check before you can log.")
        let protein = try XCTUnwrap(model.rows.first { $0.id == "protein@h2" })
        XCTAssertEqual(protein.state, .notFound)
        XCTAssertEqual(protein.state.text, "Not found on photo. Check it.")
        XCTAssertEqual(protein.actions, [.matches, .correct, .leaveUnknown])
        XCTAssertEqual(protein.accessibilityLabel, "Protein, per 100 g, 5.8公克, Not found on photo. Check it.")
        let fat = try XCTUnwrap(model.rows.first { $0.id == "fat@h1" })
        XCTAssertEqual(fat.state, .found)
        XCTAssertEqual(fat.actions, [], "a found value in the other column needs nothing")
        // The preview counts the unchecked value as unknown, never as the read number.
        guard case .unknown? = model.input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .protein })?.value else {
            return XCTFail("protein is unknown until checked")
        }
    }

    func testMatchesThePhotoEnablesLogAndRebuildsTheInput() throws {
        let model = try source()
        var blockers: [String?] = []
        var inputs = 0
        model.onBlockerChange = { blockers.append($0) }
        model.onInputChange = { _ in inputs += 1 }
        model.matches("protein@h2")
        XCTAssertTrue(model.canLog)
        XCTAssertEqual(blockers, [nil])
        XCTAssertEqual(inputs, 1)
        XCTAssertEqual(model.rows.first { $0.id == "protein@h2" }?.state, .checked)
        XCTAssertNil(model.attentionSummary, "no count once every item is resolved")
        guard case let .measured(protein)? = model.input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .protein })?.value else {
            return XCTFail("checked protein is stored")
        }
        XCTAssertEqual(protein.amount, 5.8)
    }

    func testCorrectAndLeaveUnknown() throws {
        let model = try source()
        XCTAssertEqual(model.correct("protein@h2", text: "five"), LabelPhotoText.invalidValue)
        XCTAssertFalse(model.canLog)
        XCTAssertNil(model.correct("protein@h2", text: "5,2"))
        XCTAssertEqual(model.rows.first { $0.id == "protein@h2" }?.state, .corrected)
        XCTAssertEqual(model.rows.first { $0.id == "protein@h2" }?.value, "5.2 g")
        XCTAssertTrue(model.canLog)
        model.leaveUnknown("protein@h2")
        XCTAssertEqual(model.rows.first { $0.id == "protein@h2" }?.state, .leftUnknown)
        XCTAssertTrue(model.canLog)
        guard case .unknown? = model.input.candidates[0].candidate.nutrients.entries.first(where: { $0.key == .protein })?.value else {
            return XCTFail("left unknown stays unknown")
        }
        // Another column cannot be corrected here.
        XCTAssertEqual(model.correct("fat@h1", text: "2.1"), LabelPhotoText.notCorrectable)
    }

    func testShowOnPhotoCentresAFoundValueOrSaysItWasNotFound() throws {
        let model = try source()
        model.show("fat@h2")
        // Stored bottom-left (y 0.3, height 0.05) is drawn top-left at 1 - 0.3 - 0.05.
        XCTAssertEqual(model.focus?.region?.x, 0.4)
        XCTAssertEqual(try XCTUnwrap(model.focus?.region?.y), 0.65, accuracy: 1e-9)
        XCTAssertEqual(model.focus?.caption, "Fat, per 100 g")
        XCTAssertNil(model.focus?.message)
        XCTAssertEqual(model.focusAnnouncement, "Showing Fat, per 100 g, on the photo")
        let first = model.focus?.request
        model.show("protein@h2")
        XCTAssertNil(model.focus?.region)
        XCTAssertEqual(model.focus?.message, "This value was not found on the photo. Check the table yourself.")
        XCTAssertNotEqual(model.focus?.request, first)
    }

    func testFortificationAnswerRebuildsTheSource() throws {
        let model = try source(fortification: .unanswered)
        try model.answerFortification(.yes)
        XCTAssertEqual(model.fortificationAnswer, .yes)
        XCTAssertEqual(model.input.candidates[0].candidate.identity.fortification, .fortified)
    }

    // MARK: Label photo screen

    final class Script {
        var reads = 0
        var outcome: LabelPhotoReadFlow.Outcome = .failed(.timedOut)
        var consented = false
        var key: LabelPhotoScreenModel.KeyState = .valid
        var online = true
        var status = LabelPhotoReadSession.Status(day: .open(reads: 3), routeUnavailable: false)
        var hold = false
    }

    func screen(_ script: Script, prepare: LabelImagePreparationError? = nil) throws -> LabelPhotoScreenModel {
        let source = try self.source()
        return LabelPhotoScreenModel(environment: .init(
            prepare: { _, _ in prepare.map { .failure($0) } ?? .success(Self.image) },
            read: { _, progress in
                script.reads += 1
                progress(1)
                if script.hold {
                    progress(2)
                    while !Task.isCancelled { await Task.yield() }
                    return .failed(.cancelled)
                }
                return script.outcome
            },
            status: { script.status },
            keyState: { script.key }, isOnline: { script.online },
            hasConsented: { script.consented }, recordConsent: { script.consented = true },
            makeConfirm: { _, _, _ in source }))
    }

    func ready(_ model: LabelPhotoScreenModel) async {
        model.choose(Data([1]))
        model.useCrop(.whole)
        model.name = "Synthetic crackers"
        await model.refresh()
    }

    func testReadIsDisabledInEveryBlockingState() async throws {
        let script = Script()
        let model = try screen(script)
        XCTAssertFalse(model.canRead, "no photo")
        model.choose(Data([1])); model.useCrop(.whole)
        XCTAssertFalse(model.canRead, "no name")
        model.name = "  "
        XCTAssertFalse(model.canRead)
        model.name = "Synthetic crackers"
        XCTAssertFalse(model.canRead, "nothing is known about today's allowance yet")
        XCTAssertNil(model.underButton, "never a count before it is known")
        await model.refresh()
        XCTAssertTrue(model.canRead)
        XCTAssertEqual(model.underButton, "Uses your OpenRouter key and credit. Today: 3 of 30 reads.")
        script.key = .missing
        XCTAssertEqual(model.blocker, .noKey); XCTAssertFalse(model.canRead)
        XCTAssertEqual(model.blocker?.text, "Add your OpenRouter key to read label photos.")
        script.key = .notValidated
        XCTAssertEqual(model.blocker, .keyNotValidated)
        script.key = .valid; script.online = false
        XCTAssertEqual(model.blocker, .offline)
        XCTAssertEqual(model.blocker?.action, "Paste nutrition label")
        script.online = true
        let states: [(LabelPhotoReadSession.Status.Day, Bool, LabelPhotoScreenModel.Blocker?)] = [
            (.limitReached, false, .dailyLimit), (.unreadable, false, .dailyLimit), (.paused, false, .paused),
            (.open(reads: 29), true, .routeUnavailable), (.open(reads: 29), false, nil),
        ]
        for (day, routeUnavailable, expected) in states {
            script.status = .init(day: day, routeUnavailable: routeUnavailable)
            await model.refresh()
            XCTAssertEqual(model.blocker, expected, "\(day) \(routeUnavailable)")
            XCTAssertEqual(model.canRead, expected == nil)
        }
        script.status = .init(day: .limitReached, routeUnavailable: false)
        await model.refresh()
        XCTAssertNil(model.underButton, "no count is shown at the limit; the limit copy says it")
        XCTAssertEqual(model.blocker?.text, LabelPhotoText.dailyLimit)
        script.status = .init(day: .paused, routeUnavailable: false)
        await model.refresh()
        XCTAssertEqual(model.blocker?.text, LabelPhotoText.failedCostPaused)
    }

    func testTheFirstUseSheetComesOnceAndNotNowSendsNothing() async throws {
        let script = Script()
        let model = try screen(script)
        await ready(model)
        model.readTapped()
        XCTAssertTrue(model.showsFirstUseSheet)
        model.firstUseDeclined()
        await Task.yield()
        XCTAssertEqual(script.reads, 0, "Not now sends nothing")
        model.readTapped()
        model.firstUseAccepted()
        try await waitUntil { script.reads == 1 && !model.isBusy }
        XCTAssertTrue(script.consented)
        model.readTapped()
        XCTAssertFalse(model.showsFirstUseSheet, "later reads do not show it")
        try await waitUntil { script.reads == 2 && !model.isBusy }
    }

    func testOutcomesShowTheirCopyAndTryAgainIsANewTap() async throws {
        let script = Script(); script.consented = true
        let model = try screen(script)
        await ready(model)
        model.readTapped()
        try await waitUntil { !model.isBusy && script.reads == 1 }
        XCTAssertEqual(model.phase, .failed("Reading the photo timed out. You can try again."))
        XCTAssertNotNil(model.prepared, "the photo is kept")
        script.outcome = .declined(["unsupported_language"])
        model.readTapped()
        try await waitUntil { !model.isBusy && script.reads == 2 }
        XCTAssertEqual(model.phase, .declined([PastedLabelText.declineMessage(.unsupportedLanguage)]))
        script.outcome = .review(try review())
        model.readTapped()
        try await waitUntil { model.confirmSource != nil }
        XCTAssertEqual(script.reads, 3)
    }

    func testRetryingShowsTheAttemptAndCancelStopsWithItsCopy() async throws {
        let script = Script(); script.consented = true; script.hold = true
        let model = try screen(script)
        await ready(model)
        model.readTapped()
        try await waitUntil { model.phase == .retrying(attempt: 2) }
        XCTAssertEqual(model.progressText, "OpenRouter is busy. Trying again (attempt 2 of 3)…")
        model.cancel()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.phase, .failed("Stopped. The photo may already have reached OpenRouter; nothing was saved."))
    }

    func testACropTooSmallIsRefusedWithItsCopy() throws {
        let model = try screen(Script(), prepare: .cropTooSmall)
        model.choose(Data([1]))
        model.useCrop(.whole)
        XCTAssertNil(model.prepared)
        XCTAssertEqual(model.preparationFailure, "This crop is too small to read. Move closer or crop less tightly.")
        model.name = "Synthetic crackers"
        XCTAssertFalse(model.canRead)
    }

    func testEveryFailureAndDeclineHasCopy() {
        let failures: [LabelImageReadingFailure] = [.offline, .keyMissing, .keyRejected, .routeUnavailable, .dailyLimit, .paused, .timedOut,
            .cancelled, .providerUnavailable, .wrongModel, .wrongProvider, .truncated, .refused, .oversize, .unreadableAnswer, .failed, .quotaLimited]
        for failure in failures { XCTAssertFalse(LabelPhotoText.failure(failure).isEmpty, "\(failure)") }
        XCTAssertEqual(LabelPhotoText.failure(.quotaLimited), "OpenRouter reports a quota or rate limit. Check your quota and billing before trying again.")
        XCTAssertEqual(LabelPhotoText.failure(.paused), "This read cost more than the $0.05 limit, so label photo reading is paused for today.")
        for key in PastedLabelCodes.CopyKey.allCases {
            XCTAssertEqual(LabelPhotoText.declines([key.rawValue]).count, 1, key.rawValue)
        }
        XCTAssertEqual(LabelPhotoText.declines(["no_table"]), ["No nutrition table was found in this photo. Crop to the table and try again."])
        XCTAssertEqual(LabelPhotoText.declines([]), [LabelPhotoText.failedUnusable])
        let all = [LabelPhotoText.egressStatement, LabelPhotoText.firstUseBody, LabelPhotoText.honestyNote, LabelPhotoText.dailyLimit]
        XCTAssertTrue(all.allSatisfy { !$0.contains("—") && !$0.lowercased().contains("verified") && !$0.lowercased().contains("confidence") })
    }

    func testSavedProvenanceComesFromTheStoredResponse() {
        XCTAssertEqual(LabelPhotoText.savedSource(model: "google/gemini-4-argon", provider: "Google Vertex", date: "26 Oct 2026"),
                       "Read by Gemini 4 Argon on Google Vertex through OpenRouter, 26 Oct 2026; checked by you")
        // Anything not in the table is shown exactly as stored, never as the current route's name.
        XCTAssertEqual(LabelPhotoText.savedSource(model: "openai/gpt-6.1-sol", provider: "Azure", date: "1 Nov 2026"),
                       "Read by openai/gpt-6.1-sol on Azure through OpenRouter, 1 Nov 2026; checked by you")
    }

    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition never held", file: file, line: line)
    }
}
