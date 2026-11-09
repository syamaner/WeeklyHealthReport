import FoodLedgerDomain
import Foundation

/// Identity mapping `pasted-label-identity-v3` (`docs/pasted-nutrition-label-uk-english-v2-p1.md`
/// section 4): identity v2's markers, unchanged, plus rule I1, compound cooking words. A header
/// carrying any of them is not the food as sold. Read only by the UK development harness until P5;
/// the product's `classify` keeps `PastedLabelBasisState` (v1). Identity v2 stays as pinned. The UK
/// reader's guard G3 holds the same lists (`UKVocabulary`), kept equal by a parity test.
public enum PastedLabelBasisStateV3 {
    public static let version = "pasted-label-identity-v3"
    /// Identity v2's whole-word markers.
    public static let wordMarkers: [String] = PastedLabelBasisStateV2.wordMarkers
    /// Identity v2's substring markers.
    public static let substringMarkers: [String] = PastedLabelBasisStateV2.substringMarkers
    /// I1: a single letter run that is exactly one of these prefixes followed by one of the cooking
    /// words, such as `ovenbaked` or `airfried`. Hyphenated forms are already v2 whole words.
    public static let compoundPrefixes: [String] = ["oven", "pan", "air", "deep", "shallow", "stir"]
    public static let compoundCookingWords: [String] = [
        "baked", "cooked", "fried", "grilled", "roasted", "toasted", "microwaved", "heated", "boiled", "steamed",
    ]

    public static func isAsSold(_ candidate: PastedLabelManifest.Candidate) -> Bool {
        let texts = candidate.headers.flatMap { [$0.printedText, $0.servingConversion ?? ""] }
        return !texts.contains(where: marks)
    }

    public static func marks(_ text: String) -> Bool {
        if PastedLabelBasisStateV2.marks(text) { return true }
        return text.lowercased().split { !$0.isLetter }.contains { isCompoundCookingWord(String($0)) }
    }

    /// I1 on one letter run, already lower-cased.
    public static func isCompoundCookingWord(_ word: String) -> Bool {
        compoundPrefixes.contains { prefix in
            word.hasPrefix(prefix) && compoundCookingWords.contains(String(word.dropFirst(prefix.count)))
        }
    }
}
