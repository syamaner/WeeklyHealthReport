import CryptoKit
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

public enum USDACountPortionGuidesError: Error, Equatable, Sendable {
    case missingManifest
    case manifestHashMismatch
    case malformedManifest
}

/// The reviewed count portion guides (count-portion-estimate-v1, #307): typical edible weights of
/// one whole egg without shell in four sizes, from USDA SR Legacy April 2018, for four
/// allow-listed records. Bundled and hash-pinned; no network.
public struct USDACountPortionGuides: FoodEdibleWeightGuideProviding {
    public static let manifestSHA256 = "5bcf4a90d77ddc9c465196e241a2e7400ad68934707be8737e37d10e7917ae84"
    public let sourceRelease: SourceRelease
    /// Guide sets keyed by nutrition release and record.
    private let sets: [String: FoodEdibleWeightGuideSet]

    public init() throws {
        guard let url = Bundle.module.url(forResource: "count-portion-guides-v1", withExtension: "json", subdirectory: "Resources") else {
            throw USDACountPortionGuidesError.missingManifest
        }
        try self.init(data: try Data(contentsOf: url), expectedSHA256: Self.manifestSHA256)
    }

    /// Tests pass altered bytes to prove a tampered manifest is refused.
    public init(data: Data, expectedSHA256: String) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw USDACountPortionGuidesError.manifestHashMismatch }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.guideSetID == "count-portion-guides-v1",
              manifest.source.archiveSHA256.count == 64, manifest.source.licence == "CC0 1.0" else {
            throw USDACountPortionGuidesError.malformedManifest
        }
        var byRecord: [String: [(Guide, FoodEdibleWeightGuide)]] = [:]
        for guide in manifest.guides {
            // Every manifest entry must equal the frozen application table (gate G3).
            guard let code = try? LedgerText(guide.guideID), let frozen = CountPortionGuideCode.entry(code),
                  let size = FoodEdibleWeightGuideSize(rawValue: guide.size), size == frozen.size,
                  guide.grams == frozen.grams, (guide.derivation == "raw_size_weight_for_boiled") == frozen.isDerived,
                  guide.derivation == "none" || guide.derivation == "raw_size_weight_for_boiled",
                  guide.preparation == frozen.preparation.rawValue, guide.part == "whole_without_shell",
                  guide.sourceFDCID == frozen.sourceFDCID, guide.sourcePortionID == frozen.sourcePortionID,
                  guide.sourceDescriptor == frozen.sourceDescriptor, !guide.appliesTo.isEmpty,
                  let value = try? FoodEdibleWeightGuide(code: code, size: size, sourceDescriptor: LedgerText(guide.sourceDescriptor),
                                                         edibleGramsPerPiece: guide.grams, isDerived: frozen.isDerived) else {
                throw USDACountPortionGuidesError.malformedManifest
            }
            for pair in guide.appliesTo {
                guard pair.count == 2, pair[1].hasPrefix(pair[0] + ":") else { throw USDACountPortionGuidesError.malformedManifest }
                byRecord[pair[0] + "\u{1F}" + pair[1], default: []].append((guide, value))
            }
        }
        guard Set(manifest.guides.map(\.guideID)) == Set(CountPortionGuideCode.entries.map(\.code)) else {
            throw USDACountPortionGuidesError.malformedManifest
        }
        var sets: [String: FoodEdibleWeightGuideSet] = [:]
        for (key, guides) in byRecord {
            let parts = key.split(separator: "\u{1F}").map(String.init)
            let defaults = guides.filter { $0.0.isDefault }
            let ordered = guides.map(\.1).sorted {
                FoodEdibleWeightGuideSize.allCases.firstIndex(of: $0.size)! < FoodEdibleWeightGuideSize.allCases.firstIndex(of: $1.size)!
            }
            guard defaults.count == 1, defaults[0].1.size == .large,
                  Set(ordered.map(\.size)) == Set(FoodEdibleWeightGuideSize.allCases), ordered.count == 4,
                  Set(guides.map(\.0.preparation)).count == 1,
                  let set = try? FoodEdibleWeightGuideSet(foodRecordID: ExternalIdentifier(parts[1]),
                    foodSourceReleaseID: ExternalIdentifier(parts[0]), entries: ordered, defaultCode: defaults[0].1.code) else {
                throw USDACountPortionGuidesError.malformedManifest
            }
            sets[key] = set
        }
        self.sets = sets
        sourceRelease = SourceRelease(
            sourceReleaseID: try ExternalIdentifier(CountPortionGuideCode.sourceReleaseID),
            sourceID: try ExternalIdentifier("usda-sr-legacy-portions"),
            releasedAt: ISO8601DateFormatter().date(from: "2018-04-01T00:00:00Z")!,
            artifactHash: try SHA256Digest(manifest.source.archiveSHA256),
            schemaVersion: try LedgerText("count-portion-guide-v1"),
            pipelineVersion: try LedgerText(manifest.guideSetID),
            licence: try LedgerText(manifest.source.licence),
            attribution: try LedgerText(manifest.source.attribution),
            manifestHash: try SHA256Digest(digest)
        )
        guard sourceRelease.sourceReleaseID.value == "usda-sr-legacy-portions:\(manifest.source.releaseDate):sha256:\(manifest.source.archiveSHA256)" else {
            throw USDACountPortionGuidesError.malformedManifest
        }
    }

    public func guide(for candidate: PopulatedFoodCandidate) throws -> FoodEdibleWeightGuideSet? {
        sets[candidate.candidate.sourceReleaseID.value + "\u{1F}" + candidate.candidate.recordID.value]
    }

    /// Whether any of these candidates has a guide (the composition root adds the release then).
    public func appliesToAny(_ candidates: [PopulatedFoodCandidate]) -> Bool {
        candidates.contains { (try? guide(for: $0)) != nil }
    }

    private struct Manifest: Decodable {
        let guideSetID: String
        let source: Source
        let guides: [Guide]
        enum CodingKeys: String, CodingKey { case guideSetID = "guide_set_id", source, guides }
    }

    private struct Source: Decodable {
        let archiveSHA256: String
        let releaseDate: String
        let licence: String
        let attribution: String
        enum CodingKeys: String, CodingKey {
            case archiveSHA256 = "archive_sha256", releaseDate = "release_date", licence, attribution
        }
    }

    private struct Guide: Decodable {
        let guideID: String
        let size: String
        let grams: Double
        let part: String
        let preparation: String
        let sourceFDCID: Int
        let sourcePortionID: Int
        let sourceDescriptor: String
        let derivation: String
        let isDefault: Bool
        let appliesTo: [[String]]
        enum CodingKeys: String, CodingKey {
            case guideID = "guide_id", size, grams, part, preparation, derivation
            case sourceFDCID = "source_fdc_id", sourcePortionID = "source_portion_id", sourceDescriptor = "source_descriptor"
            case isDefault = "default", appliesTo = "applies_to"
        }
    }
}
