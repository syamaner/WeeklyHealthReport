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
            case .rows(let rows):
                ForEach(rows) { row in
                    TodaySoFarHealthRowView(row: row)
                }
                if rows.contains(where: { $0.status == .failed }) {
                    Button("Try again") { Task { await model.handle(.pullToRefresh) } }
                }
            }
            NavigationLink("Health", value: AppRoute.healthReport)
                .accessibilityHint("Opens the Health summaries for completed days")
        } header: {
            Text("Health · today so far")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.footer)
                if let asOf = card.asOf { Text(asOf) }
            }
        }
    }

    static func feature(model: TodaySoFarHealthModel, requestsAuthorization: Bool) -> HomeFeature {
        HomeFeature(
            cards: [HomeCard(id: .healthToday) { _ in AnyView(TodaySoFarHealthCardView(model: model)) }],
            refresh: { trigger in
                await model.handle(Self.trigger(for: trigger, requestsAuthorization: requestsAuthorization))
            }
        )
    }

    /// Hosted unit tests must not present the Health sheet, so they refresh without it.
    static func trigger(for trigger: HomeRefreshTrigger, requestsAuthorization: Bool) -> TodaySoFarHealthModel.Trigger {
        switch trigger {
        case .appeared: requestsAuthorization ? .homeAppeared : .becameActive
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
