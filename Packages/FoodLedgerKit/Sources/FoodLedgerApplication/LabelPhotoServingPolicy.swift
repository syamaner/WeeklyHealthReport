import Foundation
import FoodLedgerDomain

/// `label-photo-serving-v1` (docs/label-photo-ai-prefill-v1.md P10 and 17.4): the outcomes of
/// `pasted-label-serving-v1` for a stored per-serving column and of `pasted-label-serving-v3` for
/// a stored per 100 g or ml column with an exact serving size in the same unit. The frozen pasted
/// policy is keyed by pasted parser versions and pasted evidence, so the photo route owns this
/// method; it reads the photo manifest through the same projection the verifier uses and calls
/// the pasted rules on it, never a copy of them. A parity test over the pasted serving fixtures
/// proves the outcomes are the same.
public enum LabelPhotoServingPolicy {
    public static let version = LabelPhotoManifest.servingVersion

    /// The serving quantity that applies to the selection, or nil.
    public static func serving(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PositiveQuantity? {
        let source = candidate.candidate
        guard input.sourceReleases.contains(where: { $0.sourceReleaseID == source.sourceReleaseID && $0.sourceID.value == LabelPhotoSource.sourceID }),
              let manifest = manifest(input, candidate: candidate) else { return nil }
        return serving(LabelPhotoSource.projection(manifest), basis: source.identity.servingBasis)
    }

    /// The serving for a stored basis, read from the projected manifest by the pasted rules.
    static func serving(_ projected: PastedLabelEvidenceManifest, basis: ResolutionBasis) -> PositiveQuantity? {
        switch basis {
        case let .perServing(serving): serving
        case .per100Grams: PastedLabelServingPolicy.per100Serving(projected, unit: .grams)
        case .per100Millilitres: PastedLabelServingPolicy.per100Serving(projected, unit: .millilitres)
        case .perUnit, .named, .unknown: nil
        }
    }

    public static func applies(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate) != nil
    }

    /// No weight or volume: only servings are offered.
    public static func servingsOnly(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        serving(input, candidate: candidate)?.unit == .count
    }

    /// The servings in one pack, printed exactly or entered by the user, whenever servings convert
    /// through a serving in grams or millilitres. "About" is never a whole pack.
    public static func wholePack(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PastedLabelWholePack? {
        guard let serving = serving(input, candidate: candidate), serving.unit != .count,
              let manifest = manifest(input, candidate: candidate) else { return nil }
        return wholePack(LabelPhotoSource.projection(manifest))
    }

    static func wholePack(_ projected: PastedLabelEvidenceManifest) -> PastedLabelWholePack? {
        if let printed = projected.candidate.servingsPerPack {
            guard !printed.approximate, let count = PastedLabelSource.amount(printed.decimalText), count > 0 else { return nil }
            return PastedLabelWholePack(servings: count, origin: .printed)
        }
        guard let index = projected.corrections.firstIndex(where: { $0.nutrient == PastedLabelManifest.Correction.servingsPerPack }),
              let count = PastedLabelSource.amount(projected.corrections[index].corrected.decimalText), count > 0 else { return nil }
        return PastedLabelWholePack(servings: count, origin: .enteredByYou(correctionIndex: index))
    }

    /// The conversion recorded for n servings, under this method.
    public static func conversion(servings: PositiveQuantity, serving: PositiveQuantity,
                                  candidate: PopulatedFoodCandidate) throws -> QuantityConversionDraft? {
        try PastedLabelServingPolicy.conversion(servings: servings, serving: serving, candidate: candidate, method: version)
    }

    /// Reopen verification of a stored conversion naming this method.
    public static func verifies(_ stored: QuantityConversionVersion, input: PopulatedFoodConfirmation,
                                candidate: PopulatedFoodCandidate) -> Bool {
        guard stored.methodVersion.value == version, let serving = serving(input, candidate: candidate),
              let expected = try? conversion(servings: stored.sourceQuantity, serving: serving, candidate: candidate) else { return false }
        return stored.convertedQuantity == expected.convertedQuantity && stored.sourceReleaseID == expected.sourceReleaseID
            && stored.evidenceID == expected.evidenceID
    }

    /// The photo manifest bound to the candidate through its manifest evidence.
    static func manifest(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> LabelPhotoManifest? {
        guard let evidence = input.evidence.first(where: { candidate.candidate.evidenceIDs.contains($0.evidenceID)
                  && $0.captureMethodVersion.value == LabelPhotoManifest.version }),
              case let .text(payload) = evidence.originalPayload else { return nil }
        return LabelPhotoManifest.decode(Data(payload.value.utf8))
    }
}
