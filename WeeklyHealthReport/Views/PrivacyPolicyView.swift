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

struct PrivacyPolicyView: View {
    private let policy = try? PrivacyPolicy.bundledText()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(policy ?? "The offline privacy policy could not be loaded. Open the published policy below.")
                    .textSelection(.enabled)
                Link("Published privacy policy", destination: PrivacyPolicy.publicURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
