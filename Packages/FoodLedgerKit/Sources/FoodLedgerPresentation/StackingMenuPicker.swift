import SwiftUI

/// The layout rule shared by every `StackingMenuPicker`.
public enum StackingMenuPickerLayout {
    /// Accessibility text sizes put the title above a full-width value that wraps, since the
    /// standard row truncates long values such as "Keep populated basis" (#285) or
    /// "Kitchen scale" (#337).
    public static func stacks(at size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// A menu picker. At standard sizes it is the system row (title, then the value). At
/// accessibility sizes the title sits above a full-width menu button whose value wraps, with a
/// 44 pt target, and VoiceOver reads the title as the label and the chosen option as the value.
struct StackingMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        let choices = Picker(title, selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        if StackingMenuPickerLayout.stacks(at: dynamicTypeSize) {
            let current = options.first { $0.0 == selection }?.1 ?? ""
            VStack(alignment: .leading, spacing: 6) {
                Text(title).accessibilityHidden(true)
                Menu {
                    choices.pickerStyle(.inline).labelsHidden()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(current).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(title)
                .accessibilityValue(current)
            }
        } else {
            choices
        }
    }
}
