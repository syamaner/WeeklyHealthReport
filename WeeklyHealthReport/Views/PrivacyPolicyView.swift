import SwiftUI

enum PrivacyPolicy {
    static let publicURL = URL(string: "https://github.com/syamaner/WeeklyHealthReport/blob/main/docs/privacy-policy.txt")!

    static func bundledText(bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: "privacy-policy", withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// The bundled policy split into sections at its heading lines (docs/openrouter-single-consent-v1-amendment.md
/// O1.3): a heading is a non-empty line with no full stop and no colon, preceded by a blank line or the
/// start of the file and followed by a blank line. The lines before the first blank line (the title and
/// the Effective line) are the title block, never matched as a heading. The text is unchanged by the split.
enum PrivacyPolicySections {
    static let openRouterHeading = "OpenRouter"

    struct Section: Equatable, Identifiable {
        let heading: String
        let body: String
        var id: String { heading }
    }

    struct Split: Equatable {
        let titleBlock: String
        let sections: [Section]
    }

    static func split(_ text: String) -> Split {
        let lines = text.components(separatedBy: "\n")
        guard let firstBlank = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return Split(titleBlock: text, sections: [])
        }
        let titleBlock = lines[..<firstBlank].joined(separator: "\n")
        func isBlank(_ index: Int) -> Bool { lines[index].trimmingCharacters(in: .whitespaces).isEmpty }
        func isHeading(_ index: Int) -> Bool {
            let line = lines[index]
            guard index > firstBlank, !isBlank(index), !line.contains("."), !line.contains(":"),
                  isBlank(index - 1), index + 1 < lines.count, isBlank(index + 1) else { return false }
            return true
        }
        var sections: [Section] = []
        var heading: String?
        var body: [String] = []
        func close() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if let heading { sections.append(Section(heading: heading, body: text)) }
            else if !text.isEmpty { sections.append(Section(heading: "", body: text)) }
        }
        for index in firstBlank..<lines.count {
            if isHeading(index) {
                close()
                heading = lines[index]; body = []
            } else {
                body.append(lines[index])
            }
        }
        close()
        return Split(titleBlock: titleBlock, sections: sections)
    }
}

struct PrivacyPolicyView: View {
    private let policy = try? PrivacyPolicy.bundledText()
    /// The section heading to scroll to, such as `OpenRouter` from Settings › OpenRouter.
    var anchor: String?

    init(anchor: String? = nil) { self.anchor = anchor }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let policy {
                        let split = PrivacyPolicySections.split(policy)
                        Text(split.titleBlock).textSelection(.enabled)
                        ForEach(split.sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                if !section.heading.isEmpty {
                                    Text(section.heading).font(.headline).accessibilityAddTraits(.isHeader)
                                }
                                Text(section.body).textSelection(.enabled)
                            }
                            .id(section.heading)
                        }
                    } else {
                        Text("The offline privacy policy could not be loaded. Open the published policy below.")
                    }
                    Link("Published privacy policy", destination: PrivacyPolicy.publicURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .onAppear {
                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
            }
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
