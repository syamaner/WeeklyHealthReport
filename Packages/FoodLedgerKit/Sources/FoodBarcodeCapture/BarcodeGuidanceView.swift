#if os(iOS)
import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public struct BarcodePermissionGuidanceView: View {
    private let guidance: BarcodePermissionGuidance
    private let useGenericSearch: () -> Void

    public init(
        guidance: BarcodePermissionGuidance,
        useGenericSearch: @escaping () -> Void
    ) {
        self.guidance = guidance
        self.useGenericSearch = useGenericSearch
    }

    public var body: some View {
        // A plain stack rather than ContentUnavailableView: inside a Form row its title is held to
        // one line and truncated ("Barcode camera unavailable"). Every line here wraps.
        VStack(alignment: .leading, spacing: 12) {
            Label(guidance.title, systemImage: "camera.fill")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(guidance.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(guidance.genericSearchTitle, action: useGenericSearch)
                .frame(minHeight: 44)
                .accessibilityHint("Continues to populated generic food search")
        }
        .padding(.vertical, 4)
    }
}

public struct BarcodeFallbackGuidanceView: View {
    private let route: BarcodeFallbackRoute
    private let useGenericSearch: (CaptureEvidence) -> Void

    public init(
        route: BarcodeFallbackRoute,
        useGenericSearch: @escaping (CaptureEvidence) -> Void
    ) {
        self.route = route
        self.useGenericSearch = useGenericSearch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Barcode needs a food match").font(.headline)
            Text(route.guidance)
            Button("Use generic search") { useGenericSearch(route.evidence) }
                .accessibilityHint("Keeps the captured barcode evidence")
        }
    }
}
#endif
