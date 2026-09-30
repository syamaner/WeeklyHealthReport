import Foundation
import FoodLedgerApplication

/// Enumerates explicit source panels without a model choosing a denominator or synthesising values.
public enum FoodSourceDocumentPanelReader {
    public static let version = "food-source-document-panels-v2"
    public static func panels(_ projection: Data, documentID: String, recordID: String) throws -> [FoodSourceNutritionPanel] {
        try Task.checkCancellation()
        let snapshot = try FoodSourceDocumentDecoder.decode(projection, documentID: documentID, recordID: recordID,
            basisCell: .init(table: 1, row: 1, cell: 2, segment: 1))
        var panels: [FoodSourceNutritionPanel] = []
        for (tableIndex, table) in snapshot.document.tables.enumerated() {
            try Task.checkCancellation()
            guard table.id == tableIndex + 1 else { throw FoodSourceBindingError.invalidDocument }
            // Captions are explicit evidence, not synthetic header cells. Competing layouts fail closed.
            let location: FoodSourceBasisLocation?
            if !table.captions.isEmpty { location = .caption(table: table.id, index: 1) }
            else if table.rows.first?.cells.count == 1 { location = .inline(.init(table: table.id, row: 1, cell: 1, segment: 2)) }
            else { location = nil }
            if let location {
                let source = try SelectedFoodSourceDocument(documentID: documentID, recordID: recordID,
                    sha256: snapshot.sha256, document: snapshot.document, basisLocation: location)
                if let values = try? FoodSourceExplicitBasisBinding.readAvailableMacros(from: source), !values.isEmpty {
                    panels.append(try FoodSourceNutritionPanel(source: source, declarations: values))
                    guard panels.count <= 32 else { throw FoodSourceBindingError.unsupportedLayout }
                }
                try Task.checkCancellation()
                continue
            }
            for (rowIndex, row) in table.rows.enumerated() {
                try Task.checkCancellation()
                guard row.cells.count == 2, row.cells[0].segments.count == 1,
                      ["typical values", "nutrition", "nutritional values"].contains(
                        row.cells[0].segments[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else { continue }
                let source = try SelectedFoodSourceDocument(documentID: documentID, recordID: recordID,
                    sha256: snapshot.sha256, document: snapshot.document,
                    basisCell: .init(table: table.id, row: rowIndex + 1, cell: 2, segment: 1))
                guard let values = try? FoodSourceNutritionBinding.readAvailableMacros(from: source), !values.isEmpty else { continue }
                panels.append(try FoodSourceNutritionPanel(source: source, declarations: values))
                guard panels.count <= 32 else { throw FoodSourceBindingError.unsupportedLayout }
            }
        }
        try Task.checkCancellation()
        return panels
    }
}
