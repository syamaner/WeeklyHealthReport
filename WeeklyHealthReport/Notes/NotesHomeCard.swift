import SwiftUI

/// Home's "Today's notes" row (#199, D11). Always today's count from the
/// controller's own clock, independent of the export's selected day; opens
/// `todayNotes`, which pins the shared controller to today.
struct NotesHomeCard: View {
    @ObservedObject var controller: DailyNotesController
    /// Changes on each Home refresh, so the count follows a midnight rollover.
    let today: Date

    var body: some View {
        Section {
            NavigationLink(value: AppRoute.todayNotes) {
                LabeledContent(Self.title, value: Self.countLabel(controller.todayNoteCount))
            }
            .accessibilityIdentifier("homeTodayNotes")
        }
    }

    static let title = "Today’s notes"

    static func countLabel(_ count: Int) -> String {
        switch count {
        case 0: "None yet"
        case 1: "1 note"
        default: "\(count) notes"
        }
    }

    /// Full Page shows the count only; note text stays behind the row.
    static func fullPageSection(count: Int) -> TodayFullPageDocument.Section {
        TodayFullPageDocument.Section(title: title, rows: [TodayFullPageDocument.Row(value: countLabel(count))])
    }

    static func feature(controller: DailyNotesController) -> HomeFeature {
        HomeFeature(cards: [
            HomeCard(id: .notes, fullPage: { _ in fullPageSection(count: controller.todayNoteCount) }) { context in
                AnyView(NotesHomeCard(controller: controller, today: context.today))
            }
        ])
    }
}
