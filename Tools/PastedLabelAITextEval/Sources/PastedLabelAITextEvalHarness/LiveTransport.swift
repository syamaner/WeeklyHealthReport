import FoodLabelPhotoCapture
import Foundation

/// The live connection of `send --live` (A3, docs/pasted-label-ai-text-v1.md 5.2 item 1, T1 and
/// T4): the shipped transport of the label photo route, unchanged, for both the keyless catalogue
/// GETs and the POST to `https://openrouter.ai/api/v1/chat/completions`, with the key from the
/// environment only. This is the one file in the tool allowed to name that transport
/// (check-boundaries.sh); no file in the tool may load URLs itself.
public enum LiveTransport {
    public static func connection(key: EnvironmentKey) -> SendCommand.Connection {
        .transport(OpenRouterTransport(), keys: key)
    }
}
