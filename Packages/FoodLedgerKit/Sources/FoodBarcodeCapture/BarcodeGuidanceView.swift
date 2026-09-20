#if os(iOS)
import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public struct BarcodePermissionGuidanceView: View {
    private let guidance: BarcodePermissionGuidance
    private let useLabelPhoto: () -> Void
    private let useGenericSearch: () -> Void

    public init(
        guidance: BarcodePermissionGuidance,
        useLabelPhoto: @escaping () -> Void,
        useGenericSearch: @escaping () -> Void
    ) {
        self.guidance = guidance
        self.useLabelPhoto = useLabelPhoto
        self.useGenericSearch = useGenericSearch
    }

    public var body: some View {
        ContentUnavailableView {
            Label(guidance.title, systemImage: "camera.fill")
        } description: {
            Text(guidance.message)
        } actions: {
            Button(guidance.labelPhotoTitle, action: useLabelPhoto)
                .accessibilityHint("Continues to a populated label-photo route")
            Button(guidance.genericSearchTitle, action: useGenericSearch)
                .accessibilityHint("Continues to populated generic food search")
        }
    }
}

public struct BarcodeFallbackGuidanceView: View {
    private let route: BarcodeFallbackRoute
    private let useLabelPhoto: (CaptureEvidence) -> Void
    private let useGenericSearch: (CaptureEvidence) -> Void

    public init(
        route: BarcodeFallbackRoute,
        useLabelPhoto: @escaping (CaptureEvidence) -> Void,
        useGenericSearch: @escaping (CaptureEvidence) -> Void
    ) {
        self.route = route
        self.useLabelPhoto = useLabelPhoto
        self.useGenericSearch = useGenericSearch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No exact local match").font(.headline)
            Text(route.guidance)
            Button(route.labelPhotoTitle) { useLabelPhoto(route.evidence) }
                .accessibilityHint("Keeps the captured barcode evidence")
            Button("Use generic search") { useGenericSearch(route.evidence) }
                .accessibilityHint("Keeps the captured barcode evidence")
        }
    }
}
#endif
