/// Every string of the Nutrition label entry (docs/nutrition-label-entry-v1.md section 7). British
/// spelling, plain language, no emoji. The photo and text screens keep their own copy.
public enum NutritionLabelEntryText {
    public static let addFoodRow = "Nutrition label"
    public static let title = "Nutrition label"
    public static let addFoodRowSubtitlePhotos = "Photo, screenshot or pasted text. Photos: Taiwan labels (營養標示), read by AI; you check every value."
    public static let addFoodRowSubtitleTextOnly = "Paste or type the label text. Read on this device."
    public static let photoSectionTitle = "Photo or screenshot"
    public static let photoFooter = "Taiwan labels only. The part you crop is sent to OpenRouter to be read. Nothing else is sent."
    public static let pasteSectionTitle = "Paste"
    public static let pasteFooterPhotos = "Paste a screenshot of a label, or its text. Text is read on this device."
    public static let pasteFooterTextOnly = "Paste the label text. Reading label photos is not available in this version."
    public static let typeOrPaste = "Type or paste text"
    public static let loading = "Reading the clipboard…"
    public static let imageFailed = "The pasted image could not be opened. Nothing was sent."
    public static let readText = "Read the text on this device"
    public static let readImage = "Read the image with AI"
    public static let nothing = "The clipboard has no label image or text."

    /// The Add food row's subtitle, keyed only on the photo route's mode (3.1), never its blockers.
    public static func addFoodRowSubtitle(photosEnabled: Bool) -> String {
        photosEnabled ? addFoodRowSubtitlePhotos : addFoodRowSubtitleTextOnly
    }
}
