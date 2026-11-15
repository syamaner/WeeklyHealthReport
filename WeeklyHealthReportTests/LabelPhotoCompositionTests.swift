import XCTest
import SwiftUI
import UniformTypeIdentifiers
import FoodLedgerApplication
import FoodLedgerPresentation
@testable import WeeklyHealthReport

/// The label photo route at the composition root (docs/label-photo-ai-prefill-v1.md 17.8 L2 and
/// 17.18; contract test 24): off by default, one read session per ledger per process, and the
/// attachments root and spend ledger under the backup-excluded health-data directory.
@MainActor
final class LabelPhotoCompositionTests: XCTestCase {
    func makeRoot(route: String?, switchOn: Bool = false, savedKey: String? = nil,
                  keys: (any FoodWebKeyStoring)? = nil) throws -> (FoodLedgerCompositionRoot, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "label-photo-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        if let route { defaults.set(route, forKey: "LabelPhotoRoute") }
        if switchOn { defaults.set(true, forKey: "labelPhoto.liveRoute.enabled.v1") }
        return (try FoodLedgerCompositionRoot(fileManager: IntakeRenderFileManager(directory: directory), userDefaults: defaults,
                                              openRouterKeys: keys ?? SyntheticOpenRouterKeys(key: savedKey)), directory)
    }

    // MARK: A key the Keychain could not return at launch (#493)

    func testAKeyUnreadableAtLaunchIsReadAgainAndTheRouteAndSettingsFollow() throws {
        let keys = LockedAtLaunchOpenRouterKeys(key: "sk-or-v1-synthetic", failingReads: 1)
        let (root, _) = try makeRoot(route: nil, switchOn: true, keys: keys)
        let settings = WeeklyHealthReportApp.makeSettings(foodLedger: root, defaults: root.userDefaults, medicationAccessAvailable: false)
        let availability = AddFoodLabelPhotoAvailability(root: root)
        var settingsChanges = 0
        let observer = settings.detailChanges.sink { settingsChanges += 1 }
        defer { observer.cancel() }

        XCTAssertTrue(root.webDiscovery.keyLoadFailed)
        assertHidden(root)
        XCTAssertFalse(availability.enabled)
        XCTAssertEqual(webLookupDetail(settings), "Key not read yet", "an unreadable key is not shown as missing")

        root.recheckSavedKeys()
        XCTAssertFalse(root.webDiscovery.keyLoadFailed)
        XCTAssertTrue(root.webDiscovery.hasSavedKey)
        XCTAssertFalse(root.webDiscovery.keyIsUsable, "reading the key again never validates it")
        XCTAssertEqual(root.labelPhotoMode, .live)
        XCTAssertTrue(availability.enabled, "Add food's Nutrition label row offers photos without reopening")
        XCTAssertTrue(NutritionLabelVisit(root: root).entry.photosEnabled)
        XCTAssertEqual(webLookupDetail(settings), "Revalidate key")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertGreaterThan(settingsChanges, 0, "an open Settings screen redraws the Web lookup row")
    }

    func testAKeyThatStaysUnreadableKeepsTheRouteHidden() throws {
        let keys = LockedAtLaunchOpenRouterKeys(key: "sk-or-v1-synthetic", failingReads: .max)
        let (root, _) = try makeRoot(route: nil, switchOn: true, keys: keys)
        let availability = AddFoodLabelPhotoAvailability(root: root)
        for _ in 0..<3 {
            root.recheckSavedKeys()
            XCTAssertTrue(root.webDiscovery.keyLoadFailed)
            XCTAssertFalse(root.webDiscovery.keyIsUsable)
            assertHidden(root)
            XCTAssertFalse(availability.enabled)
        }
    }

    func testAddFoodPhotoAvailabilityFollowsTheSwitch() throws {
        let (root, _) = try makeRoot(route: nil, savedKey: "sk-or-v1-synthetic")
        let availability = AddFoodLabelPhotoAvailability(root: root)
        XCTAssertFalse(availability.enabled)
        root.labelPhotoReading.isOn = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(availability.enabled)
        root.labelPhotoReading.isOn = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(availability.enabled)
    }

    private func webLookupDetail(_ settings: AppSettings) -> String? {
        for section in settings.sections {
            for row in section.rows where row.route == .webLookupKey {
                if case let .link(detail, _) = row.kind { return detail() }
            }
        }
        return nil
    }

    // MARK: The Settings switch (17.22)

    func testModeResolutionMatrix() {
        typealias Mode = LabelPhotoRouteMode
        for debug in [false, true] {
            for (on, key) in [(false, false), (false, true), (true, false), (true, true)] {
                XCTAssertEqual(Mode.resolve(launchArgument: nil, switchOn: on, keySaved: key, debugBuild: debug),
                               on && key ? .live : .off, "no argument, debug \(debug), switch \(on), key \(key)")
            }
        }
        for argument in ["live", "answer", "routeUnavailable", "Live", "unknown", ""] {
            for (on, key) in [(false, false), (false, true), (true, false), (true, true)] {
                XCTAssertEqual(Mode.resolve(launchArgument: argument, switchOn: on, keySaved: key, debugBuild: false),
                               on && key ? .live : .off, "Release ignores `\(argument)` and never reaches a scripted scenario")
            }
        }
        XCTAssertEqual(Mode.resolve(launchArgument: "answer", switchOn: true, keySaved: true, debugBuild: true), .fake(.answer),
                       "a Debug scenario wins over the switch")
        XCTAssertEqual(Mode.resolve(launchArgument: "live", switchOn: false, keySaved: false, debugBuild: true), .live,
                       "Debug `live` wins regardless of the switch and key")
        XCTAssertEqual(Mode.resolve(launchArgument: "Live", switchOn: true, keySaved: true, debugBuild: true), .off,
                       "an unknown Debug argument keeps the route off, even with the switch on")
    }

    func testTheSwitchWithASavedKeyTurnsOnTheLiveRouteAndOffHidesIt() throws {
        let (root, _) = try makeRoot(route: nil, savedKey: "sk-or-v1-synthetic")
        XCTAssertEqual(root.labelPhotoMode, .off, "off by default, even with a saved key")
        root.labelPhotoReading.isOn = true
        XCTAssertEqual(root.labelPhotoMode, .live)
        XCTAssertEqual(root.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.live.v1")
        XCTAssertEqual(root.labelPhotoActiveSpendLedgerURL, root.labelPhotoLiveSpendLedgerURL)
        XCTAssertTrue(root.labelPhotoActiveSpendLedgerURL.standardizedFileURL.path.hasPrefix(root.healthDirectory.standardizedFileURL.path + "/"))
        XCTAssertNil(root.labelPhotoSample, "the live route reads only real photos")
        XCTAssertNotNil(root.labelPhotoScreenModel())
        XCTAssertTrue(NutritionLabelVisit(root: root).entry.photosEnabled)
        XCTAssertEqual(addFoodPhotos(root), true)

        root.labelPhotoReading.isOn = false
        assertHidden(root)
    }

    func testTheSwitchWithNoSavedKeyStaysOff() throws {
        let (root, _) = try makeRoot(route: nil, switchOn: true)
        assertHidden(root)
    }

    func testADebugScenarioWithTheSwitchOnKeepsTheScriptedRecords() throws {
        let (root, _) = try makeRoot(route: "answer", switchOn: true, savedKey: "sk-or-v1-synthetic")
        XCTAssertEqual(root.labelPhotoMode, .fake(.answer))
        XCTAssertEqual(root.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.scripted.v1")
        XCTAssertEqual(root.labelPhotoActiveSpendLedgerURL, root.labelPhotoSpendLedgerURL)
    }

    func testTurningTheSwitchOffWhileTheScreenIsOpenStopsTheNextSend() async throws {
        let (root, _) = try makeRoot(route: nil, switchOn: true, savedKey: "sk-or-v1-synthetic")
        let model = try XCTUnwrap(root.labelPhotoScreenModel())
        XCTAssertNotEqual(model.blocker, .turnedOff)
        root.labelPhotoReading.isOn = false
        XCTAssertEqual(model.blocker, .turnedOff)
        XCTAssertFalse(model.canRead)
        root.labelPhotoReading.isOn = true
        XCTAssertNotEqual(model.blocker, .turnedOff, "back on with the same key and build, the same route is in force")
    }

    func testRemovingTheKeyWhileTheScreenIsOpenShowsNoKeyNotTurnedOff() throws {
        let (root, _) = try makeRoot(route: nil, switchOn: true, savedKey: "sk-or-v1-synthetic")
        let model = try XCTUnwrap(root.labelPhotoScreenModel())
        root.webDiscovery.removeKey()
        XCTAssertFalse(root.webDiscovery.hasSavedKey)
        XCTAssertEqual(model.blocker, .noKey, "the switch is still on; the cause is the missing key")
        XCTAssertFalse(model.canRead)
    }

    private func addFoodPhotos(_ root: FoodLedgerCompositionRoot) -> Bool? {
        let view = AddFoodView(recents: [], search: { _ in }, scanBarcode: {}, pasteOrDictate: {}, nutritionLabel: {},
                               nutritionLabelPhotos: root.labelPhotoEnabled, favourites: {}, relog: { _ in })
        return Mirror(reflecting: view).descendant("nutritionLabelPhotos") as? Bool
    }

    private func assertHidden(_ root: FoodLedgerCompositionRoot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(root.labelPhotoMode, .off, file: file, line: line)
        XCTAssertFalse(root.labelPhotoEnabled, file: file, line: line)
        XCTAssertNil(root.labelPhotoFlow(), file: file, line: line)
        XCTAssertNil(root.labelPhotoScreenModel(), file: file, line: line)
        let visit = NutritionLabelVisit(root: root)
        XCTAssertNil(visit.photoModel, file: file, line: line)
        XCTAssertFalse(visit.entry.photosEnabled, file: file, line: line)
        XCTAssertFalse(visit.entry.acceptsImages, "a pasted image is not accepted", file: file, line: line)
        XCTAssertEqual(visit.entry.addFoodRowSubtitle, NutritionLabelEntryText.addFoodRowSubtitle(photosEnabled: false), file: file, line: line)
        XCTAssertEqual(addFoodPhotos(root), false, "Add food shows the text-only subtitle", file: file, line: line)
    }

    func testTheRouteIsOffByDefault() throws {
        let (root, _) = try makeRoot(route: nil)
        XCTAssertFalse(root.labelPhotoEnabled)
        XCTAssertNil(root.labelPhotoFlow())
        XCTAssertNil(root.labelPhotoScreenModel())
        let (unknown, _) = try makeRoot(route: "Live")
        XCTAssertFalse(unknown.labelPhotoEnabled, "only a scripted scenario or exactly `live` enables it")
    }

    func testTheLiveRouteIsALaunchArgumentWithItsOwnConsentLedgerAndNoSample() throws {
        let (root, _) = try makeRoot(route: "live")
        XCTAssertEqual(root.labelPhotoMode, .live)
        XCTAssertEqual(root.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.live.v1")
        XCTAssertNotEqual(root.labelPhotoActiveSpendLedgerURL, root.labelPhotoSpendLedgerURL, "scripted reads never touch the real allowance")
        XCTAssertTrue(root.labelPhotoActiveSpendLedgerURL.standardizedFileURL.path.hasPrefix(root.healthDirectory.standardizedFileURL.path + "/"))
        XCTAssertNil(root.labelPhotoSample, "the live route reads only real photos")
        let (fake, _) = try makeRoot(route: "answer")
        XCTAssertEqual(fake.labelPhotoActiveConsentKey, "labelPhoto.egressConsent.scripted.v1")
        XCTAssertEqual(fake.labelPhotoActiveSpendLedgerURL, fake.labelPhotoSpendLedgerURL)
        XCTAssertNotNil(fake.labelPhotoSample)
    }

    func testTheSpendLedgerAndAttachmentsSitUnderTheBackupExcludedDirectory() throws {
        let (root, _) = try makeRoot(route: "answer")
        let health = root.healthDirectory.standardizedFileURL.path
        XCTAssertTrue(root.labelPhotoSpendLedgerURL.standardizedFileURL.path.hasPrefix(health + "/"))
        XCTAssertTrue(root.attachmentsRoot.standardizedFileURL.path.hasPrefix(health + "/"))
        XCTAssertEqual(try root.healthDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testOneReadSessionPerLedgerPerProcess() throws {
        let (root, _) = try makeRoot(route: "answer")
        let first = try XCTUnwrap(root.labelPhotoFlow())
        let second = try XCTUnwrap(root.labelPhotoFlow())
        XCTAssertTrue(first.session === second.session, "every screen and scene shares the session")
        XCTAssertNotNil(root.labelPhotoScreenModel())
        XCTAssertNotNil(root.labelPhotoScreenModel())
        XCTAssertTrue(try XCTUnwrap(root.labelPhotoFlow()).session === first.session)
    }

    // MARK: Nutrition label (#454, docs/nutrition-label-entry-v1.md 6.2 test 8)

    /// A pasted image or a chosen photo: what the Nutrition label screen hands the photo route.
    static let photo = Data("synthetic pasted label".utf8)

    func testTheControlFactoryExistsWhenOffAndAsksForTextOnly() throws {
        let (root, _) = try makeRoot(route: nil)
        XCTAssertNil(root.labelPhotoScreenModel(), "still nil when off")
        let controls = root.nutritionLabelControls
        XCTAssertNil(controls.sample, "the DEBUG seam is never honoured when off")
        XCTAssertEqual(AppNutritionLabelControls.contentTypes(acceptsImages: false), [.plainText], "off never requests images")
        XCTAssertEqual(AppNutritionLabelControls.contentTypes(acceptsImages: true), [.image, .plainText])
        let visit = NutritionLabelVisit(root: root)
        XCTAssertNil(visit.photoModel)
        XCTAssertNil(visit.photoViews, "no source buttons are asked for when off")
        XCTAssertFalse(visit.entry.showsPhotoSection)
        XCTAssertFalse(visit.entry.acceptsImages)
        visit.entry.handle(.loading)
        visit.entry.handle(.loaded(imageData: Self.photo, text: nil))
        XCTAssertFalse(visit.showsPhoto)
        XCTAssertFalse(visit.pending.isPending)
        // The screen renders with the factory in off mode, and asks it for text only.
        let recording = RecordingControls()
        render(NavigationStack {
            NutritionLabelEntryView(model: visit.entry, controls: recording, photoViews: nil, openSettings: {})
        })
        XCTAssertEqual(recording.requests.values, [false])
    }

    func testThePasteAndSourceButtonPathsShareTheInjectedModel() throws {
        let (root, _) = try makeRoot(route: "answer")
        let visit = NutritionLabelVisit(root: root)
        let model = try XCTUnwrap(visit.photoModel)
        XCTAssertTrue(visit.entry.showsPhotoSection)
        XCTAssertNotNil(visit.photoViews)
        visit.entry.handle(.loading)
        visit.entry.handle(.loaded(imageData: Self.photo, text: nil))
        XCTAssertTrue(visit.showsPhoto)
        XCTAssertTrue(visit.pending.isPending)
        XCTAssertFalse(model.cropping, "nothing is chosen until the photo screen appears")
        let flow = LabelPhotoFlowView(root: root, model: model, pending: visit.pending, finish: nil, close: {})
        let injected = try XCTUnwrap(Mirror(reflecting: flow).descendant("_model") as? ObservedObject<LabelPhotoScreenModel>)
        XCTAssertTrue(injected.wrappedValue === model, "the flow takes the injected model unchanged")
        // Consumed once, after the screen appears: the crop opens exactly once.
        visit.pending.consume(into: model)
        XCTAssertTrue(model.cropping)
        XCTAssertEqual(model.photo, Self.photo)
        XCTAssertFalse(visit.pending.isPending)
        model.cancelCrop()
        XCTAssertFalse(model.cropping, "Cancel crop returns to the photo screen")
        visit.pending.consume(into: model)
        XCTAssertFalse(model.cropping, "a reappearance finds nothing pending")
        // The source buttons take the same path into the same instance.
        visit.showsPhoto = false
        visit.entry.photoChosen(Self.photo)
        XCTAssertTrue(visit.showsPhoto)
        XCTAssertTrue(visit.photoModel === model)
        visit.pending.consume(into: model)
        XCTAssertTrue(model.cropping)
    }

    /// Closing the pasted-label screen drops the routed text from the visit.
    func testClosingTheTextScreenDropsTheText() throws {
        let (root, _) = try makeRoot(route: "answer")
        let visit = NutritionLabelVisit(root: root)
        visit.openText(" 營養標示\n")
        XCTAssertEqual(visit.text, " 營養標示\n")
        visit.showsText = false
        XCTAssertEqual(visit.text, "")
    }

    /// Going back from the photo screen by any means drops the photo from memory (E15), even though
    /// the visit keeps the one shared model for the next photo.
    func testPoppingThePhotoScreenDropsThePhoto() throws {
        let (root, _) = try makeRoot(route: "answer")
        let visit = NutritionLabelVisit(root: root)
        let model = try XCTUnwrap(visit.photoModel)
        visit.entry.photoChosen(Self.photo)
        visit.pending.consume(into: model)
        model.useCrop(.whole)
        model.name = "Earlier attempt"
        XCTAssertNotNil(model.photo)
        visit.showsPhoto = false
        XCTAssertNil(model.photo)
        XCTAssertNil(model.prepared)
        XCTAssertNil(model.confirmSource)
        XCTAssertEqual(model.name, "")
        XCTAssertTrue(visit.photoModel === model, "the next photo still uses the same instance")
    }

    func testThePastedTextOpensTheTextScreenWithItsBytes() throws {
        let (root, _) = try makeRoot(route: "answer")
        let visit = NutritionLabelVisit(root: root)
        let text = " 營養標示\n熱量  111 大卡 \n"
        visit.entry.handle(.loading)
        visit.entry.handle(.loaded(imageData: nil, text: text))
        XCTAssertTrue(visit.showsText)
        XCTAssertFalse(visit.showsPhoto)
        XCTAssertEqual(Array(visit.text.utf8), Array(text.utf8))
        XCTAssertEqual(root.pastedLabelTextModel(initialText: visit.text).text, text)
    }

    func testTheDebugPasteSampleIsHonouredOnlyWithTheFakeRoute() throws {
        for (route, honoured) in [("answer", true), ("live", false), (nil, false)] as [(String?, Bool)] {
            for sample in ["image", "text", "both", "brokenImage"] {
                let (root, _) = try makeRoot(route: route)
                root.userDefaults.set(sample, forKey: "LabelPasteSample")
                XCTAssertEqual(root.labelPasteSample != nil, honoured, "\(route ?? "off") \(sample)")
            }
        }
        let (root, _) = try makeRoot(route: "answer")
        root.userDefaults.set("both", forKey: "LabelPasteSample")
        let both = try XCTUnwrap(root.labelPasteSample)
        XCTAssertNotNil(both.imageData); XCTAssertNotNil(both.text)
        root.userDefaults.set("brokenImage", forKey: "LabelPasteSample")
        XCTAssertNil(UIImage(data: try XCTUnwrap(root.labelPasteSample?.imageData)), "the broken image never opens")
        root.userDefaults.set("unknown", forKey: "LabelPasteSample")
        XCTAssertNil(root.labelPasteSample)
    }

    func testAddFoodHasOneNutritionLabelRoute() {
        let view = AddFoodView(recents: [], search: { _ in }, scanBarcode: nil, pasteOrDictate: nil, nutritionLabel: {}, favourites: nil,
                               relog: { _ in })
        let labels = Mirror(reflecting: view).children.compactMap(\.label)
        XCTAssertTrue(labels.contains("nutritionLabel"))
        XCTAssertFalse(labels.contains("pasteLabel"))
        XCTAssertFalse(labels.contains("photoLabel"))
    }

    final class Requests { var values: [Bool] = [] }

    struct RecordingControls: NutritionLabelControlFactory {
        let requests = Requests()
        func pasteControl(acceptsImages: Bool, events: @escaping (NutritionLabelPasteEvent) -> Void) -> AnyView {
            requests.values.append(acceptsImages)
            return AnyView(Text("Paste"))
        }
    }

    private func render<V: View>(_ content: V) {
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        window.isHidden = true
    }

    func testTheScriptedRoutesConsentIsItsOwn() {
        // A consent given to the scripted transport never stands for live egress (L5 uses a fresh key).
        XCTAssertEqual(FoodLedgerCompositionRoot.labelPhotoConsentKey, "labelPhoto.egressConsent.scripted.v1")
    }
}

/// A key store for the switch tests: never the device Keychain, and nothing is ever sent.
private struct SyntheticOpenRouterKeys: FoodWebKeyStoring {
    let key: String?
    func load() throws -> String? { key }
    func save(_ key: String) throws {}
    func delete() throws {}
}

/// A synthetic key store whose first reads throw, as the Keychain does before first unlock (#493).
private final class LockedAtLaunchOpenRouterKeys: FoodWebKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let key: String?
    private var failingReads: Int
    init(key: String?, failingReads: Int) { self.key = key; self.failingReads = failingReads }
    func load() throws -> String? {
        try lock.withLock {
            if failingReads > 0 { failingReads -= 1; throw CocoaError(.fileReadNoPermission) }
            return key
        }
    }
    func save(_ key: String) throws {}
    func delete() throws {}
}
