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
    /// The card's current content as plain text for Today's Full Page; nil for
    /// cards that are only controls (for example Add food).
    var fullPage: @MainActor (HomeCardContext) -> TodayFullPageDocument.Section? = { _ in nil }
    let content: @MainActor (HomeCardContext) -> AnyView
}

/// Today's Full Page: Home's cards as plain text in card order, built from the
/// cards' current content when iOS asks for it. Interactive-only controls are
/// omitted. Presentation only; it never feeds Health's Full Page, Copy all or
/// the Daily JSON export.
struct TodayFullPageDocument: Equatable {
    struct Row: Equatable {
        let label: String?
        let value: String
        /// A secondary line under the label, such as "Includes estimates".
        let note: String?

        init(_ label: String? = nil, value: String, note: String? = nil) {
            self.label = label
            self.value = value
            self.note = note
        }
    }

    struct Section: Equatable {
        let title: String
        let rows: [Row]
        var footer: String? = nil
    }

    static let title = "Today"
    let date: String
    let sections: [Section]
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
    /// Reports the day of each refresh, so Today's Full Page dates its
    /// document with the same day as the header and the cards it renders.
    var dayRefreshed: @MainActor (Date) -> Void = { _ in }
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

    /// Today's Full Page from the same features and card order as the screen.
    static func fullPageDocument(
        _ features: [HomeFeature],
        today: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> TodayFullPageDocument {
        let context = HomeCardContext(today: today)
        return TodayFullPageDocument(
            date: header(today, calendar: calendar, locale: locale),
            sections: orderedCards(features).compactMap { $0.fullPage(context) }
        )
    }

    static func header(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide))
    }

    private func refresh(_ trigger: HomeRefreshTrigger) async {
        let day = now()
        today = day
        dayRefreshed(day)
        for feature in features {
            await feature.refresh(trigger)
        }
    }
}
