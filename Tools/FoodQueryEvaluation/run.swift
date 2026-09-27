import Foundation
@main struct EvaluateQueries {
    struct Fixture: Decodable { let cases: [Case] }
    struct Case: Decodable { let id: String; let query: String }
    struct Output: Encodable { let id: String; let parsed: ParsedFoodQuery }
    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let results = fixture.cases.map { Output(id: $0.id, parsed: FoodQueryParser.parse($0.query, recognisedBrands: ["Acme"])) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
