import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Shared contract suite for `FoodDocumentCapturing` and its part-read permission (#508 phase 3,
/// docs/web-lookup-part-read-phase3-gate.md section 4, contract test 18). The input is a page shape;
/// each subject turns a shape into a capturing instance and an address (the public capture serves
/// the synthetic HTML below through its seams; fakes script the shape). Returns its violations; an
/// empty list passes. No XCTest here, so the suite stays inside this target's allowed imports.
public enum FoodDocumentCapturePortContracts {
    public enum PageShape: String, CaseIterable, Sendable {
        /// A page within `FoodDocumentBounds.current`.
        case whole
        /// A page over the bounds whose nutrition table can be kept.
        case overBoundsWithPanel
        /// A page over the bounds with no nutrition table or list.
        case overBoundsWithoutPanel
    }

    public typealias Subject = @Sendable (PageShape) async throws -> (capture: any FoodDocumentCapturing, url: URL)

    /// Synthetic HTML for each shape (no real page).
    public static func html(_ shape: PageShape) -> String {
        let panel = "<h2>Nutrition</h2><table><caption>Typical values per 100g</caption>"
            + "<tr><th>Energy</th><td>61kcal</td></tr><tr><th>Fat</th><td>3.1g</td></tr>"
            + "<tr><th>Protein</th><td>6.2g</td></tr><tr><th>Salt</th><td>0.1g</td></tr></table>"
        let menu = "<ul>" + (1...2_100).map { "<li>Aisle \($0)</li>" }.joined() + "</ul>"
        switch shape {
        case .whole: return "<h1>Synthetic tofu</h1>" + panel
        case .overBoundsWithPanel: return "<h1>Synthetic tofu</h1>" + menu + panel
        case .overBoundsWithoutPanel: return "<h1>Synthetic tofu</h1>" + menu + "<p>No table here</p>"
        }
    }

    public static func violations(_ subject: Subject) async -> [String] {
        var failures: [String] = []
        func capture(_ shape: PageShape, _ permission: FoodDocumentPartReadPermission) async -> Result<CapturedFoodDocument, Error> {
            do {
                let (port, url) = try await subject(shape)
                return .success(try await port.capture(url, partRead: permission))
            } catch { return .failure(error) }
        }
        func isTooLarge(_ result: Result<CapturedFoodDocument, Error>) -> Bool {
            if case let .failure(error) = result { return error as? FoodSourceAcquisitionError == .responseTooLarge }
            return false
        }
        // 1. A whole page is the same document under both values, with no part-read record.
        switch (await capture(.whole, .refused), await capture(.whole, .permitted)) {
        case let (.success(refused), .success(permitted)):
            if refused != permitted { failures.append("whole: the two permissions gave different documents") }
            if refused.partialRead != nil || refused.hasSelectedLocator { failures.append("whole: the document is marked part-read") }
        default: failures.append("whole: a capture failed")
        }
        // 2. Over the bounds without permission: refused.
        if !isTooLarge(await capture(.overBoundsWithPanel, .refused)) {
            failures.append("overBoundsWithPanel/refused: not refused with responseTooLarge")
        }
        // 3. Over the bounds with permission: a valid part-read document.
        switch await capture(.overBoundsWithPanel, .permitted) {
        case let .success(document):
            if (try? document.validate()) == nil { failures.append("overBoundsWithPanel/permitted: the document does not validate") }
            if document.partialRead?.policy != FoodDocumentPartialRead.selectionPolicy {
                failures.append("overBoundsWithPanel/permitted: no part-read record")
            }
            let suffix = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
            if !document.blocks.allSatisfy({ $0.locator.hasSuffix(suffix) }) {
                failures.append("overBoundsWithPanel/permitted: a locator lacks the selected version")
            }
        case .failure: failures.append("overBoundsWithPanel/permitted: the capture failed")
        }
        // 4. Over the bounds with no panel: refused under both values.
        for permission in [FoodDocumentPartReadPermission.refused, .permitted]
        where !isTooLarge(await capture(.overBoundsWithoutPanel, permission)) {
            failures.append("overBoundsWithoutPanel/\(permission): not refused with responseTooLarge")
        }
        return failures
    }

    /// A valid part-read document for fakes that script `overBoundsWithPanel`: the given whole-page
    /// blocks with selected-version locators and a record whose full counts pass the bounds.
    public static func partReadDocument(id: String, url: URL, blocks: [FoodDocumentBlock]) throws -> CapturedFoodDocument {
        let suffix = ";projection:" + FoodDocumentPartialRead.selectedProjectionVersion
        let kept = blocks.map { FoodDocumentBlock(id: $0.id, kind: $0.kind, text: $0.text, locator: $0.locator + suffix) }
        let characters = kept.reduce(0) { $0 + $1.text.count }
        return try CapturedFoodDocument(id: id, url: url.absoluteString, rawSha256: String(repeating: "b", count: 64),
            captureOrigin: "synthetic_fixture", retrievedAt: "2026-11-18T00:00:00Z", blocks: kept,
            partialRead: FoodDocumentPartialRead(fullBlocks: FoodDocumentPartialRead.selectionPolicyBounds.blocks + 100,
                fullCharacters: characters + 5_000, keptBlocks: kept.count, keptCharacters: characters))
    }
}
