import FoodLedgerDomain
import Foundation

/// Identity mapping `pasted-label-identity-v2` (`docs/pasted-nutrition-label-uk-english-v1-p2.md`
/// section 4): v1's markers plus the closed UK list. A header carrying any of them is not the
/// food as sold. Read only by the UK development harness until P5; the product's `classify` keeps
/// `PastedLabelBasisState` (v1), and no manifest records v2 before then. The UK reader's guard G3
/// holds the same word list (`UKVocabulary.identityWordMarkers`), kept equal by a parity test.
public enum PastedLabelBasisStateV2 {
    public static let version = "pasted-label-identity-v2"
    /// Whole words, matched case-insensitively, so `unprepared`, `uncooked` and `serving` do not match.
    public static let wordMarkers: [String] = PastedLabelBasisState.wordMarkers + [
        "preparation", "reconstituted", "reconstitution", "rehydrated", "diluted", "dilution",
        "cooked", "cooking", "baked", "grilled", "fried", "microwaved", "heated", "boiled", "steamed", "roasted", "toasted",
        "brewed", "infused", "soaked", "poached", "braised", "barbecued", "made", "served", "instructions", "consumed", "with",
    ]
    /// Matched as substrings: v1's Traditional Chinese markers, and `+` (something added).
    public static let substringMarkers: [String] = PastedLabelBasisState.substringMarkers + ["+"]

    public static func isAsSold(_ candidate: PastedLabelManifest.Candidate) -> Bool {
        let texts = candidate.headers.flatMap { [$0.printedText, $0.servingConversion ?? ""] }
        return !texts.contains(where: marks)
    }

    public static func marks(_ text: String) -> Bool {
        if substringMarkers.contains(where: text.contains) { return true }
        let words = text.lowercased().split { !$0.isLetter }
        return words.contains { wordMarkers.contains(String($0)) }
    }
}
