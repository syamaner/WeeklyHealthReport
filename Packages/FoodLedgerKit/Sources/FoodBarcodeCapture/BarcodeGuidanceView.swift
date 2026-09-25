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
        ContentUnavailableView {
            Label(guidance.title, systemImage: "camera.fill")
        } description: {
            Text(guidance.message)
        } actions: {
            Button(guidance.genericSearchTitle, action: useGenericSearch)
                .accessibilityHint("Continues to populated generic food search")
        }
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
