import Foundation
import FoodLedgerDomain

/// Where one stored value came from (`docs/pasted-nutrition-label-v1.md` sections 2.3 and 3.5):
/// the single projection every surface uses, so Confirm, the saved entry, the misread report and
/// Developer tools cannot disagree. A bound is a value shape that any of the first four origins
/// can carry; it is not an origin of its own.
public enum NutrientValueOrigin: Equatable, Hashable, Sendable {
    public enum Unknown: String, Sendable {
        /// A mandatory row the reader did not find (a G3 or G4 flag still shown).
        case notRead = "not_read"
        /// The label does not print it.
        case notStated = "not_stated"
    }

    case printed
    /// Calculated from a printed value under an allow-listed rule (`kj_to_kcal_v1`,
    /// `salt_to_sodium_v1`); never shown as printed.
    case calculated(rule: String)
    case correctedByYou
    case enteredByYou
    case unknown(Unknown)

    /// The origin of a stored pasted-label value, from its provenance, the one calculated
    /// predicate (`NutrientDerivation`) and the manifest's correction records and flags. Only
    /// the manifest decides between "not read" and "not stated".
    public static func project(_ value: NutrientValue, key: NutrientKey, manifest: PastedLabelManifest) -> NutrientValueOrigin {
        if case let .unknown(reason) = value {
            // Printed but unusable as it stands (an ambiguous row or another unit): not read.
            guard reason == .notDeclared else { return .unknown(.notRead) }
            let nutrient = PastedLabelValueOrigins.labelNutrient(key)
            let flagged = manifest.flagsShown.contains { flag in
                guard let nutrient else { return false }
                let concerned = LabelReading.Flag(code: flag.code, concerns: flag.concerns)
                return concerned.nutrient == nutrient && (concerned.headerID == nil || concerned.headerID == manifest.storedHeaderID)
            }
            return .unknown(flagged ? .notRead : .notStated)
        }
        for provenance in value.provenance where provenance.sourceKind == .manualDeclaration {
            if let index = correctionIndex(provenance.manifestReference?.value), manifest.corrections.indices.contains(index) {
                return manifest.corrections[index].kind == .corrected ? .correctedByYou : .enteredByYou
            }
        }
        for provenance in value.provenance {
            if let transform = provenance.transforms.first(where: NutrientDerivation.calculatedTransform) {
                return .calculated(rule: transform.transformID.value)
            }
        }
        return .printed
    }

    /// The correction index named by a `manifest-sha256=…;correction=<index>` reference.
    static func correctionIndex(_ reference: String?) -> Int? {
        guard let reference, let range = reference.range(of: ";correction=") else { return nil }
        return Int(reference[range.upperBound...])
    }
}

/// The origins of a pasted label's stored nutrients, and the stored manifest of an entry.
public enum PastedLabelValueOrigins {
    /// The reader key a ledger key is stored from (`energy_kcal` for energy), if any.
    public static func labelNutrient(_ key: NutrientKey) -> String? {
        PastedLabelSource.ledgerKeys.first { $0.value == key }?.key
    }

    /// Every ledger key, in catalogue order, with its origin.
    public static func origins(_ nutrients: NutrientSet, manifest: PastedLabelManifest) -> [NutrientKey: NutrientValueOrigin] {
        Dictionary(uniqueKeysWithValues: nutrients.entries.map { ($0.key, NutrientValueOrigin.project($0.value, key: $0.key, manifest: manifest)) })
    }

    /// The pasted-label manifest a candidate's evidence carries, or nil for any other route.
    /// It decodes the stored bytes only; verification is the save and reopen services' job.
    public static func manifest(evidence: [CaptureEvidence], evidenceIDs: [EvidenceID]) -> PastedLabelManifest? {
        guard let stored = evidence.first(where: { evidenceIDs.contains($0.evidenceID)
                  && $0.captureMethodVersion.value == PastedLabelManifest.version }),
              case let .text(payload) = stored.originalPayload else { return nil }
        return PastedLabelManifest.decode(Data(payload.value.utf8))
    }

    /// The manifest of the candidate selected on Confirm, or nil for any other route.
    public static func manifest(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> PastedLabelManifest? {
        guard input.sourceReleases.contains(where: { $0.sourceReleaseID == candidate.candidate.sourceReleaseID
                  && $0.sourceID.value == PastedLabelSource.sourceID }) else { return nil }
        return manifest(evidence: input.evidence, evidenceIDs: candidate.candidate.evidenceIDs)
    }
}
