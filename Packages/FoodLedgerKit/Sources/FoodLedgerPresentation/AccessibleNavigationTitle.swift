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

    /// At accessibility sizes the query wraps onto more lines instead of truncating
    /// ("3 pieces ban…", #315); standard sizes keep the one-line field.
    public static func wrapsQuery(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
    /// Lines a wrapping query may grow to before it scrolls.
    public static let wrappedQueryLineLimit = 1...6

    /// A wrapping field takes Return as a line break; the query is one line, so a typed or pasted
    /// line break submits the text before it joined with spaces. Nil when there is no line break.
    public static func submittedQuery(_ text: String) -> String? {
        guard text.contains(where: \.isNewline) else { return nil }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The submission for the field as shown: only the wrapping field (accessibility sizes) takes
    /// Return as a line break, so at standard sizes a paste never starts a search.
    public static func submittedQuery(_ text: String, at size: DynamicTypeSize) -> String? {
        wrapsQuery(at: size) ? submittedQuery(text) : nil
    }
}

/// The food and amount field on Add food and Search results. At accessibility sizes the query
/// wraps instead of truncating (#315), and the prompt is drawn as wrapping text because a
/// multi-line field truncates its placeholder; standard sizes keep the one-line system field.
public struct FoodQueryField: View {
    private let prompt: String
    @Binding private var text: String
    private let submit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(prompt: String, text: Binding<String>, submit: @escaping () -> Void) {
        self.prompt = prompt; _text = text; self.submit = submit
    }

    public var body: some View {
        Group {
            if FoodSearchFieldText.wrapsQuery(at: dynamicTypeSize) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(prompt).foregroundStyle(.tertiary).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextField("", text: $text, axis: .vertical).lineLimit(FoodSearchFieldText.wrappedQueryLineLimit)
                }
            } else {
                TextField(prompt, text: $text)
            }
        }
        .accessibilityLabel(FoodSearchFieldText.shortPrompt)
        .submitLabel(.search)
        .onSubmit(submit)
        .onChange(of: text) { _, value in
            guard let submitted = FoodSearchFieldText.submittedQuery(value, at: dynamicTypeSize) else { return }
            text = submitted
            submit()
        }
    }
}

/// An entry route row's label (#315). At accessibility sizes the icon sits above the title, so the
/// title has the full row width and never breaks mid-word ("Favour-" / "ites"); standard sizes
/// keep the system icon-and-title label.
public struct RouteRowLabel: View {
    private let title: String
    private let systemImage: String
    private let subtitle: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ title: String, systemImage: String, subtitle: String? = nil) {
        self.title = title; self.systemImage = systemImage; self.subtitle = subtitle
    }

    public static func stacks(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

    public var body: some View {
        if Self.stacks(at: dynamicTypeSize) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage).accessibilityHidden(true)
                text
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            Label { text } icon: { Image(systemName: systemImage) }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
