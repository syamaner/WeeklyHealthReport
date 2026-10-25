import Foundation
import FoodLedgerDomain

/// What the pure photo reader made of one model answer (docs/label-photo-ai-prefill-v1.md 12.1
/// and 17.1): the `label-photo-wire-mapping-v1` candidate on the pasted manifest's projection,
/// then the frozen gate, `label-arithmetic-checks-v2` and `pasted-label-conversions-v1`, for the
/// Taiwan format only. The model's text is evidence; every number here comes from the mapping and
/// the frozen rules, never from the model (12.3, invariant 4). It never persists or decides.
public struct LabelPhotoReading: Equatable, Sendable {
    public static let labelFormat = "taiwan_nutrition_labelling"
    public static let launchScope = ["taiwan_nutrition_labelling"]

    public struct Versions: Equatable, Sendable {
        public let mapping: String
        public let gate: String
        public let arithmetic: String
        public let conversion: String
        public init(mapping: String, gate: String, arithmetic: String, conversion: String) {
            self.mapping = mapping; self.gate = gate; self.arithmetic = arithmetic; self.conversion = conversion
        }
    }

    /// SHA-256 of the prepared image bytes the model read (the candidate's `input_sha256`).
    public let imageSHA256: String
    public let candidate: PastedLabelManifest.Candidate
    /// The format the reader inferred; anything but Taiwan is declined (`layout_not_supported`).
    public let inferredFormat: String
    /// Gate v2 on the Taiwan format; nil when the candidate is declined or not Taiwan.
    public let gate: LabelReading.Gate?
    public let checks: [LabelReading.Check]
    public let conversions: [PastedLabelManifest.Conversion]
    public let storedHeaderID: String?
    public let versions: Versions

    public init(imageSHA256: String, candidate: PastedLabelManifest.Candidate, inferredFormat: String, gate: LabelReading.Gate?,
                checks: [LabelReading.Check], conversions: [PastedLabelManifest.Conversion], storedHeaderID: String?,
                versions: Versions) {
        self.imageSHA256 = imageSHA256; self.candidate = candidate; self.inferredFormat = inferredFormat; self.gate = gate
        self.checks = checks; self.conversions = conversions; self.storedHeaderID = storedHeaderID; self.versions = versions
    }

    /// The decline codes Confirm shows instead of values: the model's own decline, a format other
    /// than Taiwan, or a gate hard decline. Empty when the reading can be confirmed.
    public var hardDeclines: [String] {
        if candidate.declined { return candidate.declineReasons }
        if inferredFormat != Self.labelFormat { return [PastedLabelCodes.CopyKey.layoutNotSupported.rawValue] }
        guard let gate else { return [PastedLabelCodes.CopyKey.layoutNotSupported.rawValue] }
        if let skipped = gate.skipped { return [skipped] }
        return gate.hardDeclines
    }

    public var isUsable: Bool { hardDeclines.isEmpty && storedHeaderID != nil }

    /// `<mapping>:<gate>:<arithmetic>:<conversion>`, the part of the pipeline the reader owns.
    public var readerPipeline: String { [versions.mapping, versions.gate, versions.arithmetic, versions.conversion].joined(separator: ":") }
}

/// Consumer-owned port (12.1, 17.1): the wire answer to a reading. The conformer lives in
/// `FoodLabelPhotoReading`, beside the frozen parser rules the application cannot import. A text
/// that is not one schema-valid answer gives nil, and nothing is shown (12.5 test 8).
public protocol LabelPhotoInterpreting: Sendable {
    func reading(wireText: String, imageSHA256: String) -> LabelPhotoReading?
}
