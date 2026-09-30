import CryptoKit
import Foundation
import FoodLedgerApplication

/// Decodes independently acquired projection bytes, never Gemini-generated document content.
/// HTTP/page projection and product selection are separate capabilities; this does not fetch URLs.
public enum FoodSourceDocumentDecoder {
    public static let maximumBytes = FoodSourceContentLimits.projectionBytes
    public static func decode(_ data: Data, documentID: String, recordID: String,
                              basisCell: FoodSourceCell) throws -> SelectedFoodSourceDocument {
        guard !data.isEmpty, data.count <= maximumBytes else { throw FoodSourceBindingError.invalidDocument }
        let document: FoodSourceTableDocument
        do { document = try JSONDecoder().decode(FoodSourceTableDocument.self, from: data) }
        catch { throw FoodSourceBindingError.invalidDocument }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try SelectedFoodSourceDocument(documentID: documentID, recordID: recordID,
            sha256: digest, document: document, basisCell: basisCell)
    }
}
