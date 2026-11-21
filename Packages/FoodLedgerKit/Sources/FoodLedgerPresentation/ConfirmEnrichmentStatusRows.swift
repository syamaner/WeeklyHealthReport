import FoodLedgerApplication
import SwiftUI

/// The loading row with Stop, the one quiet note, and the Ask again row (with O1's blocked row when the
/// switch or key blocks it), for one part (docs/confirm-enrichment-openrouter-v1.md sections 6 and 8).
/// Log is never affected.
struct ConfirmEnrichmentStatusRows: View {
    @ObservedObject var controller: ConfirmEnrichmentController
    let part: ConfirmEnrichmentPart

    var body: some View {
        if controller.loading.contains(part) {
            HStack {
                ProgressView().accessibilityHidden(true)
                Text(ConfirmEnrichmentText.loading).font(.subheadline)
                Spacer()
                Button(ConfirmEnrichmentText.stop) { controller.stop() }
                    .buttonStyle(.borderless).frame(minHeight: 44)
                    .accessibilityLabel("\(ConfirmEnrichmentText.stop) looking for suggestions")
                    .accessibilityIdentifier("confirmEnrichment.stop")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("confirmEnrichment.loading")
        }
        if part == .nutrients, let note = controller.note {
            Label(note, systemImage: "info.circle").font(.caption).accessibilityLabel(note)
                .accessibilityIdentifier("confirmEnrichment.note")
        }
        if controller.offersAskAgain(part) {
            Button(ConfirmEnrichmentText.askAgain) { controller.askAgain(part) }
                .buttonStyle(.borderless).frame(minHeight: 44)
                .accessibilityLabel(part == .details ? "\(ConfirmEnrichmentText.askAgain) for food details"
                                    : "\(ConfirmEnrichmentText.askAgain) for estimated values")
                .accessibilityIdentifier("confirmEnrichment.askAgain.\(part.rawValue)")
            if let blocked = controller.blocked {
                Label(OpenRouterBlockedText.text(blocked), systemImage: "exclamationmark.circle").font(.caption)
            }
        }
    }
}
