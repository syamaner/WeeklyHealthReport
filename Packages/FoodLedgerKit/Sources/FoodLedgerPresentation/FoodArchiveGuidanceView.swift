import SwiftUI

public enum FoodArchiveGuidance {
    public static let integrity =
        "Archive hashes check integrity. They do not encrypt or anonymise your food and log data."
    public static let deletion =
        "Deleting local food data does not delete an archive you exported separately."
}

public struct FoodArchiveGuidanceView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Local food archive", systemImage: "archivebox")
                .font(.headline)
            Text(FoodArchiveGuidance.integrity)
            Text(FoodArchiveGuidance.deletion)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Local food archive. " + FoodArchiveGuidance.integrity + " "
                + FoodArchiveGuidance.deletion
        )
    }
}
