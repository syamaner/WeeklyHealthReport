import SwiftUI

/// Home's "Health · today so far" card (#199, today_so_far_health_v1). Renders
/// `TodaySoFarHealthCard` presentation; a new highlight touches only the
/// health feature's files, never `HomeView` or `HomeCardID`.
struct TodaySoFarHealthCardView: View {
    @ObservedObject var model: TodaySoFarHealthModel

    var body: some View {
        let card = TodaySoFarHealthCard.make(projection: model.projection, windowFailed: model.windowFailed)
        Section {
            switch card.content {
            case .unavailable(let message):
                Label(message, systemImage: "heart.slash")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                Button("Try again") { Task { await model.handle(.pullToRefresh) } }
            case .rows(let rows):
                ForEach(rows) { row in
                    TodaySoFarHealthRowView(row: row)
                }
                if rows.contains(where: { $0.status == .failed }) {
                    Button("Try again") { Task { await model.handle(.pullToRefresh) } }
                }
            }
            NavigationLink(value: AppRoute.healthReport) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.linkTitle)
                    Text(Self.linkSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(Self.healthHint)
            .accessibilityIdentifier("homeHealthSummaries")
        } header: {
            // A plain header (owner decision F, 13 October 2026): the one way to Health is the
            // "Health summaries" row below.
            Text(Self.title)
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.footer)
                if let asOf = card.asOf { Text(asOf) }
            }
        }
    }

    static let title = "Health · today so far"
    static let linkTitle = "Health summaries"
    static let linkSubtitle = "Completed days"
    static let healthHint = "Opens the Health summaries for completed days"

    /// The card as plain text for Today's Full Page: the same rows, footer and
    /// "As of" time; the links are controls and are omitted.
    static func fullPageSection(_ card: TodaySoFarHealthCard) -> TodayFullPageDocument.Section {
        typealias Row = TodayFullPageDocument.Row
        let rows: [Row]
        switch card.content {
        case .unavailable(let message), .failed(let message):
            rows = [Row(value: message)]
        case .rows(let healthRows):
            rows = healthRows.map { Row($0.title, value: $0.status == .loading ? "Loading" : $0.value) }
        }
        let footer = ([card.footer] + [card.asOf].compactMap { $0 }).joined(separator: "\n")
        return .init(title: title, rows: rows, footer: footer)
    }

    /// `readsHealthData` is false only in hosted unit tests, where the app shell
    /// also skips its report refresh: the card then neither presents the Health
    /// sheet nor reads HealthKit from the test host process.
    static func feature(model: TodaySoFarHealthModel, readsHealthData: Bool) -> HomeFeature {
        HomeFeature(
            cards: [HomeCard(id: .healthToday, fullPage: { _ in
                fullPageSection(TodaySoFarHealthCard.make(projection: model.projection, windowFailed: model.windowFailed))
            }) { _ in AnyView(TodaySoFarHealthCardView(model: model)) }],
            refresh: { trigger in
                guard readsHealthData else { return }
                await model.handle(Self.trigger(for: trigger))
            }
        )
    }

    static func trigger(for trigger: HomeRefreshTrigger) -> TodaySoFarHealthModel.Trigger {
        switch trigger {
        case .appeared: .homeAppeared
        case .becameActive: .becameActive
        case .significantTimeChange: .significantTimeChange
        case .calendarDayChanged: .calendarDayChanged
        case .pullToRefresh: .pullToRefresh
        }
    }
}

private struct TodaySoFarHealthRowView: View {
    let row: TodaySoFarHealthRow

    var body: some View {
        LabeledContent {
            if row.status == .loading {
                ProgressView()
            } else {
                Text(row.value)
                    .monospacedDigit()
                    .foregroundStyle(row.status == .available ? .primary : .secondary)
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            Text(row.title)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}
