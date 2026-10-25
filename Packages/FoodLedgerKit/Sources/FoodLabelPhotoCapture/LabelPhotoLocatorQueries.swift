import FoodLabelPhotoReading
import FoodLedgerApplication
import Foundation

/// What the Vision locator asks the pinned matcher and what it records (docs/label-photo-ai-prefill-v1.md
/// 6.1, 8.1 and 17.15). Pure: the candidate in, the matcher's queries and inputs out; the matcher's
/// results in, the manifest's location records out.
enum LabelPhotoLocatorQueries {
    struct Inputs: Equatable {
        let queries: [LabelValueMatcher.Query]
        let headers: [String]
        let headerBases: [LabelValueMatcher.HeaderBasis]
        let rowLabels: [String]
        let columnCount: Int
    }

    /// One query per cell (`<row_id>@<header_id>`) and per printed serving line, with every header
    /// of the reading (an empty text when none is printed) and its basis (17.15).
    static func inputs(_ candidate: PastedLabelManifest.Candidate) -> Inputs {
        let headerText = Dictionary(candidate.headers.map { ($0.headerID, $0.printedText) }, uniquingKeysWith: { first, _ in first })
        var queries = candidate.cells.map { cell in
            LabelValueMatcher.Query(id: LabelPhotoManifest.cellItem(rowID: cell.rowID, headerID: cell.headerID), rowLabel: cell.printedLabel,
                                    headerText: headerText[cell.headerID].flatMap { $0.isEmpty ? nil : $0 }, printedText: cell.printedText)
        }
        if let size = candidate.servingSize {
            queries.append(.init(id: PastedLabelManifest.Correction.servingSize, rowLabel: nil, headerText: nil, printedText: size.printedText))
        }
        if let pack = candidate.servingsPerPack {
            queries.append(.init(id: PastedLabelManifest.Correction.servingsPerPack, rowLabel: nil, headerText: nil, printedText: pack.printedText))
        }
        return Inputs(queries: queries, headers: candidate.headers.map(\.printedText),
                      headerBases: candidate.headers.map { $0.basis == "reference_intake" ? .referenceIntake : .amount },
                      rowLabels: Array(Set(candidate.cells.map(\.printedLabel))).sorted(), columnCount: candidate.headers.count)
    }

    /// The manifest's records: one per query, in query order; a region (decimal text, four places,
    /// Vision's normalised coordinates with the origin bottom left) only on a found value.
    static func records(_ queries: [LabelValueMatcher.Query], located: [LabelValueMatcher.Location]) -> [LabelPhotoManifest.Location] {
        let byID = Dictionary(located.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return queries.map { query in
            guard let location = byID[query.id] else { return .init(item: query.id, status: .notFound, region: nil) }
            switch location.status {
            case .found:
                // A found value whose region cannot be recorded inside the unit square is recorded
                // ambiguous (shown as "Not found on the photo"), never found without its region.
                guard let box = location.region, case let recorded = region(box), recorded.isInsideUnitSquare else {
                    return .init(item: query.id, status: .ambiguous, region: nil)
                }
                return .init(item: query.id, status: .found, region: recorded)
            case .ambiguous: return .init(item: query.id, status: .ambiguous, region: nil)
            case .notFound: return .init(item: query.id, status: .notFound, region: nil)
            }
        }
    }

    /// Decimal text with at most four places, clamped inside the unit square.
    static func region(_ box: LabelValueMatcher.Box) -> LabelPhotoManifest.Region {
        func text(_ value: Double) -> String {
            let clamped = min(max(value, 0), 1)
            var out = String(format: "%.4f", clamped)
            while out.contains("."), out.hasSuffix("0") { out.removeLast() }
            if out.hasSuffix(".") { out.removeLast() }
            return out
        }
        let x = min(max(box.x, 0), 1), y = min(max(box.y, 0), 1)
        let w = min(max(box.width, 0.0001), 1 - x), h = min(max(box.height, 0.0001), 1 - y)
        return .init(x: text(x), y: text(y), w: text(w), h: text(h))
    }
}
