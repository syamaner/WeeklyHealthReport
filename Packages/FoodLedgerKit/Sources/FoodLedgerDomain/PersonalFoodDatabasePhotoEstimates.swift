import Foundation

// Label photo estimates (docs/personal-food-catalogue-off-estimates-v1-proposal.md sections 2.1 to
// 2.3; phase gate docs/personal-food-catalogue-off-estimates-v1-phase.md sections 2 and 4): the rules
// of a `product_dataset_photo` record in a `personal-food-catalogue-estimates-v3` file. They mirror
// the skill's `estimates_v3.py` rule for rule, so both give the same codes in the same order.

enum PersonalFoodDatabasePhotoRules {
    typealias R = PersonalFoodDatabaseRules
    static let token = PFDText("product_dataset_photo")
    static let prefix = Array("https://images.openfoodfacts.org/images/products/".utf8)
    static let urlLimit = 2048
    static let stateBases: Set<PFDText> = [PFDText("source_states_it"), PFDText("stated_assumption")]
    static let methods: Set<PFDText> = [PFDText("direct"), PFDText("carried_from_similar_food")]
    static let gtinPrefix = Array("off:gtin:".utf8)

    /// The barcode of a photo address, or nil when the address is not exactly the photo form: the
    /// fixed prefix, one or more all-digit segments, one file name; printable ASCII, no query or
    /// fragment. Byte for byte as `estimates_v3.barcode`.
    static func barcode(_ reference: PFDText?) -> [UInt8]? {
        guard let b = reference?.bytes, b.starts(with: prefix), b.count <= urlLimit,
              b.allSatisfy({ (0x21...0x7e).contains($0) }), !b.contains(UInt8(ascii: "?")),
              !b.contains(UInt8(ascii: "#")) else { return nil }
        let parts = b.dropFirst(prefix.count).split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false)
        guard parts.count >= 2, let last = parts.last, !last.isEmpty,
              parts.dropLast().allSatisfy({ !$0.isEmpty && $0.allSatisfy(R.isDigit) }) else { return nil }
        return parts.dropLast().flatMap { Array($0) }
    }

    static func stripZeros(_ digits: [UInt8]) -> [UInt8] {
        let trimmed = Array(digits.drop { $0 == UInt8(ascii: "0") })
        return trimmed.isEmpty ? [UInt8(ascii: "0")] : trimmed
    }

    /// The digits of every `off:gtin:` record the entry cites in its labels, leading zeros removed.
    static func entryBarcodes(_ item: PFDValue) -> Set<[UInt8]> {
        var out = Set<[UInt8]>()
        for (_, v) in item["label_nutrients"]?.members ?? [] {
            guard let rid = v["record_id"]?.text?.bytes, rid.starts(with: gtinPrefix) else { continue }
            let digits = Array(rid.dropFirst(gtinPrefix.count))
            if !digits.isEmpty, digits.allSatisfy(R.isDigit) { out.insert(stripZeros(digits)) }
        }
        return out
    }

    /// Sections 2.1 and 2.2: true when any rule fails (one `photo-fields`).
    static func recordFails(_ rec: PFDValue) -> Bool {
        let digestOK = rec["source_digest"]?.text.map { R.isHex64($0.bytes) } ?? false
        let dateOK = rec["retrieved_on"]?.text.flatMap { PersonalFoodDatabaseDate(ascii: $0.bytes) } != nil
        return rec["composition_source"]?.isNull != true || rec["page_access"]?.text != PFDText("direct_read")
            || barcode(rec["source_reference"]?.text) == nil || !digestOK || !dateOK
            || !(rec["state_basis"]?.text.map(stateBases.contains) ?? false)
            || !(rec["method"]?.text.map(methods.contains) ?? false) || rec["derivation"]?.isNull != true
    }

    /// Section 2.3: `direct` only for a photo of a barcode the entry cites.
    static func relationCodes(record rec: PFDValue, item: PFDValue) -> [PersonalFoodDatabaseRuleCode] {
        guard rec["method"]?.text == PFDText("direct") else { return [] }
        if let code = barcode(rec["source_reference"]?.text), entryBarcodes(item).contains(stripZeros(code)) { return [] }
        return [.photoRelation]
    }

    /// A v3 file holds at least one photo estimate (cited evidence of the token).
    static func hasPhotoEstimate(_ doc: PFDValue) -> Bool {
        var cited = Set<PFDText>()
        for item in doc["items"]?.items ?? [] {
            for (_, v) in item["estimated_nutrients"]?.members ?? [] {
                if let rid = v["evidence_id"]?.text { cited.insert(rid) }
            }
        }
        return (doc["estimate_evidence"]?.items ?? []).contains {
            $0["source_type"]?.text == token && ($0["id"]?.text.map(cited.contains) ?? false)
        }
    }
}

/// The photo address and record rules for code outside the codec (the capture manifest and the daily
/// food export), so all three read one definition.
public enum PersonalFoodDatabasePhotoAddress {
    /// True when `reference` is exactly the label photo address form (phase gate section 2.1).
    public static func isPhoto(_ reference: String) -> Bool {
        PersonalFoodDatabasePhotoRules.barcode(PFDText(bytes: Array(reference.utf8))) != nil
    }

    /// The typed form of sections 2.1 and 2.2, for an evidence record that names the token.
    public static func recordIsValid(_ e: PersonalFoodDatabaseEstimateEvidence) -> Bool {
        guard e.sourceType == .productDatasetPhoto else { return true }
        let digestOK = e.sourceDigest.map { PersonalFoodDatabaseRules.isHex64(Array($0.utf8)) } ?? false
        return e.compositionSource == nil && e.pageAccess == .directRead && isPhoto(e.sourceReference) && digestOK
            && e.retrievedOn != nil && e.stateBasis != .unknown && (e.method == .direct || e.method == .carriedFromSimilarFood)
            && e.derivation == nil && e.quality.rank <= PersonalFoodDatabaseEstimateQuality.medium.rank
    }
}
