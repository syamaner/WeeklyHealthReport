import FoodLedgerApplication
import FoodLedgerDomain
@testable import FoodLedgerPresentation
import Foundation
import XCTest

/// The Nutrition label entry (docs/nutrition-label-entry-v1.md 3 and 6.2 tests 1 to 6): the pure
/// classifier, the entry model's sections and copy, the paste states and the routing into the
/// photo and text screens. Synthetic payloads and closures only; no clipboard, no image framework.
@MainActor
final class NutritionLabelEntryPresentationTests: XCTestCase {
    typealias Kind = NutritionLabelPasteKind
    typealias T = NutritionLabelEntryText

    static let image = Data("synthetic pasted label image".utf8)
    static let text = "  營養標示\n每一份量 30 公克\n熱量  111 大卡  \n"

    final class Routes {
        var images: [Data] = []
        var texts: [String] = []
        var count: Int { images.count + texts.count }
    }

    func entry(photos: Bool, _ routes: Routes) -> NutritionLabelEntryModel {
        NutritionLabelEntryModel(photosEnabled: photos, openImage: { routes.images.append($0) }, openText: { routes.texts.append($0) })
    }

    // MARK: Test 1: the classifier

    func testTheClassifierDecidesFromWhatLoaded() {
        XCTAssertEqual(Kind.classify(hasImage: true, hasText: false), .image)
        XCTAssertEqual(Kind.classify(hasImage: false, hasText: true), .text)
        XCTAssertEqual(Kind.classify(hasImage: true, hasText: true), .both)
        XCTAssertEqual(Kind.classify(hasImage: false, hasText: false), .neither)
        for blank in [nil, "", " ", "\n\t ", "\u{3000}\u{3000}", "\r\n"] {
            XCTAssertFalse(Kind.hasUsableText(blank), "whitespace-only text is no text: \(String(describing: blank))")
        }
        XCTAssertTrue(Kind.hasUsableText(" 熱量 "))
        XCTAssertEqual(Kind.classify(hasImage: true, hasText: Kind.hasUsableText("  \n")), .image, "an image with whitespace text is an image")
    }

    func testTheClassifierFileImportsNothing() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FoodLedgerPresentation/NutritionLabelPasteKind.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("import "), "the classifier is pure Swift")
    }

    // MARK: Test 2: the entry model's sections and copy

    func testModeOffAndNotOffGiveTheirSectionsFootersAndSubtitle() {
        let routes = Routes()
        let on = entry(photos: true, routes)
        XCTAssertTrue(on.showsPhotoSection)
        XCTAssertTrue(on.acceptsImages)
        XCTAssertEqual(on.photoFooter, "Taiwan labels only. The part you crop is sent to OpenRouter to be read. Nothing else is sent.")
        XCTAssertEqual(on.pasteFooter, "Paste a screenshot of a label, or its text. Text is read on this device.")
        XCTAssertEqual(on.addFoodRowSubtitle,
                       "Photo, screenshot or pasted text. Photos: Taiwan labels (營養標示), read by AI; you check every value.")
        XCTAssertTrue(on.addFoodRowSubtitle.contains("Taiwan labels"), "the Taiwan scope stays in the not-off copy")
        XCTAssertTrue(on.photoFooter.contains("Taiwan labels only"))

        let off = entry(photos: false, routes)
        XCTAssertFalse(off.showsPhotoSection)
        XCTAssertFalse(off.acceptsImages, "off requests plain text only")
        XCTAssertEqual(off.pasteFooter, "Paste the label text. Reading label photos is not available in this version.")
        XCTAssertEqual(off.addFoodRowSubtitle, "Paste or type the label text. Read on this device.")
        XCTAssertEqual(T.addFoodRow, "Nutrition label")
        XCTAssertEqual(T.typeOrPaste, "Type or paste text")
        XCTAssertFalse(off.typeOrPasteDisabled, "Type or paste text is always enabled")
    }

    func testOffModeNeverRoutesAnImage() {
        let routes = Routes()
        let off = entry(photos: false, routes)
        off.handle(.loading)
        off.handle(.loaded(imageData: Self.image, text: nil))
        XCTAssertEqual(off.pasteState, .nothing, "an image is never taken in off mode")
        off.photoChosen(Self.image)
        off.handle(.loading)
        off.handle(.loaded(imageData: Self.image, text: Self.text))
        XCTAssertEqual(routes.images, [])
        XCTAssertEqual(routes.texts, [Self.text])
    }

    func testTheCopyHasNoEmDashOrEmoji() {
        let copy = [T.addFoodRow, T.title, T.addFoodRowSubtitlePhotos, T.addFoodRowSubtitleTextOnly, T.photoSectionTitle, T.photoFooter,
                    T.pasteSectionTitle, T.pasteFooterPhotos, T.pasteFooterTextOnly, T.typeOrPaste, T.loading, T.imageFailed, T.readText,
                    T.readImage, T.nothing]
        for line in copy {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.unicodeScalars.contains { $0.properties.isEmojiPresentation }, line)
        }
        XCTAssertEqual(T.loading, "Reading the clipboard…")
        XCTAssertEqual(T.imageFailed, "The pasted image could not be opened. Nothing was sent.")
        XCTAssertEqual(T.readText, "Read the text on this device")
        XCTAssertEqual(T.readImage, "Read the image with AI")
        XCTAssertEqual(T.nothing, "The clipboard has no label image or text.")
    }

    // MARK: Test 3: the paste states

    func testLoadingDisablesPasteAndTypeOrPasteText() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        XCTAssertFalse(model.pasteDisabled)
        model.handle(.loading)
        XCTAssertEqual(model.pasteState, .loading)
        XCTAssertEqual(model.message, "Reading the clipboard…")
        XCTAssertTrue(model.pasteDisabled)
        XCTAssertTrue(model.typeOrPasteDisabled)
        model.typeOrPaste()
        XCTAssertEqual(routes.count, 0, "Type or paste text does nothing while loading")
    }

    func testAFailedImageShowsItsCopyAndCallsNeitherRoute() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.handle(.loading)
        model.handle(.failed(text: nil))
        XCTAssertEqual(model.pasteState, .failed(offersText: false))
        XCTAssertEqual(model.message, "The pasted image could not be opened. Nothing was sent.")
        XCTAssertEqual(model.choices, [])
        XCTAssertEqual(routes.count, 0)
        model.handle(.loading)
        model.handle(.failed(text: " \n"))
        XCTAssertEqual(model.choices, [], "whitespace text offers nothing")
        XCTAssertFalse(model.pasteDisabled)
    }

    func testAFailedImageWithTextOffersOnlyReadTheTextAndDropsTheImage() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.handle(.loading)
        model.handle(.failed(text: Self.text))
        XCTAssertEqual(model.pasteState, .failed(offersText: true))
        XCTAssertEqual(model.choices, ["Read the text on this device"])
        XCTAssertEqual(routes.count, 0, "neither route is called automatically")
        model.readImage()
        XCTAssertEqual(routes.count, 0, "there is no image to read")
        model.readText()
        XCTAssertEqual(routes.texts, [Self.text])
        XCTAssertEqual(routes.images, [])
        XCTAssertFalse(model.holdsPayload)
        XCTAssertEqual(model.pasteState, .idle)
    }

    func testLeavingDuringALoadIgnoresItsResult() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.handle(.loading)
        model.leave()
        XCTAssertEqual(model.pasteState, .idle)
        model.handle(.loaded(imageData: Self.image, text: Self.text))
        model.handle(.failed(text: Self.text))
        XCTAssertEqual(model.pasteState, .idle)
        XCTAssertEqual(routes.count, 0, "a load finishing after leaving routes nothing")
        XCTAssertFalse(model.holdsPayload)
    }

    func testChoosingInBothDropsTheOtherPayload() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.handle(.loading)
        model.handle(.loaded(imageData: Self.image, text: Self.text))
        XCTAssertEqual(model.pasteState, .both)
        XCTAssertEqual(model.choices, ["Read the image with AI", "Read the text on this device"])
        XCTAssertEqual(routes.count, 0, "the user chooses (Q2)")
        model.readImage()
        XCTAssertEqual(routes.images, [Self.image])
        XCTAssertFalse(model.holdsPayload)
        model.readText()
        XCTAssertEqual(routes.texts, [], "the text was dropped")

        model.handle(.loading)
        model.handle(.loaded(imageData: Self.image, text: Self.text))
        model.readText()
        XCTAssertEqual(routes.texts, [Self.text])
        model.readImage()
        XCTAssertEqual(routes.images, [Self.image], "the image was dropped")
    }

    func testLeavingOrGoingToTheBackgroundDropsBothAndRoutesNothing() {
        for state in ["both", "failed"] {
            let routes = Routes()
            let model = entry(photos: true, routes)
            model.handle(.loading)
            if state == "both" { model.handle(.loaded(imageData: Self.image, text: Self.text)) } else { model.handle(.failed(text: Self.text)) }
            XCTAssertTrue(model.holdsPayload, state)
            // The screen calls `leave()` on disappearing and when the scene goes to the background.
            model.leave()
            XCTAssertFalse(model.holdsPayload, state)
            XCTAssertEqual(model.pasteState, .idle, state)
            model.readImage(); model.readText()
            XCTAssertEqual(routes.count, 0, state)
        }
    }

    func testNothingUsableIsSaidInline() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.handle(.loading)
        model.handle(.loaded(imageData: nil, text: "   "))
        XCTAssertEqual(model.pasteState, .nothing)
        XCTAssertEqual(model.message, "The clipboard has no label image or text.")
        XCTAssertEqual(routes.count, 0)
    }

    // MARK: Test 4: image routing into the photo screen

    final class Script {
        var reads = 0
        var consented = false
        var key: LabelPhotoScreenModel.KeyState = .valid
        var online = true
        var status = LabelPhotoReadSession.Status(day: .open(reads: 3), routeUnavailable: false)
    }

    static var prepared: PreparedLabelImage {
        try! PreparedLabelImageFactory.make(bytes: Data("synthetic prepared label photo".utf8), pixelWidth: 900, pixelHeight: 900,
                                            jpegQuality: "0.85", digester: SHA256Digester())
    }

    func screen(_ script: Script) -> LabelPhotoScreenModel {
        LabelPhotoScreenModel(environment: .init(
            prepare: { _, _ in .success(Self.prepared) },
            read: { _, _ in script.reads += 1; return .failed(.timedOut) },
            status: { script.status }, keyState: { script.key }, isOnline: { script.online },
            hasConsented: { script.consented }, recordConsent: { script.consented = true },
            makeConfirm: { _, _, _ in throw CancellationError() }))
    }

    func testAPastedImageReachesChooseAndNothingElse() async {
        let script = Script()
        let photo = screen(script)
        let routes = Routes()
        // The composition root's route: the image is handed to `choose(_:)` once the photo screen appears.
        let model = NutritionLabelEntryModel(photosEnabled: true, openImage: { routes.images.append($0); photo.choose($0) },
                                             openText: { routes.texts.append($0) })
        model.handle(.loading)
        model.handle(.loaded(imageData: Self.image, text: "   "))
        XCTAssertEqual(routes.images, [Self.image])
        XCTAssertEqual(routes.texts, [])
        XCTAssertEqual(photo.photo, Self.image)
        XCTAssertNil(photo.prepared)
        XCTAssertTrue(photo.cropping, "choose opens the crop step only")
        photo.name = "Synthetic crackers"
        await photo.refresh()
        XCTAssertFalse(photo.canRead, "Read cannot be tapped until the crop is used")
        photo.readTapped()
        XCTAssertEqual(script.reads, 0)
        photo.useCrop(.whole)
        XCTAssertTrue(photo.canRead)
        photo.readTapped()
        XCTAssertTrue(photo.showsFirstUseSheet, "without consent the first-use sheet comes first")
        await Task.yield()
        XCTAssertEqual(script.reads, 0, "nothing is sent before Send photo")
    }

    func testWithEachBlockerAPastedImageKeepsReadDisabled() async {
        let blockers: [(LabelPhotoScreenModel.Blocker, (Script) -> Void)] = [
            (.noKey, { $0.key = .missing }), (.keyNotValidated, { $0.key = .notValidated }), (.offline, { $0.online = false }),
            (.dailyLimit, { $0.status = .init(day: .limitReached, routeUnavailable: false) }),
            (.paused, { $0.status = .init(day: .paused, routeUnavailable: false) }),
            (.routeUnavailable, { $0.status = .init(day: .open(reads: 1), routeUnavailable: true) }),
        ]
        for (blocker, apply) in blockers {
            let script = Script()
            script.consented = true
            apply(script)
            let photo = screen(script)
            let model = NutritionLabelEntryModel(photosEnabled: true, openImage: { photo.choose($0) }, openText: { _ in })
            model.handle(.loading)
            model.handle(.loaded(imageData: Self.image, text: nil))
            XCTAssertTrue(photo.cropping, "\(blocker): the crop step opens whatever the blocker")
            photo.useCrop(.whole)
            photo.name = "Synthetic crackers"
            await photo.refresh()
            XCTAssertEqual(photo.blocker, blocker)
            XCTAssertFalse(photo.canRead, "\(blocker)")
            photo.readTapped()
            XCTAssertEqual(script.reads, 0, "\(blocker)")
        }
    }

    // MARK: Tests 5 and 6: text routing and the empty entry

    func testPastedTextIsRoutedByteForByte() {
        let routes = Routes()
        let model = entry(photos: false, routes)
        let padded = "\n\t " + Self.text + " \u{3000}\r\n"
        model.handle(.loading)
        model.handle(.loaded(imageData: nil, text: padded))
        XCTAssertEqual(routes.texts.count, 1)
        XCTAssertEqual(Array(routes.texts[0].utf8), Array(padded.utf8), "no trim, normalisation or truncation")
        let long = String(repeating: "熱", count: PastedLabelManifest.maximumTextScalars + 1)
        model.handle(.loading)
        model.handle(.loaded(imageData: nil, text: long))
        XCTAssertEqual(routes.texts.last, long, "a text over the limit reaches the text screen, which blocks it")
    }

    func testTypeOrPasteTextOpensTheTextScreenEmpty() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.typeOrPaste()
        XCTAssertEqual(routes.texts, [""])
        XCTAssertEqual(routes.images, [])
        XCTAssertEqual(model.pasteState, .idle, "nothing is read from the clipboard")
    }

    func testAChosenPhotoUsesTheSameRouteAsAPastedImage() {
        let routes = Routes()
        let model = entry(photos: true, routes)
        model.cameraWasDenied()
        XCTAssertTrue(model.cameraDenied)
        model.photoChosen(Self.image)
        XCTAssertEqual(routes.images, [Self.image])
        XCTAssertFalse(model.cameraDenied)
    }
}
