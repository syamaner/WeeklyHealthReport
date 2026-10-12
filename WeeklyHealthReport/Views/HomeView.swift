import SwiftUI
import UIKit

/// Home's card slots in wireframe order. A new card kind is a new feature and
/// adds one case; a new health highlight never changes this type (#199).
enum HomeCardID: Int, Comparable, CaseIterable {
    case food, addFood, quickAdd, healthToday, notes

    static func < (lhs: HomeCardID, rhs: HomeCardID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What every card can read when Home renders: today's date from the
/// injected clock, refreshed on each Home refresh.
struct HomeCardContext: Equatable {
    let today: Date
}

struct HomeCard: Identifiable {
    let id: HomeCardID
    let content: @MainActor (HomeCardContext) -> AnyView
}

/// Why Home refreshed. Views forward lifecycle events; features decide what to read.
enum HomeRefreshTrigger: Equatable {
    case appeared
    case becameActive
    case significantTimeChange
    case calendarDayChanged
    case pullToRefresh
}

/// One feature's contribution to Home: its cards, any screen-level presentation
/// it owns (sheets, pushed confirmations), and how it refreshes.
struct HomeFeature {
    let cards: [HomeCard]
    var decorate: @MainActor (AnyView) -> AnyView = { $0 }
    var refresh: @MainActor (HomeRefreshTrigger) async -> Void = { _ in }
}

/// Today only. Sorts contributed cards by `HomeCardID` and renders them; it
/// knows no feature (#199 phase plan, "Home cards contributed per feature").
struct HomeView: View {
    let features: [HomeFeature]
    let now: () -> Date
    let calendar: Calendar
    @State private var today: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let context = HomeCardContext(today: today ?? now())
        let form = Form {
            Section {
                Text(Self.header(context.today, calendar: calendar))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("homeDate")
            }
            ForEach(Self.orderedCards(features)) { card in
                card.content(context)
            }
        }
        .accessibilityIdentifier("homeForm")
        .refreshable { await refresh(.pullToRefresh) }
        .onAppear { Task { await refresh(.appeared) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh(.becameActive) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await refresh(.significantTimeChange) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refresh(.calendarDayChanged) }
        }
        features.reduce(AnyView(form)) { view, feature in feature.decorate(view) }
    }

    static func orderedCards(_ features: [HomeFeature]) -> [HomeCard] {
        features.flatMap(\.cards).sorted { $0.id < $1.id }
    }

    static func header(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide))
    }

    private func refresh(_ trigger: HomeRefreshTrigger) async {
        today = now()
        for feature in features {
            await feature.refresh(trigger)
        }
    }
}
