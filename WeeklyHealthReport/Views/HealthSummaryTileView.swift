import SwiftUI

/// Renders one summary tile. Values and styles come verbatim from report
/// rows; the style changes emphasis only and never carries meaning by colour
/// alone (failures also read "Could not read").
struct HealthSummaryTileView: View {
    let tile: HealthSummaryTile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.title)
                .font(.subheadline.weight(.semibold))
            if let label = tile.primary.label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            value(tile.primary, font: .title3)
            ForEach([tile.detail, tile.trend].compactMap { $0 }) { detail in
                VStack(alignment: .leading, spacing: 0) {
                    if let label = detail.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    value(detail, font: .caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("health.tile.\(tile.kind.rawValue)")
    }

    @ViewBuilder
    private func value(_ row: ReportDocument.Row, font: Font) -> some View {
        switch row.style {
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                Text(row.value).font(font).foregroundStyle(.secondary)
            }
        case .standard:
            Text(row.value).font(font).monospacedDigit()
        case .secondary, .note:
            Text(row.value).font(font).foregroundStyle(.secondary)
        case .failure:
            // An Apple Health failure is explained once by the screen's banner (#308),
            // so the tile states it quietly; the food log failure keeps red.
            Text(row.value).font(font).foregroundStyle(row.isExplainedByHealthBanner ? .secondary : Color.red)
        }
    }

    private var accessibilityText: String {
        var parts = [tile.title]
        for row in [tile.primary, tile.detail, tile.trend].compactMap({ $0 }) {
            if let label = row.label {
                parts.append("\(label): \(row.value)")
            } else {
                parts.append(row.value)
            }
        }
        return parts.joined(separator: ". ")
    }
}
