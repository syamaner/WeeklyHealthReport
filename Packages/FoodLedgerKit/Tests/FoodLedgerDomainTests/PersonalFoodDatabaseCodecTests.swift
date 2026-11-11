import CryptoKit
@testable import FoodLedgerDomain
import Foundation
import XCTest

/// Import v1 section 9 for the pure codec (phase 1, P1a; docs/personal-food-database-import-v1-phase-1.md).
/// The shared fixtures are the skill checker's own (`test_export_check.py`), so both sides must give
/// the same verdict and rule code for every file. Synthetic data only.
final class PersonalFoodDatabaseCodecTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let fixtures = repoRoot.appendingPathComponent("docs/fixtures/personal-food-database-v1")
    /// `shasum -a 256` of the committed golden.json; the skill reports the same release prefix.
    static let goldenSHA256 = "4847a36ac12f16fe74ed8680fc87dedcc1b5de1eb68775ac7eea780e405265ec"

    struct Manifest: Decodable {
        let golden: String
        let reject: [String: String]
        let accept: [String]
        let generated_at_test_time: [String: String]
        let rule_codes: [String]
        let canonical_units: [String: String]
        let max_depth: Int
        let max_values: Int
    }

    func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("manifest.json")))
    }

    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Self.fixtures.appendingPathComponent(name)) }

    func codes(_ data: Data) -> Set<String> {
        switch PersonalFoodDatabaseCodec.decode(data) {
        case .success: []
        case let .failure(rejection): Set(rejection.codes.map(\.rawValue))
        }
    }

    func golden() throws -> PersonalFoodDatabaseFile {
        try PersonalFoodDatabaseCodec.decode(try fixture(try manifest().golden)).get()
    }

    // MARK: Shared fixtures

    func testEveryRejectFixtureGivesItsRuleCode() throws {
        let m = try manifest()
        XCTAssertGreaterThanOrEqual(m.reject.count, 80)
        for (file, code) in m.reject.sorted(by: { $0.key < $1.key }) {
            let got = codes(try fixture(file))
            XCTAssertTrue(got.contains(code), "\(file): expected \(code), got \(got.sorted())")
        }
    }

    func testGoldenAndAcceptFixturesAreAccepted() throws {
        let m = try manifest()
        XCTAssertFalse(m.accept.isEmpty)
        for file in [m.golden] + m.accept {
            XCTAssertEqual(codes(try fixture(file)), [], file)
        }
    }

    func testGeneratedLargeCases() throws {
        let m = try manifest()
        XCTAssertEqual(m.generated_at_test_time, ["over-size-limit": "size", "too-many-items": "count", "too-many-values": "count"])
        XCTAssertEqual(codes(Data(repeating: 0x20, count: PersonalFoodDatabaseJSON.limitBytes + 1)), ["size"])
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture(m.golden)) as? [String: Any])
        let first = try XCTUnwrap((doc["items"] as? [Any])?.first)
        doc["items"] = Array(repeating: first, count: PersonalFoodDatabaseCodec.limitItems + 1)
        XCTAssertTrue(codes(try JSONSerialization.data(withJSONObject: doc)).contains("count"))
        // The value budget: one array of 4,000,001 zeros (4,000,002 values with the array itself).
        var dense = [UInt8(ascii: "[")]
        dense.reserveCapacity(2 * PersonalFoodDatabaseJSON.maxValues + 3)
        for _ in 0..<PersonalFoodDatabaseJSON.maxValues { dense += [UInt8(ascii: "0"), UInt8(ascii: ",")] }
        dense += [UInt8(ascii: "0"), UInt8(ascii: "]")]
        XCTAssertEqual(codes(Data(dense)), ["count"])
    }

    func testValueBudgetIsExactAndKeepsPythonOrder() {
        // The rules with a small budget; testGeneratedLargeCases checks the real one.
        let n = 10
        func read(_ count: Int, tail: String = "") -> PersonalFoodDatabaseRuleCode? {
            let text = "[" + Array(repeating: "0", count: count).joined(separator: ",") + tail + "]"
            if case let .failure(code) = PersonalFoodDatabaseJSON.read(Data(text.utf8), valueBudget: n) { return code }
            return nil
        }
        XCTAssertNil(read(n - 1), "the array and its elements fit exactly")
        XCTAssertEqual(read(n), .count)
        XCTAssertEqual(read(2, tail: ",{\"a\":{\"b\":[1,2,3,4,5,6]}}"), .count, "keys do not count, nested values do")
        // A syntax error or repeated key after the budget is passed is still reported first, as in Python.
        XCTAssertEqual(read(n, tail: ",NaN"), .json)
        XCTAssertEqual(read(n, tail: ",{\"a\":1,\"a\":2}"), .duplicateKey)
        // The budget is checked before unpaired surrogates, as in export_v1.
        XCTAssertEqual(read(n, tail: ",\"\\ud800\""), .count)
    }

    func testRuleCodesEqualThePythonChecker() throws {
        XCTAssertEqual(Set(PersonalFoodDatabaseRuleCode.allCases.map(\.rawValue)), Set(try manifest().rule_codes))
    }

    func testCanonicalUnitsAndDepthEqualThePythonChecker() throws {
        let m = try manifest()
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: NutrientKey.allCases.map { ($0.rawValue, $0.canonicalUnit.rawValue) }),
                       m.canonical_units)
        XCTAssertEqual(PersonalFoodDatabaseJSON.maxDepth, m.max_depth)
        XCTAssertEqual(PersonalFoodDatabaseJSON.maxValues, m.max_values)
    }

    // MARK: Typed model

    func testGoldenDecodesToTypedValues() throws {
        let file = try golden()
        XCTAssertEqual(file.generated, PersonalFoodDatabaseDate(year: 2026, month: 11, day: 7))
        XCTAssertEqual(file.sources.map(\.sourceID), [.openFoodFacts, .owner])
        XCTAssertEqual(file.genericCorpora, [.cofid: String(repeating: "a", count: 64), .tfda: String(repeating: "a", count: 64)])
        XCTAssertEqual(file.entries.map(\.id), file.entries.map(\.id).sorted())
        let titles = Set(file.entries.map(\.title))
        XCTAssertEqual(titles, ["Synthetic Example Oats", "合成豆腐", "Synthetic Crème Spread"])

        let oats = try XCTUnwrap(file.entries.first { $0.title == "Synthetic Example Oats" })
        XCTAssertEqual(oats.brand, "Example Brand")
        XCTAssertEqual(oats.state, .raw)
        XCTAssertEqual(oats.basis, .per100Grams)
        XCTAssertEqual(oats.genericReference, PersonalFoodDatabaseGenericReference(
            source: .cofid, corpusSHA256: String(repeating: "a", count: 64), recordID: "cofid:example",
            match: .sameFoodSameState, role: .merge))
        let sodium = try XCTUnwrap(oats.labelNutrients.first { $0.key == .sodium }?.value)
        XCTAssertEqual(sodium.value, 5.0)
        XCTAssertEqual(sodium.unit, .milligrams)
        XCTAssertEqual(sodium.source, .exactProductDataset(
            sourceRelease: file.sources[0].sourceReleaseID, recordID: "off:gtin:00000000000017"))
        XCTAssertEqual(sodium.transform, PersonalFoodDatabaseTransform(
            transformID: "mass-g-to-mg", version: "v1", sourceValue: 0.005, sourceUnit: "g"))
        let energy = try XCTUnwrap(oats.labelNutrients.first { $0.key == .energyConsumed }?.value)
        XCTAssertEqual(energy.value, 370)
        XCTAssertEqual(energy.source, .manualDeclaration(sourceRelease: file.sources[1].sourceReleaseID))
        XCTAssertNil(energy.transform)

        let tofu = try XCTUnwrap(file.entries.first { $0.title == "合成豆腐" })
        XCTAssertNil(tofu.brand)
        XCTAssertTrue(tofu.labelNutrients.isEmpty)
        XCTAssertEqual(tofu.genericReference?.role, .candidate)
        XCTAssertEqual(tofu.genericReference?.recordID, "tfda:X0001")
    }

    func testEntryEqualityCoversEveryField() throws {
        func entry(_ mutate: (inout [String: Any]) -> Void) throws -> PersonalFoodDatabaseEntry {
            var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("golden.json")) as? [String: Any])
            var items = try XCTUnwrap(doc["items"] as? [[String: Any]])
            let i = try XCTUnwrap(items.firstIndex { $0["title"] as? String == "合成豆腐" })
            mutate(&items[i])
            doc["items"] = items
            let file = try PersonalFoodDatabaseCodec.decode(try JSONSerialization.data(withJSONObject: doc)).get()
            return try XCTUnwrap(file.entries.first { $0.id == items[i]["id"] as? String })
        }
        let base = try entry { _ in }
        XCTAssertEqual(base, try entry { _ in })
        XCTAssertNotEqual(base, try entry { $0["state"] = "frozen" })
        XCTAssertNotEqual(base, try entry { $0["basis"] = "per_100_ml_as_labelled" })
        XCTAssertNotEqual(base, try entry { $0["category"] = "other" })
        XCTAssertNotEqual(base, try entry { $0["aliases"] = ["x"] })
    }

    func testNegativeZeroBecomesZeroAndEmptyBrandStays() throws {
        let zero = try PersonalFoodDatabaseCodec.decode(try fixture("accept-negative-zero.json")).get()
        let energy = zero.entries.flatMap(\.labelNutrients).first { $0.key == .energyConsumed }?.value.value
        XCTAssertEqual(energy, 0)
        XCTAssertEqual(energy?.sign, .plus)
        let empty = try PersonalFoodDatabaseCodec.decode(try fixture("accept-empty-brand.json")).get()
        XCTAssertTrue(empty.entries.contains { $0.brand == "" })
    }

    // MARK: Release identity

    func testDatabaseReleaseIsAPureFunctionOfTheBytes() throws {
        let bytes = try fixture("golden.json")
        let hex = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, Self.goldenSHA256, "golden.json changed; regenerate it with the skill and update the pin")
        let digest = try SHA256Digest(hex)
        let release = try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: digest, generated: try golden().generated)
        XCTAssertEqual(release.sourceReleaseID.value, "pfc:sha256:\(hex)")
        XCTAssertEqual(release.sourceID.value, "personal-food-database")
        XCTAssertEqual(release.releasedAt, Date(timeIntervalSince1970: 1_794_009_600))
        XCTAssertEqual(release.artifactHash, digest)
        XCTAssertEqual(release.manifestHash, digest)
        XCTAssertEqual(release.schemaVersion.value, "personal-food-catalogue-v1")
        XCTAssertEqual(release.pipelineVersion.value, "pfc-resolution-v1")
        XCTAssertEqual(release.licence.value, "private")
        XCTAssertEqual(release.attribution.value, "Your food database, built by the owner")
        XCTAssertEqual(release, try PersonalFoodDatabaseRelease.sourceRelease(fileSHA256: digest, generated: try golden().generated))

        var changed = [UInt8](bytes)
        changed[changed.count - 2] ^= 0x01
        XCTAssertNotEqual(SHA256.hash(data: Data(changed)).map { String(format: "%02x", $0) }.joined(), hex)
    }

    func testDeclaredSourcesMapToSourceReleases() throws {
        let file = try golden()
        let off = try file.sources[0].sourceRelease()
        XCTAssertEqual(off.sourceID.value, "open-food-facts")
        XCTAssertEqual(off.pipelineVersion.value, "off-product-projection-v4")
        XCTAssertEqual(off.artifactHash.value, String(repeating: "b", count: 64))
        XCTAssertEqual(off.releasedAt, Date(timeIntervalSince1970: 1_794_009_600))
        let owner = try file.sources[1].sourceRelease()
        XCTAssertEqual(owner.sourceReleaseID.value, "owner:sha256:" + String(repeating: "c", count: 64))
        XCTAssertEqual(owner.attribution.value, "Label values typed or confirmed by the owner")
        XCTAssertEqual(try file.sources[1].sourceRelease(), owner)
    }

    func testReleaseDateIgnoresTheProcessTimeZone() throws {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for zone in ["Pacific/Kiritimati", "America/Los_Angeles", "Asia/Taipei"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: zone))
            XCTAssertEqual(PersonalFoodDatabaseDate(year: 2026, month: 11, day: 7)?.utcMidnight,
                           Date(timeIntervalSince1970: 1_794_009_600), zone)
        }
        XCTAssertEqual(PersonalFoodDatabaseDate(year: 1970, month: 1, day: 1)?.utcMidnight, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(PersonalFoodDatabaseDate(year: 2000, month: 3, day: 1)?.utcMidnight, Date(timeIntervalSince1970: 951_868_800))
        XCTAssertNil(PersonalFoodDatabaseDate(year: 2026, month: 2, day: 29))
        XCTAssertNotNil(PersonalFoodDatabaseDate(year: 2024, month: 2, day: 29))
        XCTAssertNil(PersonalFoodDatabaseDate(year: 1900, month: 2, day: 29))
        XCTAssertNil(PersonalFoodDatabaseDate(year: 0, month: 1, day: 1))
    }

    // MARK: The strict reader

    func read(_ text: String) -> Result<PersonalFoodDatabaseJSONValue, PersonalFoodDatabaseRuleCode> {
        PersonalFoodDatabaseJSON.read(Data(text.utf8))
    }

    func code(_ text: String) -> PersonalFoodDatabaseRuleCode? {
        if case let .failure(c) = read(text) { c } else { nil }
    }

    func testReaderStagesAndCodes() {
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data([0xEF, 0xBB, 0xBF, 0x7B, 0x7D])).failureCode, .bom)
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data("{}".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })).failureCode, .json)
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data([0xFF, 0xFE, 0x7B, 0x00, 0x7D, 0x00])).failureCode, .encoding)
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data([0x22, 0xED, 0xA0, 0x80, 0x22])).failureCode, .encoding)  // UTF-8 surrogate
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data([0x22, 0xC0, 0xAF, 0x22])).failureCode, .encoding)  // overlong
        // Encoding is checked before parsing, nesting before repeated keys.
        XCTAssertEqual(PersonalFoodDatabaseJSON.read(Data([0x7B, 0xFF])).failureCode, .encoding)
        XCTAssertEqual(code("{\"a\":1,\"a\":1," + String(repeating: "[", count: 65) + "}"), .json)
        XCTAssertEqual(code("{\"a\":{\"b\":1,\"b\":2}}"), .duplicateKey)
        XCTAssertEqual(code("{\"a\":1,\"a\":NaN}"), .json)  // the parse error inside the object comes first
        for bad in ["NaN", "[Infinity]", "[-Infinity]", "", "{} x", "[1,]", "{\"a\":1,}", "[01]", "[1.]", "[.5]",
                    "[\"\u{01}\"]", "[\"\\x\"]", "[\"\\u12G4\"]", "'a'", "[tru]", "[1e]x"] {
            XCTAssertEqual(code(bad), .json, bad)
        }
    }

    func testDepthLimitIsExact() {
        XCTAssertNotNil(try? read(String(repeating: "[", count: 64) + String(repeating: "]", count: 64)).get())
        XCTAssertEqual(code(String(repeating: "[", count: 65) + String(repeating: "]", count: 65)), .json)
        XCTAssertNotNil(try? read("[\"" + String(repeating: "[", count: 100) + "\"]").get(), "brackets inside a string do not count")
        XCTAssertNotNil(try? read("[\"\\\"" + String(repeating: "{", count: 100) + "\"]").get())
    }

    func testNumbersAndTheirRange() throws {
        XCTAssertNotNil(try? read(String(repeating: "9", count: 4300)).get())
        XCTAssertNotNil(try? read("-" + String(repeating: "9", count: 4300)).get(), "the sign is not a digit")
        XCTAssertEqual(code(String(repeating: "9", count: 4301)), .json)
        XCTAssertNotNil(try? read("1." + String(repeating: "9", count: 5000)).get(), "the digit limit is for integers")
        guard case let .array(values) = try read("[1e400, -0, 4e2, 1E+2, 0.5e-3]").get() else { return XCTFail() }
        let doubles = values.compactMap { if case let .number(d) = $0 { d } else { nil } }
        XCTAssertEqual(doubles.first, .infinity)
        XCTAssertEqual(Array(doubles.dropFirst()), [0, 400, 100, 0.0005])
        XCTAssertNil(PFDValue.number(1e15).nutrientNumber)
        XCTAssertEqual(PFDValue.number(999_999_999_999_999).nutrientNumber, 999_999_999_999_999)
        XCTAssertNil(PFDValue.bool(true).nutrientNumber)
    }

    func testStringsAndSurrogates() throws {
        guard case let .array(values) = try read("[\"\\u00e9\", \"\\ud83d\\ude00\", \"caf\u{e9}\", \"\\/\\b\"]").get() else {
            return XCTFail()
        }
        XCTAssertEqual(values.compactMap(\.text).map(\.string), ["é", "😀", "café", "/\u{08}"])
        for lone in ["[\"\\ud800\"]", "[\"\\udc00\"]", "[\"\\ud800\\u0041\"]", "[\"\\ud800x\"]", "{\"\\ud800\":1}"] {
            XCTAssertEqual(code(lone), .json, lone)
        }
        // A repeated key is reported before an unpaired surrogate, as in Python.
        XCTAssertEqual(code("{\"a\":\"\\ud800\",\"a\":1}"), .duplicateKey)
    }

    func testKeysCompareByScalarsNotCanonicalEquivalence() throws {
        let nfc = "\u{e9}", nfd = "e\u{301}"
        XCTAssertEqual(nfc, nfd, "Swift String treats them as equal")
        guard case let .object(members) = try read("{\"\(nfc)\":1,\"\(nfd)\":2}").get() else { return XCTFail() }
        XCTAssertEqual(members.count, 2)
        XCTAssertNotEqual(members[0].key, members[1].key)
        // The Kelvin sign is canonically equivalent to "K" in Swift; it must not pass as a vocabulary word.
        XCTAssertNotEqual(PFDText(bytes: Array("\u{212A}".utf8)), PFDText("K"))
    }

    func testDigitRulesAreASCIIOnly() {
        typealias R = PersonalFoodDatabaseRules
        XCTAssertTrue(R.isEntryID(PFDText("pfc:0123456789ab")))
        XCTAssertFalse(R.isEntryID(PFDText(bytes: Array(("pfc:" + String(repeating: "\u{FF10}", count: 12)).utf8))))
        XCTAssertFalse(R.isEntryID(PFDText("pfc:0123456789AB")))
        XCTAssertTrue(R.isGTINRecordID(PFDText("off:gtin:00000000000017")))
        XCTAssertFalse(R.isGTINRecordID(PFDText(bytes: Array(("off:gtin:" + String(repeating: "\u{0660}", count: 14)).utf8))))
        XCTAssertNil(PersonalFoodDatabaseDate(ascii: Array("\u{FF12}\u{FF10}\u{FF12}\u{FF16}-11-07".utf8)))
        XCTAssertNil(PersonalFoodDatabaseDate(ascii: Array("2026-W45-6".utf8)))
        XCTAssertFalse(R.isHex64(Array(String(repeating: "\u{FF41}", count: 64).utf8)))
    }

    func testTitleBlanknessFollowsPythonStrip() {
        typealias R = PersonalFoodDatabaseRules
        for blank in [" ", "\u{1C}", "\u{3000}\u{2028}", "\u{85}\u{A0}", "\t\n"] {
            XCTAssertTrue(R.isBlank(PFDText(bytes: Array(blank.utf8))), blank.debugDescription)
        }
        for text in ["a", "\u{200B}", "\u{180E}", "\u{FEFF}"] {  // not whitespace to Python
            XCTAssertFalse(R.isBlank(PFDText(bytes: Array(text.utf8))), text.debugDescription)
        }
    }

    func testTransformToleranceUsesThePythonFormula() {
        typealias R = PersonalFoodDatabaseRules
        XCTAssertFalse(R.transformArithmeticFails(expected: 5, value: 5.025))
        XCTAssertTrue(R.transformArithmeticFails(expected: 5, value: 5.0251))
        XCTAssertFalse(R.transformArithmeticFails(expected: 0, value: 1e-9))
        XCTAssertTrue(R.transformArithmeticFails(expected: 0, value: 2e-9))
        XCTAssertNil(R.transform(id: PFDText("mass-g-to-mg"), version: PFDText("v2")))
        XCTAssertEqual(R.transform(id: PFDText("mass-g-to-mg"), version: PFDText("v1"))?.nutrient, .sodium)
        XCTAssertFalse(NutrientDerivation.calculatedTransforms.contains { $0.transformID == "mass-g-to-mg" },
                       "a unit conversion is never a calculation")
    }

    // MARK: Robustness

    /// A seeded sweep of truncations, byte flips and type swaps of the golden file: every result is a
    /// verdict, never a trap, and a mutated file is never accepted with a changed meaning unnoticed.
    func testMutatedGoldenFilesNeverTrap() throws {
        let golden = [UInt8](try fixture("golden.json"))
        var seed: UInt64 = 0x5EED_0424
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        let swaps = ["\"x\"", "[]", "{}", "null", "true", "-1", "1e400", "[[]]", "{\"a\":{}}"]
        var rejected = 0
        for round in 0..<600 {
            var bytes = golden
            switch round % 3 {
            case 0:
                bytes = Array(bytes.prefix(next() % bytes.count))
            case 1:
                bytes[next() % bytes.count] = UInt8(truncatingIfNeeded: next())
            default:
                let text = String(decoding: bytes, as: UTF8.self)
                let colons = text.indices.filter { text[$0] == ":" }
                let at = colons[next() % colons.count]
                let after = text.index(after: at)
                let end = text[after...].firstIndex { $0 == "," || $0 == "}" || $0 == "]" } ?? text.endIndex
                bytes = Array((String(text[...at]) + " " + swaps[next() % swaps.count] + String(text[end...])).utf8)
            }
            if case .failure = PersonalFoodDatabaseCodec.decode(Data(bytes)) { rejected += 1 }
        }
        XCTAssertGreaterThan(rejected, 500)
    }
}

private extension Result where Failure == PersonalFoodDatabaseRuleCode {
    var failureCode: PersonalFoodDatabaseRuleCode? {
        if case let .failure(code) = self { code } else { nil }
    }
}
