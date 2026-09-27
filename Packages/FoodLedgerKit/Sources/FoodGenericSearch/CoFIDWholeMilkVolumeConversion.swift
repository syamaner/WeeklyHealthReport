import CryptoKit
import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

public enum CoFIDMilkConversionError: Error, Equatable, Sendable {
    case missingRule
    case ruleHashMismatch
    case malformedRule
}

/// One reviewed external volume estimate for one CoFID nutrition record.
public struct CoFIDWholeMilkVolumeConversion: FoodVolumeConversionOffering {
    public static let manifestSHA256 = "bc1b0965edb48e5d09f98092ae6efd85e66fd8ee672880f8de87b650e5514962"
    private let rule: Rule
    public let sourceRelease: SourceRelease
    public let sourceURL: URL

    public init() throws {
        guard let url = Bundle.module.url(forResource: "cofid-whole-milk-volume-v1", withExtension: "json", subdirectory: "Resources") else {
            throw CoFIDMilkConversionError.missingRule
        }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.manifestSHA256 else { throw CoFIDMilkConversionError.ruleHashMismatch }
        guard let rule = try? JSONDecoder().decode(Rule.self, from: data),
              rule.millilitresToGrams == 1.03,
              rule.factorArtifactSHA256.count == 64,
              let factorURL = URL(string: rule.factorURL), factorURL.scheme == "https" else {
            throw CoFIDMilkConversionError.malformedRule
        }
        self.rule = rule
        sourceURL = factorURL
        sourceRelease = SourceRelease(
            sourceReleaseID: try ExternalIdentifier("phe-npm-2018:sha256:\(rule.factorArtifactSHA256)"),
            sourceID: try ExternalIdentifier("phe-npm-2018-annex-a"),
            releasedAt: ISO8601DateFormatter().date(from: "2018-03-01T00:00:00Z")!,
            artifactHash: try SHA256Digest(rule.factorArtifactSHA256),
            schemaVersion: try LedgerText("dairy-source-basis-v1"),
            pipelineVersion: try LedgerText(rule.ruleID),
            licence: try LedgerText(rule.licence),
            attribution: try LedgerText("\(rule.factorSource). \(rule.factorURL)"),
            manifestHash: try SHA256Digest(digest)
        )
    }

    public func offer(for candidate: PopulatedFoodCandidate, original: PositiveQuantity) throws -> QuantityConversionDraft? {
        guard applies(to: candidate), original.unit == .millilitres else { return nil }
        return QuantityConversionDraft(
            convertedQuantity: try FoodQuantityCalculator.estimatedMass(
                volume: original, gramsPerMillilitre: rule.millilitresToGrams),
            methodVersion: try LedgerText(rule.ruleID),
            sourceReleaseID: sourceRelease.sourceReleaseID
        )
    }

    public func applies(to candidate: PopulatedFoodCandidate) -> Bool {
        candidate.candidate.sourceReleaseID.value == rule.nutritionReleaseID
            && candidate.candidate.recordID.value == rule.nutritionRecordID
            && candidate.candidate.identity.servingBasis == .per100Grams
    }

    private struct Rule: Decodable {
        let ruleID: String
        let nutritionReleaseID: String
        let nutritionRecordID: String
        let millilitresToGrams: Double
        let factorSource: String
        let factorURL: String
        let factorArtifactSHA256: String
        let licence: String

        enum CodingKeys: String, CodingKey {
            case ruleID = "rule_id"
            case nutritionReleaseID = "nutrition_release_id"
            case nutritionRecordID = "nutrition_record_id"
            case millilitresToGrams = "millilitres_to_grams"
            case factorSource = "factor_source"
            case factorURL = "factor_url"
            case factorArtifactSHA256 = "factor_artifact_sha256"
            case licence
        }
    }
}
