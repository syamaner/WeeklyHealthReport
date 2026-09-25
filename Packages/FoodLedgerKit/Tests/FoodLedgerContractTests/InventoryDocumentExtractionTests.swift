import Foundation
import FoodLedgerApplication
import FoodInventoryImport
import XCTest

final class InventoryDocumentExtractionTests: XCTestCase {
    func testTextRetainsExactBytesAndRejectsUnreadableInput() throws {
        let extractor: any InventoryDocumentExtracting = LocalInventoryDocumentExtractor()
        let bytes = Data("\u{feff}Sample oats 500 grams £2.00\r\n".utf8)
        let result = try extractor.extract(bytes, format: .text)
        XCTAssertEqual(result.originalBytes, bytes)
        XCTAssertEqual(result.text, "Sample oats 500 grams £2.00\r\n")
        XCTAssertThrowsError(try extractor.extract(Data([0xff, 0xfe, 0xff]), format: .text))
        XCTAssertThrowsError(try extractor.extract(Data(" \n".utf8), format: .text))
        XCTAssertThrowsError(try extractor.extract(Data(repeating: 65, count: 5_000_001), format: .text))
    }

    func testPDFTextAndImageOnlyRejection() throws {
        let extractor: any InventoryDocumentExtracting = LocalInventoryDocumentExtractor()
        let textPDF = pdf(content: "BT /F1 12 Tf 20 100 Td (Sample oats 500 g) Tj ET")
        let result = try extractor.extract(textPDF, format: .pdf)
        XCTAssertEqual(result.originalBytes, textPDF)
        XCTAssertTrue(result.text.contains("Sample oats 500 g"))
        XCTAssertThrowsError(try extractor.extract(pdf(content: ""), format: .pdf))
        XCTAssertThrowsError(try extractor.extract(Data("not a PDF".utf8), format: .pdf))
    }

    /// A tiny invented one-page PDF with deterministic xref offsets, no external assets.
    private func pdf(content: String) -> Data {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
        ]
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = text.utf8.count
        text += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(text.utf8)
    }
}
