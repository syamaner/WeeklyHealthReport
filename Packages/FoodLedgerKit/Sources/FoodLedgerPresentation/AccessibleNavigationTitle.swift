import SwiftUI

/// Screen titles that stay whole at accessibility text sizes (#308). A large navigation title
/// truncates at AX5 ("Search resu…", "Paste nutriti…"); at accessibility sizes the title moves
/// to the inline bar and may wrap to two lines and scale down, so the whole title is always
/// shown. Standard sizes keep the system title unchanged. The navigation title (back button,
/// VoiceOver) is the same string at every size.
public enum AccessibleNavigationTitle {
    public static func usesInlineTitle(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
    /// Lines the inline title may use before it scales down; never truncated.
    public static let inlineLineLimit = 2
    public static let inlineMinimumScaleFactor: CGFloat = 0.5
}

private struct AccessibleNavigationTitleModifier: ViewModifier {
    let title: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if AccessibleNavigationTitle.usesInlineTitle(at: dynamicTypeSize) {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(AccessibleNavigationTitle.inlineLineLimit)
                            .minimumScaleFactor(AccessibleNavigationTitle.inlineMinimumScaleFactor)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
        } else {
            content.navigationTitle(title)
        }
    }
}

public extension View {
    /// `navigationTitle` that never truncates at accessibility text sizes (#308).
    func accessibleNavigationTitle(_ title: String) -> some View {
        modifier(AccessibleNavigationTitleModifier(title: title))
    }
}

/// The food search field's placeholder (#308). The example does not fit one line at
/// accessibility sizes, where iOS shrinks a placeholder to fit; there the field keeps the plain
/// prompt, which scales with the text, and the example stays in the help text below.
public enum FoodSearchFieldText {
    public static let shortPrompt = "Food and amount"
    public static func prompt(example: String, at size: DynamicTypeSize) -> String {
        size.isAccessibilitySize ? shortPrompt : "\(shortPrompt), e.g. \(example)"
    }
    /// The search chips stack full width at accessibility sizes, so each chip wraps whole words.
    public static func stacksChips(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}
