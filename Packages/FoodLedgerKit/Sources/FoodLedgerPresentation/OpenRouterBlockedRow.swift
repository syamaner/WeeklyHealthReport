import FoodLedgerApplication
import SwiftUI

/// The copy of the one compact blocked row (docs/openrouter-single-consent-v1-amendment.md O1.4).
/// It is not a warning about egress; it is the place the action is blocked.
public enum OpenRouterBlockedText {
    public static let switchOff = "Turn on OpenRouter in Settings to use this."
    public static let noKey = "Add your OpenRouter key in Settings."
    public static let keyNotValidated = "Validate your OpenRouter key in Settings."
    public static let link = "OpenRouter settings"

    public static func text(_ reason: OpenRouterBlockedReason) -> String {
        switch reason {
        case .switchOff: switchOff
        case .noKey: noKey
        case .keyNotValidated: keyNotValidated
        }
    }
}

/// One row in place of a journey's send action, with one link to Settings › OpenRouter.
public struct OpenRouterBlockedRow: View {
    private let reason: OpenRouterBlockedReason
    private let identifier: String
    private let openSettings: () -> Void

    public init(_ reason: OpenRouterBlockedReason, identifier: String, openSettings: @escaping () -> Void) {
        self.reason = reason; self.identifier = identifier; self.openSettings = openSettings
    }

    public var body: some View {
        Label(OpenRouterBlockedText.text(reason), systemImage: "exclamationmark.circle").accessibilityIdentifier(identifier)
        Button(OpenRouterBlockedText.link, action: openSettings).frame(minHeight: 44)
            .accessibilityIdentifier(identifier + ".settings")
    }
}
