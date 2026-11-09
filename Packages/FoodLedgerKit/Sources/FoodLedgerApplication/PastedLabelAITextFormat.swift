import Foundation

/// The text route's format step (docs/pasted-label-ai-text-v1.md 4.7, revision 10). The frozen
/// `pasted-label-format-inference-v1` is called unchanged first; this step adds one closed rule
/// on top of it, because a bilingual Taiwan panel (`熱量 Calories`, `鈉 Sodium`) is read by the
/// model as `mixed`, which the frozen inference declines as `format_ambiguous`.
///
/// The rule: a `mixed` candidate whose sent text prints the Taiwan mandatory title `營養標示`
/// (traditional script) is a Taiwan panel. Nothing else changes: `unknown` stays ambiguous, a
/// `mixed` text without the title stays ambiguous, English stays with the frozen inference, and
/// the gate still runs every Taiwan rule, G1 simplified Chinese included. It never reads a value.
public enum PastedLabelAITextFormat {
    public static let version = "pasted-label-ai-text-format-v1"

    /// The Taiwan mandatory panel title, as printed in traditional script.
    public static let taiwanTitle = "營養標示"

    /// Whether a candidate the frozen inference found ambiguous, with the model's language
    /// `mixed`, is a Taiwan panel by the sent text.
    public static func mixedIsTaiwan(language: String, text: String) -> Bool {
        language == "mixed" && text.contains(taiwanTitle)
    }
}
