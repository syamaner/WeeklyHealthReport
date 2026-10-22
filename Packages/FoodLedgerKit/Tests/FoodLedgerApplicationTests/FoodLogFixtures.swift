import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// Synthetic records for Food Log tests (#197): one product per 100 g with known energy,
/// protein and carbohydrates and unknown fat.
enum FoodLogFixtures {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)
    static let day = "2023-11-14"

    static func id<Tag>(_ number: Int, _ tag: Tag.Type) throws -> LedgerID<Tag> {
        try LedgerID(String(format: "00000000-0000-0000-0000-%012x", number))
    }

    static func nutrients(fatKnown: Bool = false) throws -> NutrientSet {
        let provenance = NutrientProvenance(sourceKind: .manualDeclaration, sourceID: try ExternalIdentifier("physical_package"),
            sourceReleaseID: try ExternalIdentifier("package:fixture-v1"), evidenceID: try id(1, EvidenceTag.self), capturedAt: date)
        let known: [NutrientKey: Double] = [.energyConsumed: 200, .protein: 10, .carbohydrates: 30]
            .merging(fatKnown ? [.fatTotal: 5, .fiber: 10] : [:]) { first, _ in first }
        return try NutrientSet(entries: NutrientKey.allCases.map { key in
            guard let amount = known[key] else { return try NutrientEntry(key: key, value: .unknown(.notDeclared)) }
            return try NutrientEntry(key: key, value: .measured(ExactNutrientValue(amount: amount, unit: key.canonicalUnit,
                sourceValue: .exact(SourceExactNutrientValue(amount: amount, unit: LedgerText(key.canonicalUnit.rawValue), basis: .per100Grams)),
                provenance: [provenance])))
        })
    }

    /// Records with product versions 3 (fat and fibre unknown) and 13 (fat and fibre known), resolutions 5 and 15.
    static func records() throws -> LedgerMutation {
        var mutation = LedgerMutation()
        for (offset, fatKnown) in [(0, false), (10, true)] {
            let identity = try DecisiveIdentity(preparation: PreparationState(kind: .asSold), bone: .notApplicable,
                skin: .notApplicable, drained: .notApplicable, packingMedium: .named(LedgerText("none")),
                fortification: .unfortified, servingBasis: .per100Grams)
            let productID: ProductID = try id(2 + offset, ProductTag.self)
            let productVersionID: ProductVersionID = try id(3 + offset, ProductVersionTag.self)
            mutation.products.append(Product(productID: productID, createdAt: date))
            mutation.productVersions.append(try ProductVersion(productVersionID: productVersionID, productID: productID,
                ordinal: VersionOrdinal(1), name: LedgerText(fatKnown ? "Oats" : "Fixture food"), itemClass: .food,
                packFacts: PackFacts(), identity: identity, evidenceIDs: [try id(1, EvidenceTag.self)], assertionIDs: [], createdAt: date))
            let resolutionID: ResolutionID = try id(4 + offset, ResolutionTag.self)
            mutation.resolutions.append(NutritionResolution(resolutionID: resolutionID, productVersionID: productVersionID,
                basis: .per100Grams, createdAt: date))
            mutation.resolutionVersions.append(try NutritionResolutionVersion(resolutionVersionID: id(5 + offset, ResolutionVersionTag.self),
                resolutionID: resolutionID, ordinal: VersionOrdinal(1), methodVersion: LedgerText("fixture_resolution_v1"),
                sourceReleaseIDs: [try ExternalIdentifier("package:fixture-v1")], nutrients: nutrients(fatKnown: fatKnown), createdAt: date))
        }
        return mutation
    }

    static func log(_ item: Int, version: Int, ordinal: Int = 1, supersedes: Int? = nil, product: Int = 3,
                    resolution: Int = 5, value: Double = 150, unit: QuantityUnit = .grams,
                    occurredAt: Date = date, removed: Int? = nil, conversion: Int? = nil,
                    plate: Int? = nil, declaration: EdibleWeightDeclaration? = nil,
                    createdAt: Date = date) throws -> LogItemVersion {
        try LogItemVersion(logItemVersionID: id(version, LogItemVersionTag.self), logItemID: id(item, LogItemTag.self),
            ordinal: VersionOrdinal(ordinal), supersedesLogItemVersionID: try supersedes.map { try id($0, LogItemVersionTag.self) },
            occurredAt: occurredAt, reportingDate: LedgerText(day),
            composition: try removed.map { .removed(try id($0, LogItemVersionTag.self)) } ?? .product(id(product, ProductVersionTag.self)),
            edibleQuantity: PositiveQuantity(value: value, unit: unit),
            weightDeclaration: declaration,
            quantityConversionVersionID: try conversion.map { try id($0, QuantityConversionVersionTag.self) },
            plateWeightVersionID: try plate.map { try id($0, PlateWeightVersionTag.self) },
            originalResolutionVersionID: id(5, ResolutionVersionTag.self),
            effectiveResolutionVersionID: id(resolution, ResolutionVersionTag.self),
            correctionReason: supersedes == nil ? nil : LedgerText("Fixture change"), createdAt: createdAt)
    }
}
