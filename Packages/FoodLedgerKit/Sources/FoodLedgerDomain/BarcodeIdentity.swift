import Foundation

public enum BarcodeSymbology: String, Codable, CaseIterable, Sendable {
    case ean8 = "ean-8"
    case ean13 = "ean-13"
    case upce = "upc-e"
    case code128 = "code-128"
    case dataMatrix = "data-matrix"
    case qr
    case unknown
}

public enum BarcodeIdentity: Codable, Equatable, Sendable {
    case gtin(LedgerText)
    case local(namespace: LedgerText, code: LedgerText)

    public var lookupAlias: LedgerText {
        get throws {
            switch self {
            case let .gtin(value):
                return try LedgerText("barcode:gtin:\(value.value)")
            case let .local(namespace, code):
                return try LedgerText(
                    "barcode:local:\(namespace.value.lowercased()):\(code.value)"
                )
            }
        }
    }
}

public enum BarcodeClassificationError: Error, Equatable, Sendable {
    case unsupportedSymbology
    case invalidGTINLength
    case invalidGTINCharacters
    case invalidGTINCheckDigit
    case missingLocalNamespace
}

public enum BarcodeClassifier {
    public static func classify(
        code: LedgerText,
        symbology: BarcodeSymbology,
        localNamespace: LedgerText? = nil
    ) throws -> BarcodeIdentity {
        if let localNamespace {
            return .local(namespace: localNamespace, code: code)
        }

        let canonicalCode: LedgerText
        switch symbology {
        case .ean8:
            canonicalCode = try canonicalGTIN(code, expectedLength: 8)
        case .ean13:
            canonicalCode = try canonicalGTIN(code, expectedLength: 13)
        case .upce:
            canonicalCode = try LedgerText(expandUPCE(code.value).leftPadded(to: 14, with: "0"))
        case .code128, .dataMatrix, .qr:
            throw BarcodeClassificationError.missingLocalNamespace
        case .unknown:
            throw BarcodeClassificationError.unsupportedSymbology
        }
        return .gtin(canonicalCode)
    }

    private static func canonicalGTIN(
        _ code: LedgerText,
        expectedLength: Int
    ) throws -> LedgerText {
        guard code.value.count == expectedLength else {
            throw BarcodeClassificationError.invalidGTINLength
        }
        guard code.value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            throw BarcodeClassificationError.invalidGTINCharacters
        }
        guard hasValidGTINCheckDigit(code.value) else {
            throw BarcodeClassificationError.invalidGTINCheckDigit
        }
        return try LedgerText(code.value.leftPadded(to: 14, with: "0"))
    }

    private static func expandUPCE(_ value: String) throws -> String {
        guard value.count == 8 else { throw BarcodeClassificationError.invalidGTINLength }
        guard value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            throw BarcodeClassificationError.invalidGTINCharacters
        }
        let digits = Array(value)
        let numberSystem = digits[0]
        guard numberSystem == "0" || numberSystem == "1" else {
            throw BarcodeClassificationError.invalidGTINCheckDigit
        }
        let body: String
        switch digits[6] {
        case "0", "1", "2":
            body = "\(numberSystem)\(digits[1])\(digits[2])\(digits[6])0000\(digits[3])\(digits[4])\(digits[5])"
        case "3":
            body = "\(numberSystem)\(digits[1])\(digits[2])\(digits[3])00000\(digits[4])\(digits[5])"
        case "4":
            body = "\(numberSystem)\(digits[1])\(digits[2])\(digits[3])\(digits[4])00000\(digits[5])"
        default:
            body = "\(numberSystem)\(digits[1])\(digits[2])\(digits[3])\(digits[4])\(digits[5])0000\(digits[6])"
        }
        let expanded = body + String(digits[7])
        guard hasValidGTINCheckDigit(expanded) else {
            throw BarcodeClassificationError.invalidGTINCheckDigit
        }
        return expanded
    }

    private static func hasValidGTINCheckDigit(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == value.count, let checkDigit = digits.last else { return false }
        let body = digits.dropLast().reversed()
        let sum = body.enumerated().reduce(0) { partial, item in
            partial + item.element * (item.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - (sum % 10)) % 10 == checkDigit
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        String(repeating: String(character), count: max(0, length - count)) + self
    }
}

public struct BarcodeLibraryRecord: Codable, Equatable, Sendable {
    public let libraryEntryVersion: LibraryEntryVersion
    public let productVersion: ProductVersion
    public let resolution: NutritionResolution
    public let resolutionVersion: NutritionResolutionVersion
    public let sourceReleases: [SourceRelease]

    public init(
        libraryEntryVersion: LibraryEntryVersion,
        productVersion: ProductVersion,
        resolution: NutritionResolution,
        resolutionVersion: NutritionResolutionVersion,
        sourceReleases: [SourceRelease]
    ) throws {
        guard libraryEntryVersion.productVersionID == productVersion.productVersionID,
              resolution.productVersionID == productVersion.productVersionID,
              resolutionVersion.resolutionID == resolution.resolutionID,
              Set(resolutionVersion.sourceReleaseIDs) == Set(sourceReleases.map(\.sourceReleaseID))
        else {
            throw FoodLedgerValidationError.missingProvenance
        }
        self.libraryEntryVersion = libraryEntryVersion
        self.productVersion = productVersion
        self.resolution = resolution
        self.resolutionVersion = resolutionVersion
        self.sourceReleases = sourceReleases
    }
}
