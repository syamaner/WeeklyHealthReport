import Foundation
import FoodLedgerDomain

/// An independently acquired table projection. A model response must never supply this document.
public struct FoodSourceTableDocument: Decodable, Equatable, Sendable {
    public struct Cell: Decodable, Equatable, Sendable {
        public let rowspan: Int
        public let colspan: Int
        public let segments: [String]
    }
    public struct Row: Decodable, Equatable, Sendable { public let cells: [Cell] }
    public struct Table: Decodable, Equatable, Sendable {
        public let id: Int
        public let rows: [Row]
        public let captions: [String]
        private enum CodingKeys: String, CodingKey { case id, rows, captions }
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            rows = try values.decode([Row].self, forKey: .rows)
            captions = try values.decodeIfPresent([String].self, forKey: .captions) ?? []
        }
    }
    public let version: String
    public let tables: [Table]
}

/// One-based source coordinates, retaining the source's paired cell segments.
public struct FoodSourceCell: Codable, Equatable, Sendable {
    public let table: Int
    public let row: Int
    public let cell: Int
    public let segment: Int
    public init(table: Int, row: Int, cell: Int, segment: Int) {
        self.table = table; self.row = row; self.cell = cell; self.segment = segment
    }
}

/// Explicit v2 evidence locations; captions never masquerade as invented table cells.
public enum FoodSourceBasisLocation: Codable, Equatable, Sendable {
    case cell(FoodSourceCell)
    case caption(table: Int, index: Int)
    case inline(FoodSourceCell)
}

/// The acquisition adapter owns the hash and selected record, independently of extraction claims.
public struct SelectedFoodSourceDocument: Equatable, Sendable {
    public let documentID: String
    public let recordID: String
    public let sha256: String
    public let document: FoodSourceTableDocument
    public let basisLocation: FoodSourceBasisLocation
    /// Compatibility accessor for the original two-cell header layout only.
    public var basisCell: FoodSourceCell? {
        if case let .cell(cell) = basisLocation { return cell }; return nil
    }

    public init(documentID: String, recordID: String, sha256: String,
                document: FoodSourceTableDocument, basisCell: FoodSourceCell) throws {
        try self.init(documentID: documentID, recordID: recordID, sha256: sha256, document: document, basisLocation: .cell(basisCell))
    }

    public init(documentID: String, recordID: String, sha256: String,
                document: FoodSourceTableDocument, basisLocation: FoodSourceBasisLocation) throws {
        guard !documentID.isEmpty, !recordID.isEmpty,
              sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              document.version == "table-preserving-source-v7", document.tables.count <= 32,
              document.tables.allSatisfy({ $0.captions.count <= 32 && $0.rows.count <= 256 && $0.rows.allSatisfy {
                  $0.cells.count <= 32 && $0.cells.allSatisfy { $0.segments.count <= 64 }
              } }) else { throw FoodSourceBindingError.invalidDocument }
        self.documentID = documentID; self.recordID = recordID; self.sha256 = sha256
        self.document = document; self.basisLocation = basisLocation
    }
}

/// Untrusted extraction proposal; it has no authority until the binder checks it.
public struct FoodSourceNutrientClaim: Codable, Equatable, Sendable {
    public let documentID: String
    public let recordID: String
    public let sha256: String
    public let field: NutrientKey
    public let amount: Double
    public let unit: String
    public let basis: ResolutionBasis
    public let declaredLiteral: String
    public let sourceCell: FoodSourceCell
    public init(documentID: String, recordID: String, sha256: String, field: NutrientKey,
                amount: Double, unit: String, basis: ResolutionBasis, declaredLiteral: String,
                sourceCell: FoodSourceCell) {
        self.documentID = documentID; self.recordID = recordID; self.sha256 = sha256
        self.field = field; self.amount = amount; self.unit = unit; self.basis = basis
        self.declaredLiteral = declaredLiteral; self.sourceCell = sourceCell
    }
}

/// Correspondence to captured content only, not verified food identity or permission to save.
public struct BoundFoodSourceNutrient: Equatable, Sendable {
    public let field: NutrientKey
    public let value: SourceExactNutrientValue
    public let declaredLiteral: String
    public let documentID: String
    public let recordID: String
    public let sha256: String
    public let sourceCell: FoodSourceCell
    public let basisLocation: FoodSourceBasisLocation
    /// Compatibility accessor for the original two-cell header layout only.
    public var basisCell: FoodSourceCell? {
        if case let .cell(cell) = basisLocation { return cell }; return nil
    }
    public let bindingVersion: String
    fileprivate init(claim: FoodSourceNutrientClaim, value: SourceExactNutrientValue, basisCell: FoodSourceCell) {
        self.init(claim: claim, value: value, basisLocation: .cell(basisCell), version: FoodSourceNutritionBinding.version)
    }
    fileprivate init(claim: FoodSourceNutrientClaim, value: SourceExactNutrientValue, basisLocation: FoodSourceBasisLocation, version: String) {
        self.bindingVersion = version
        self.field = claim.field; self.value = value; self.declaredLiteral = claim.declaredLiteral
        self.documentID = claim.documentID; self.recordID = claim.recordID; self.sha256 = claim.sha256
        self.sourceCell = claim.sourceCell; self.basisLocation = basisLocation
    }
}

public enum FoodSourceBindingError: Error, Equatable, Sendable {
    case invalidDocument, sourceMismatch, duplicateClaim, invalidCell, unsupportedLayout
    case unsupportedField, wrongPanel, sectionBoundary, basisMismatch, declarationMismatch
}

/// Closed v1: direct four-macro declarations in an explicit per-100 mass/volume panel.
/// No serving conversion, density, inferred preparation, salt conversion or candidate construction.
public enum FoodSourceNutritionBinding {
    public static let version = "food-source-nutrition-binding-v1"
    private static let number = #"([0-9]+(?:\.[0-9]+)?)"#
    private static let labels: Set<String> = ["energy", "fat", "saturates", "carbohydrate", "sugars", "fibre", "protein", "salt"]

    public static func bind(_ claims: [FoodSourceNutrientClaim], to source: SelectedFoodSourceDocument) throws -> [BoundFoodSourceNutrient] {
        guard claims.count <= 4, Set(claims.map(\.field)).count == claims.count else { throw FoodSourceBindingError.duplicateClaim }
        return try claims.map { try bind($0, source: source) }
    }

    public static let panelReadingVersion = "food-source-panel-reading-v1"

    /// Read one source section directly. Missing declarations stay absent; later panels cannot fill them.
    public static func readAvailableMacros(from source: SelectedFoodSourceDocument) throws -> [BoundFoodSourceNutrient] {
        let basis = try panelBasis(source)
        guard let pointer = source.basisCell else { throw FoodSourceBindingError.wrongPanel }
        guard pointer.table > 0, pointer.table <= source.document.tables.count else { throw FoodSourceBindingError.invalidCell }
        let rows = source.document.tables[pointer.table - 1].rows
        guard pointer.row < rows.count else { return [] }
        var seen = Set<String>()
        var claims: [FoodSourceNutrientClaim] = []
        section: for row in (pointer.row + 1)...rows.count {
            let values: [(String, String)]
            do { values = try pairs(source.document, table: pointer.table, row: row) }
            catch { break section }
            // Validate the complete paired row before admitting any of its segments.
            var nextSeen = seen
            for (label, text) in values {
                guard labels.contains(label), nextSeen.insert(label).inserted,
                      literal(text, energy: label == "energy") != nil else { break section }
            }
            seen = nextSeen
            for (index, pair) in values.enumerated() {
                let field: NutrientKey
                switch pair.0 {
                case "energy": field = .energyConsumed
                case "protein": field = .protein
                case "carbohydrate": field = .carbohydrates
                case "fat": field = .fatTotal
                default: continue
                }
                guard let declared = literal(pair.1, energy: field == .energyConsumed), let amount = Double(declared) else { break section }
                claims.append(.init(documentID: source.documentID, recordID: source.recordID, sha256: source.sha256,
                    field: field, amount: amount, unit: field == .energyConsumed ? "kcal" : "g", basis: basis,
                    declaredLiteral: declared, sourceCell: .init(table: pointer.table, row: row, cell: 2, segment: index + 1)))
            }
        }
        return try bind(claims, to: source)
    }

    private static func panelBasis(_ source: SelectedFoodSourceDocument) throws -> ResolutionBasis {
        guard let pointer = source.basisCell else { throw FoodSourceBindingError.wrongPanel }
        guard pointer.cell == 2, pointer.segment == 1 else { throw FoodSourceBindingError.wrongPanel }
        let values = try pairs(source.document, table: pointer.table, row: pointer.row)
        guard values.count == 1, ["typical values", "nutrition", "nutritional values"].contains(values[0].0),
              let match = captures(#"per "# + number + #"\s*(g|ml)"#, values[0].1.lowercased()),
              Decimal(string: match[0], locale: Locale(identifier: "en_US_POSIX")) == 100 else { throw FoodSourceBindingError.basisMismatch }
        return match[1] == "g" ? .per100Grams : .per100Millilitres
    }

    private static func bind(_ claim: FoodSourceNutrientClaim, source: SelectedFoodSourceDocument) throws -> BoundFoodSourceNutrient {
        guard claim.documentID == source.documentID, claim.recordID == source.recordID,
              claim.sha256 == source.sha256 else { throw FoodSourceBindingError.sourceMismatch }
        let label: String
        let unit: String
        switch claim.field {
        case .energyConsumed: label = "energy"; unit = "kcal"
        case .protein: label = "protein"; unit = "g"
        case .carbohydrates: label = "carbohydrate"; unit = "g"
        case .fatTotal: label = "fat"; unit = "g"
        default: throw FoodSourceBindingError.unsupportedField
        }
        let pointer = claim.sourceCell
        guard let basisPointer = source.basisCell else { throw FoodSourceBindingError.wrongPanel }
        guard pointer.table == basisPointer.table, pointer.cell == 2, basisPointer.cell == 2,
              basisPointer.segment == 1, pointer.row > basisPointer.row else { throw FoodSourceBindingError.wrongPanel }
        let basis = try panelBasis(source)
        guard basis == claim.basis else { throw FoodSourceBindingError.basisMismatch }
        var seen = Set<String>()
        // Do not carry a denominator across a heading, repeated nutrient or another panel.
        for row in (basisPointer.row + 1)...pointer.row {
            for (sectionLabel, value) in try pairs(source.document, table: pointer.table, row: row) {
                guard labels.contains(sectionLabel), seen.insert(sectionLabel).inserted,
                      literal(value, energy: sectionLabel == "energy") != nil else { throw FoodSourceBindingError.sectionBoundary }
            }
        }
        let targetPairs = try pairs(source.document, table: pointer.table, row: pointer.row)
        guard pointer.segment > 0, pointer.segment <= targetPairs.count else { throw FoodSourceBindingError.invalidCell }
        let target = targetPairs[pointer.segment - 1]
        guard target.0 == label, claim.unit == unit,
              let declared = literal(target.1, energy: label == "energy"), declared == claim.declaredLiteral,
              claim.amount.isFinite, claim.amount >= 0,
              Decimal(string: declared, locale: Locale(identifier: "en_US_POSIX")) == Decimal(string: String(claim.amount), locale: Locale(identifier: "en_US_POSIX")) else { throw FoodSourceBindingError.declarationMismatch }
        let value = try SourceExactNutrientValue(amount: claim.amount, unit: LedgerText(unit), basis: basis)
        return BoundFoodSourceNutrient(claim: claim, value: value, basisCell: basisPointer)
    }

    private static func pairs(_ document: FoodSourceTableDocument, table: Int, row: Int) throws -> [(String, String)] {
        guard table > 0, table <= document.tables.count else { throw FoodSourceBindingError.invalidCell }
        let selected = document.tables[table - 1]
        guard selected.id == table, row > 0, row <= selected.rows.count else { throw FoodSourceBindingError.invalidCell }
        let cells = selected.rows[row - 1].cells
        guard cells.count == 2, cells.allSatisfy({ $0.rowspan == 1 && $0.colspan == 1 }),
              !cells[0].segments.isEmpty, cells[0].segments.count == cells[1].segments.count else { throw FoodSourceBindingError.unsupportedLayout }
        return zip(cells[0].segments, cells[1].segments).map {
            ($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $1.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func literal(_ text: String, energy: Bool) -> String? {
        if energy, let combined = captures(number + #"\s*kJ\s*/\s*"# + number + #"\s*kcal"#, text) { return combined[1] }
        return captures(number + (energy ? #"\s*kcal"# : #"\s*g"#), text)?.first
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range == NSRange(text.startIndex..., in: text) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

/// One complete source section, which may contain only a partial macro profile.
/// Consumers must retain separate panels rather than merge missing fields across them.
public struct FoodSourceNutritionPanel: Equatable, Sendable {
    public let source: SelectedFoodSourceDocument
    public let declarations: [BoundFoodSourceNutrient]
    public var hasFourMacros: Bool { declarations.count == 4 }
    public init(source: SelectedFoodSourceDocument, declarations: [BoundFoodSourceNutrient]) throws {
        guard !declarations.isEmpty, declarations.count <= 4,
              Set(declarations.map(\.field)).count == declarations.count,
              declarations.allSatisfy({ $0.documentID == source.documentID && $0.recordID == source.recordID
                  && $0.sha256 == source.sha256 && Self.samePanel($0, source: source)
                  && $0.value.basis == declarations.first?.value.basis }) else { throw FoodSourceBindingError.sourceMismatch }
        self.source = source; self.declarations = declarations
    }
    private static func samePanel(_ value: BoundFoodSourceNutrient, source: SelectedFoodSourceDocument) -> Bool {
        if case let .inline(anchor) = source.basisLocation, case let .inline(basis) = value.basisLocation {
            return basis == value.sourceCell && basis.table == anchor.table && basis.row >= anchor.row
                && basis.cell == 1 && basis.segment == 2 && value.bindingVersion == FoodSourceExplicitBasisBinding.version
        }
        return value.basisLocation == source.basisLocation
    }
}

/// Closed v2 reader for a single explicit caption or repeated in-cell denominators.
/// Keeps v1 header reading separate; neither layout establishes product identity.
public enum FoodSourceExplicitBasisBinding {
    public static let version = "food-source-explicit-basis-binding-v2"
    private static let number = #"([0-9]+(?:\.[0-9]+)?)"#
    private static let aliases = ["energy": "energy", "fat": "fat", "carbohydrate": "carbohydrate",
        "carbohydrates": "carbohydrate", "protein": "protein", "saturates": "saturates",
        "of which saturates": "saturates", "of which is saturated": "saturates",
        "sugars": "sugars", "of which sugars": "sugars", "of which is sugars": "sugars",
        "fibre": "fibre", "salt": "salt"]

    public static func readAvailableMacros(from source: SelectedFoodSourceDocument) throws -> [BoundFoodSourceNutrient] {
        let tableID: Int
        let captionBasis: ResolutionBasis?
        switch source.basisLocation {
        case let .caption(table, index):
            tableID = table
            guard table > 0, table <= source.document.tables.count, index == 1 else { throw FoodSourceBindingError.invalidCell }
            let captions = source.document.tables[table - 1].captions
            guard captions.count == 1,
                  let match = captures(#"(?:nutrition information|nutritional information|nutrition|typical values) per "# + number + #"\s*(g|ml)[:,]?[,]?"#, clean(captions[0])),
                  let basis = basis(match[0], match[1]) else { throw FoodSourceBindingError.basisMismatch }
            captionBasis = basis
        case let .inline(anchor):
            guard anchor.row == 1, anchor.cell == 1, anchor.segment == 2 else { throw FoodSourceBindingError.wrongPanel }
            tableID = anchor.table; captionBasis = nil
        case .cell: throw FoodSourceBindingError.wrongPanel
        }
        guard tableID > 0, tableID <= source.document.tables.count else { throw FoodSourceBindingError.invalidCell }
        let table = source.document.tables[tableID - 1]
        guard table.id == tableID else { throw FoodSourceBindingError.invalidDocument }
        if captionBasis == nil, !table.captions.isEmpty { throw FoodSourceBindingError.basisMismatch }
        // A competing explicit header makes the whole new layout ambiguous, even after four values.
        guard !table.rows.contains(where: { row in
            row.cells.first?.segments.first.map { ["typical values", "nutrition", "nutritional values"].contains(clean($0)) } == true
        }) else { throw FoodSourceBindingError.wrongPanel }
        var seen = Set<String>()
        var commonBasis = captionBasis
        var result: [BoundFoodSourceNutrient] = []
        for (rowIndex, row) in table.rows.enumerated() {
            try Task.checkCancellation()
            let labelText: String, declaration: String, rowBasis: ResolutionBasis
            let valueCell: FoodSourceCell, location: FoodSourceBasisLocation
            guard row.cells.allSatisfy({ $0.rowspan == 1 && $0.colspan == 1 }) else { throw FoodSourceBindingError.unsupportedLayout }
            if let captionBasis {
                guard row.cells.count == 2, row.cells.allSatisfy({ $0.segments.count == 1 }) else { throw FoodSourceBindingError.unsupportedLayout }
                labelText = clean(row.cells[0].segments[0])
                declaration = row.cells[1].segments[0].trimmingCharacters(in: .whitespacesAndNewlines)
                rowBasis = captionBasis
                valueCell = .init(table: tableID, row: rowIndex + 1, cell: 2, segment: 1)
                location = source.basisLocation
            } else {
                guard row.cells.count == 1, row.cells[0].segments.count == 2 else { throw FoodSourceBindingError.unsupportedLayout }
                labelText = clean(row.cells[0].segments[0])
                let text = row.cells[0].segments[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let match = captures(#"per "# + number + #"\s*([gG]|[mM][lL])\s+(.+)"#, text),
                      let basis = basis(match[0], match[1].lowercased()) else { throw FoodSourceBindingError.basisMismatch }
                declaration = match[2]; rowBasis = basis
                valueCell = .init(table: tableID, row: rowIndex + 1, cell: 1, segment: 2)
                location = .inline(valueCell)
            }
            guard let label = aliases[labelText] else { break }
            guard seen.insert(label).inserted else { throw FoodSourceBindingError.sectionBoundary }
            if let commonBasis, commonBasis != rowBasis { throw FoodSourceBindingError.basisMismatch }
            commonBasis = rowBasis
            guard let declared = literal(declaration, energy: label == "energy"), let amount = Double(declared), amount.isFinite,
                  Decimal(string: declared, locale: Locale(identifier: "en_US_POSIX")) == Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")) else {
                throw FoodSourceBindingError.declarationMismatch
            }
            let field: NutrientKey
            switch label {
            case "energy": field = .energyConsumed
            case "fat": field = .fatTotal
            case "carbohydrate": field = .carbohydrates
            case "protein": field = .protein
            default: continue
            }
            let unit = field == .energyConsumed ? "kcal" : "g"
            let claim = FoodSourceNutrientClaim(documentID: source.documentID, recordID: source.recordID, sha256: source.sha256,
                field: field, amount: amount, unit: unit, basis: rowBasis, declaredLiteral: declared, sourceCell: valueCell)
            let exact = try SourceExactNutrientValue(amount: amount, unit: LedgerText(unit), basis: rowBasis)
            result.append(BoundFoodSourceNutrient(claim: claim, value: exact, basisLocation: location, version: version))
        }
        return result
    }

    /// Untrusted claims must match the independently read literal and its actual evidence location.
    public static func bind(_ claims: [FoodSourceNutrientClaim], to source: SelectedFoodSourceDocument) throws -> [BoundFoodSourceNutrient] {
        guard claims.count <= 4, Set(claims.map(\.field)).count == claims.count else { throw FoodSourceBindingError.duplicateClaim }
        let available = try readAvailableMacros(from: source)
        return try claims.map { claim in
            guard claim.documentID == source.documentID, claim.recordID == source.recordID, claim.sha256 == source.sha256 else { throw FoodSourceBindingError.sourceMismatch }
            guard let found = available.first(where: { $0.field == claim.field }), found.sourceCell == claim.sourceCell,
                  found.declaredLiteral == claim.declaredLiteral, found.value.amount == claim.amount,
                  found.value.unit.value == claim.unit, found.value.basis == claim.basis else { throw FoodSourceBindingError.declarationMismatch }
            return found
        }
    }

    private static func basis(_ amount: String, _ unit: String) -> ResolutionBasis? {
        guard Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) == 100 else { return nil }
        return unit == "g" ? .per100Grams : .per100Millilitres
    }
    private static func clean(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
    private static func literal(_ value: String, energy: Bool) -> String? {
        if energy, let match = captures(number + #"\s*kJ\s*/\s*"# + number + #"\s*kcal"#, value) { return match[1] }
        return captures(number + (energy ? #"\s*kcal"# : #"\s*g"#), value)?.first
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range == NSRange(text.startIndex..., in: text) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
