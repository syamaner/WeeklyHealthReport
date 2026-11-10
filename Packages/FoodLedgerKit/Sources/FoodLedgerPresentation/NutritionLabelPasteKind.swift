/// What a tap of Paste on the Nutrition label screen loaded (docs/nutrition-label-entry-v1.md
/// 3.3): decided from what was loaded, never from what it says. Pure Swift, no framework.
public enum NutritionLabelPasteKind: Equatable, Sendable {
    /// An image and no usable text: the image goes to the label photo route.
    case image
    /// Usable text and no image: the text goes to the pasted-label screen.
    case text
    /// Both: the user chooses (owner decision Q2, 10 November 2026).
    case both
    /// Neither: said inline.
    case neither

    public static func classify(hasImage: Bool, hasText: Bool) -> NutritionLabelPasteKind {
        switch (hasImage, hasText) {
        case (true, true): .both
        case (true, false): .image
        case (false, true): .text
        case (false, false): .neither
        }
    }

    /// Whether the first plain-text item is usable: not empty once whitespace is trimmed. The trim
    /// is only for this test; the text itself is routed unchanged.
    public static func hasUsableText(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.allSatisfy(\.isWhitespace)
    }
}
