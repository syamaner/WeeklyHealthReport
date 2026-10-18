import Foundation
import Testing
@testable import NutritionLabelParsing

// Contract tests 1 and 25 (`docs/pasted-nutrition-label-v1.md` section 8.4): the Swift decline
// gate reproduces gate v2 (`decline_gate.py`) on every exported vector, and classifies every code
// point in HAN_RANGES and UNSUPPORTED_RANGES exactly as gate v2 does.

@Test func test25FrozenTablesMatchTheirRecordedHashes() throws {
    let recorded = try ParityFixtures.recordedHashes()
    let simplified = try LabelGateTables.resourceData(LabelDeclineGate.simplifiedOnlyTableResource)
    let markers = try LabelGateTables.resourceData(LabelDeclineGate.markerClassesTableResource)
    #expect(ParityFixtures.sha256(simplified) == LabelDeclineGate.simplifiedOnlyTableSHA256)
    #expect(ParityFixtures.sha256(markers) == LabelDeclineGate.markerClassesTableSHA256)
    #expect(recorded[LabelDeclineGate.simplifiedOnlyTableResource] == LabelDeclineGate.simplifiedOnlyTableSHA256)
    #expect(recorded[LabelDeclineGate.markerClassesTableResource] == LabelDeclineGate.markerClassesTableSHA256)
    for name in ["parity-code-points-v1.json", "parity-cases-v1.jsonl", "parity-mutations-v1.jsonl"] {
        #expect(recorded[name] == ParityFixtures.sha256(try ParityFixtures.data(name)), "\(name) does not match parity-sha256-v1.txt")
    }
    // The table is the contract's format: upper-case hexadecimal, sorted, one per line.
    let lines = String(decoding: simplified, as: UTF8.self).split(separator: "\n").map(String.init)
    let values = lines.compactMap { UInt32($0, radix: 16) }
    #expect(values.count == lines.count)
    #expect(values == values.sorted())
    #expect(lines.allSatisfy { $0 == $0.uppercased() && $0.count == 4 })
    #expect(values.count == 2365)
}

@Test func test25EveryHanAndUnsupportedCodePointMatchesGateV2() throws {
    let vector = try ParityFixtures.object("parity-code-points-v1.json")
    let han = (vector["han_ranges"] as? [[Int]] ?? []).map { UInt32($0[0])...UInt32($0[1]) }
    let unsupported = (vector["unsupported_ranges"] as? [[Int]] ?? []).map { UInt32($0[0])...UInt32($0[1]) }
    #expect(han == LabelDeclineGate.hanRanges)
    #expect(unsupported == LabelDeclineGate.unsupportedRanges)
    let shared = Set((vector["shared_variants"] as? [String] ?? []).compactMap { UInt32($0, radix: 16) })
    #expect(shared == Set(LabelDeclineGate.sharedVariants.flatMap { $0.unicodeScalars.map(\.value) }))

    var walked = 0
    var mismatches: [String] = []
    for run in vector["runs"] as? [[Any]] ?? [] {
        guard let low = run[0] as? Int, let high = run[1] as? Int, let klass = run[2] as? String else { continue }
        for code in low...high {
            walked += 1
            guard let scalar = Unicode.Scalar(UInt32(code)) else {
                mismatches.append(String(format: "%04X is not a scalar", code))
                continue
            }
            let mine = LabelDeclineGate.isSimplifiedOnly(scalar) ? "s" : LabelDeclineGate.isUnsupportedScript(scalar) ? "u" : "-"
            if mine != klass { mismatches.append(String(format: "%04X: %@ != %@", code, mine, klass)) }
        }
    }
    #expect(walked == vector["code_points"] as? Int)
    #expect(walked == (han + unsupported).reduce(0) { $0 + Int($1.upperBound - $1.lowerBound) + 1 })
    #expect(mismatches.isEmpty, "\(mismatches.prefix(20))")
    // Nothing outside HAN_RANGES is Simplified-only, and shared variants never are.
    #expect(!LabelDeclineGate.isSimplifiedOnly("A"))
    for variant in LabelDeclineGate.sharedVariants {
        #expect(!LabelDeclineGate.isSimplifiedOnly(variant.unicodeScalars.first!))
    }
}

@Test func test1GateReproducesGateV2OnEveryVector() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    let meta = try #require(lines.first)
    #expect(meta["gate_version"] as? String == LabelDeclineGate.version)
    #expect(meta["supplement_marker_pattern"] as? String == SupplementMarkerMatcher.pattern)
    #expect(LabelGateTables.shared?.markerPattern == SupplementMarkerMatcher.pattern)

    var compared = 0
    var problems: [String] = []
    var outcomes: [String: Int] = [:]
    for record in lines.dropFirst() {
        let id = record["id"] as? String ?? "?"
        let format = try #require(LabelGateFormat(rawValue: record["declared_format"] as? String ?? ""))
        let candidate = try ParityFixtures.candidate(record["candidate"])
        let expected = try #require((record["expected"] as? [String: Any])?["gate"] as? [String: Any])
        let (gated, report) = LabelDeclineGate.apply(candidate, format: format)
        let python = try #require(expected["report"] as? [String: Any])
        if !ParityFixtures.sameJSON(ParityFixtures.reportObject(report), python) {
            problems.append("\(id): report \(ParityFixtures.reportObject(report)) != \(python)")
        }
        if let pythonGated = expected["gated"], !(pythonGated is NSNull) {
            let mine = try gated.map(ParityFixtures.jsonObject) ?? NSNull()
            if !ParityFixtures.sameJSON(mine, pythonGated) { problems.append("\(id): gated candidate differs") }
        } else if gated != candidate {
            problems.append("\(id): Python returned the candidate unchanged, Swift changed it")
        }
        // Hard declines and flags split the raw outcome exactly once.
        #expect(Set(report.hardDeclines).isDisjoint(with: report.flags))
        #expect(report.hardDeclines.count + report.flags.count == report.declines.count + report.blocks.count)
        let key = report.skipped?.rawValue ?? ((report.declines + report.blocks).map(\.rawValue).joined(separator: "+").nonEmpty ?? "pass")
        outcomes[key, default: 0] += 1
        compared += 1
    }
    #expect(problems.isEmpty, "\(problems.prefix(10))")
    #expect(compared == lines.count - 1)
    // Every rule and skipped state is exercised by at least one vector.
    for reason in LabelGateReason.allCases {
        #expect(outcomes.keys.contains { $0.contains(reason.rawValue) }, "no vector for \(reason)")
    }
    #expect(outcomes["failed_candidate"] ?? 0 > 0)
    #expect(outcomes["already_declined"] ?? 0 > 0)
}

@Test func supplementMarkersFollowPythonReSemantics() {
    let markers = LabelDeclineGate.supplementMarkers(in:)
    #expect(markers("SOFTGELS") == ["softgels"])
    #expect(markers("Soft Gels") == ["soft gels"])
    #expect(markers("soft  gel").isEmpty) // `\s?` allows one space only
    #expect(markers("softgelsx").isEmpty)
    #expect(markers("xsoftgel").isEmpty)
    #expect(markers("_softgel").isEmpty) // `_` is a word character
    #expect(markers("softgel²").isEmpty) // `²` is alphanumeric in Python
    #expect(markers("softgel\u{0301}") == ["softgel"]) // a combining mark is not `\w` in Python
    #expect(markers("soft\u{1C}gel") == ["soft\u{1C}gel"]) // U+001C is `\s` in Python
    #expect(markers("soft\u{0B}gel") == ["soft\u{0B}gel"])
    #expect(markers("ſoftgel") == ["ſoftgel"]) // ſ matches s case-insensitively and lowers to itself
    #expect(markers("DİETARY SUPPLEMENT") == ["di\u{0307}etary supplement"])
    #expect(markers("CAPLETSS").isEmpty)
    #expect(markers("softgel softgel caplet") == ["softgel", "softgel", "caplet"])
    #expect(markers("營養補充食品") == ["營養補充"])
    #expect(markers("Coffee capsule tablet 膠囊 口含錠").isEmpty)
}

@Test func gateNeverChangesAValueOnAPass() throws {
    let lines = try ParityFixtures.lines("parity-cases-v1.jsonl")
    for record in lines.dropFirst() where record["kind"] as? String == "text" {
        let format = try #require(LabelGateFormat(rawValue: record["declared_format"] as? String ?? ""))
        guard let candidate = try ParityFixtures.candidate(record["candidate"]) else { continue }
        let (gated, report) = LabelDeclineGate.apply(candidate, format: format)
        if report.declines.isEmpty {
            #expect(gated?.cells == candidate.cells)
            #expect(gated?.headers == candidate.headers)
            #expect(gated?.servingSize == candidate.servingSize)
            #expect(gated?.servingsPerPack == candidate.servingsPerPack)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
