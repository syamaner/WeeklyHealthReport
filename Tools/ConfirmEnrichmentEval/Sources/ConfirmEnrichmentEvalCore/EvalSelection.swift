import FoodLedgerDomain
import Foundation

/// The deterministic case selection (docs/confirm-enrichment-openrouter-v1-phase.md section 9, the
/// owner-approved case-selection paragraph of docs/privacy-and-egress.md). Pure: the pool and the seed
/// come in, the two sets come out. The same pool and seed always give the same sets.
///
/// - Open Food Facts: a development set and a sealed set of 60 products each, with no product in both,
///   at least 8 fortified in each, and an even UK / Taiwan split where the pool allows (otherwise the
///   short country is filled from the other).
/// - Bundled rows: 10 per table (CoFID, USDA, TFDA, Ciqual) in each set, with no row in both.
/// - A pool too small for either is a stop, and nothing is written.
public enum EvalSelection {
    public static let productsPerSet = 60
    public static let minimumFortifiedPerSet = 8
    public static let rowsPerTablePerSet = 10

    /// The two countries of the development and sealed sets (section 9: UK and Taiwan).
    public enum Country: String, Sendable { case unitedKingdom = "uk", taiwan }

    /// One eligible Open Food Facts product, as the export scan found it. `line` is its line number in
    /// the export, so the records can be extracted in a second streaming pass.
    public struct Product: Equatable, Sendable {
        public let code: String
        public let line: Int
        public let country: Country
        /// The fortified rule: the record's `vitamins_tags` or `minerals_tags` is not empty (Open Food
        /// Facts lists there the vitamins and minerals its ingredients analysis found added).
        public let fortified: Bool

        public init(code: String, line: Int, country: Country, fortified: Bool) {
            self.code = code; self.line = line; self.country = country; self.fortified = fortified
        }
    }

    /// One bundled table row a search text reaches.
    public struct Row: Equatable, Sendable {
        public let table: EvalCase.Table
        public let search: String
        public let recordID: String

        public init(table: EvalCase.Table, search: String, recordID: String) {
            self.table = table; self.search = search; self.recordID = recordID
        }
    }

    public struct Draw: Equatable, Sendable {
        public let development: [Product]
        public let sealed: [Product]
    }

    public struct RowDraw: Equatable, Sendable {
        public let development: [Row]
        public let sealed: [Row]
    }

    public enum Stop: Error, Equatable, CustomStringConvertible {
        case poolTooSmall, tooFewFortified, tooFewRows(EvalCase.Table)
        public var description: String {
            switch self {
            case .poolTooSmall: "pool_too_small"
            case .tooFewFortified: "pool_too_few_fortified"
            case let .tooFewRows(table): "too_few_rows_\(table.rawValue)"
            }
        }
    }

    /// A SplitMix64 generator: small, fast and fully determined by its seed.
    public struct Generator: RandomNumberGenerator, Sendable {
        private var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// One product per item: the code without leading zeros, so a UPC-12, an EAN-13 and a GTIN-14 of the
    /// same product count once and can never land in both sets.
    public static func itemKey(_ code: String) -> String {
        let trimmed = code.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    /// A Fisher-Yates shuffle over the tool's own generator, with rejection sampling for an unbiased
    /// index. Written out rather than `shuffled(using:)`, whose algorithm the standard library does not
    /// promise to keep, so a recorded seed reproduces the sets on any toolchain.
    public static func shuffle<T>(_ items: [T], generator: inout Generator) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for upper in stride(from: result.count - 1, to: 0, by: -1) {
            let bound = UInt64(upper + 1)
            let limit = UInt64.max - UInt64.max % bound
            var draw = generator.next()
            while draw >= limit { draw = generator.next() }
            result.swapAt(upper, Int(draw % bound))
        }
        return result
    }

    /// The products of both sets. The pool is put in a fixed order first (by item, one entry per item),
    /// so the draw depends only on the pool's contents and the seed, never on the export's line order.
    public static func drawProducts(_ pool: [Product], generator: inout Generator) throws -> Draw {
        var seen = Set<String>()
        let unique = pool.sorted { ($0.code, $0.line) < ($1.code, $1.line) }.filter { seen.insert(itemKey($0.code)).inserted }
        guard unique.count >= 2 * productsPerSet else { throw Stop.poolTooSmall }
        guard unique.filter(\.fortified).count >= 2 * minimumFortifiedPerSet else { throw Stop.tooFewFortified }
        var remaining = shuffle(unique, generator: &generator)
        func takeOne(into chosen: inout [Product], where predicate: (Product) -> Bool) -> Bool {
            guard let index = remaining.firstIndex(where: predicate) else { return false }
            chosen.append(remaining.remove(at: index))
            return true
        }
        // The two sets take turns, one product at a time, at every step, so neither set can use up a
        // scarce kind before the other has its share: first the fortified minimum, then each country up
        // to half the set, then any product (a short country is filled from the other).
        var development: [Product] = [], sealed: [Product] = []
        // Within a step, a set first tries the country it holds fewer of than the other set, so the
        // fortified minimum and the final fill do not tilt one set's country mix.
        func takeBalanced(into chosen: inout [Product], other: [Product], where predicate: @escaping (Product) -> Bool) -> Bool {
            for country in [Country.unitedKingdom, .taiwan]
            where chosen.filter({ $0.country == country }).count < other.filter({ $0.country == country }).count {
                if takeOne(into: &chosen, where: { predicate($0) && $0.country == country }) { return true }
            }
            return takeOne(into: &chosen, where: predicate)
        }
        // One product per turn, always to the set that holds fewer of what the step is filling (ties go
        // to the development set), so the sets stay within one product of each other at every step.
        func alternate(until full: ([Product]) -> Bool, rank: ([Product]) -> Int, where predicate: @escaping (Product) -> Bool) {
            var stuck = (development: false, sealed: false)
            while true {
                let developmentOpen = !stuck.development && !full(development)
                let sealedOpen = !stuck.sealed && !full(sealed)
                if !developmentOpen && !sealedOpen { return }
                if developmentOpen && (!sealedOpen || rank(development) <= rank(sealed)) {
                    if !takeBalanced(into: &development, other: sealed, where: predicate) { stuck.development = true }
                } else if !takeBalanced(into: &sealed, other: development, where: predicate) {
                    stuck.sealed = true
                }
            }
        }
        alternate(until: { $0.count >= minimumFortifiedPerSet }, rank: { $0.count }) { $0.fortified }
        let half = productsPerSet / 2
        for country in [Country.unitedKingdom, .taiwan] {
            let held: ([Product]) -> Int = { set in set.filter { $0.country == country }.count }
            alternate(until: { $0.count >= productsPerSet || held($0) >= half }, rank: held) { $0.country == country }
        }
        alternate(until: { $0.count >= productsPerSet }, rank: { $0.count }) { _ in true }
        return Draw(development: development, sealed: sealed)
    }

    /// The bundled rows of both sets, table by table in a fixed order, one entry per record ID.
    public static func drawRows(_ rows: [Row], generator: inout Generator) throws -> RowDraw {
        var development: [Row] = [], sealed: [Row] = []
        for table in EvalCase.Table.allCases {
            var seen = Set<String>()
            let unique = rows.filter { $0.table == table }
                .sorted { $0.recordID == $1.recordID ? $0.search < $1.search : $0.recordID < $1.recordID }
                .filter { seen.insert($0.recordID).inserted }
            guard unique.count >= 2 * rowsPerTablePerSet else { throw Stop.tooFewRows(table) }
            let shuffled = shuffle(unique, generator: &generator)
            development += shuffled.prefix(rowsPerTablePerSet)
            sealed += shuffled.dropFirst(rowsPerTablePerSet).prefix(rowsPerTablePerSet)
        }
        return RowDraw(development: development, sealed: sealed)
    }

    /// The counts printed for one set: closed names and numbers only.
    public static func counts(products: [Product], rows: [Row]) -> [(String, Int)] {
        [("open_food_facts", products.count),
         ("uk", products.filter { $0.country == .unitedKingdom }.count),
         ("taiwan", products.filter { $0.country == .taiwan }.count),
         ("fortified", products.filter(\.fortified).count)]
            + EvalCase.Table.allCases.map { table in (table.rawValue, rows.filter { $0.table == table }.count) }
    }

    /// The review sheet header (the owner's check of the development set's food details, section 9). The
    /// food detail columns list the I1.1 choices; fortification also admits `fortified`, the truth A must
    /// never pre-fill.
    public static let reviewSheetHeader = [
        "case_hash", "name", "brand", "barcode", "fortified_by_rule",
        "preparation (as_sold|raw|cooked|unknown)", "bone (with_bone|boneless|not_applicable|unknown)",
        "skin (skin_on|skinless|not_applicable|unknown)", "drained (drained|undrained|not_applicable|unknown)",
        "packing_medium (as sold|not applicable|water|brine|oil|olive_oil|sauce|unknown)",
        "fortification (unfortified|fortified|unknown)",
    ]

    public static let reviewSheetNote = "# fortified_by_rule: yes when the Open Food Facts record's vitamins_tags or minerals_tags is not empty. "
        + "Fill each food detail from the pack as sold; leave unknown when the pack does not settle it."

    /// One CSV field, quoted, with quotes doubled. A field whose first character after any spaces is `=`,
    /// `+`, `-`, `@`, `|`, a tab or a carriage return gets a leading apostrophe, so a spreadsheet never
    /// reads record text as a formula.
    public static func csvField(_ text: String) -> String {
        let opening = text.first { !$0.isWhitespace || $0 == "\t" || $0 == "\r" }
        let safe = opening.map { "=+-@|\t\r".contains($0) } == true ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }
}
