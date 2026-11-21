import FoodLedgerApplication
import FoodLedgerDomain
import Foundation

/// Confirm enrichment's Your food database read port (docs/confirm-enrichment-openrouter-v1.md section 7):
/// the category, product type and state of one entry, read locally from the active release's decoded
/// snapshot by the candidate's record ID. No network, no file read of its own; nil when no release is
/// loaded or the entry is not in it.
public struct ActiveReleaseEntryReader: PersonalFoodDatabaseEntryReading {
    private let index: PersonalFoodDatabaseIndex

    public init(index: PersonalFoodDatabaseIndex) { self.index = index }

    public func descriptionFields(recordID: ExternalIdentifier) -> PersonalFoodDescriptionFields? {
        guard let entry = index.snapshot()?.file.entries.first(where: { $0.id == recordID.value }) else { return nil }
        return Self.fields(entry)
    }

    /// The fields of one entry: closed tokens only, the state left out when unknown, and CE-D5's
    /// reviewed-facts flag from `identity_facts`.
    public static func fields(_ entry: PersonalFoodDatabaseEntry) -> PersonalFoodDescriptionFields {
        PersonalFoodDescriptionFields(category: entry.category.rawValue, productType: entry.productType.rawValue,
                                      state: entry.state == .unknown ? nil : entry.state.rawValue,
                                      hasCatalogueFacts: entry.identityFacts != nil)
    }
}
