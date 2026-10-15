import SwiftUI
import UIKit

@MainActor
final class WeeklyReportPresentationState: ObservableObject {
    @Published var showsMorningBloodPressureDetails = true
    @Published var showsEveningBloodPressureDetails = false
    @Published var showsMedicationAccessHelp = false
    /// On-screen section expansion only. Copy all, Full Page and the tiles
    /// always use the fully expanded document.
    @Published var expandedSections = Set(ReportDocument.SectionID.allCases)
    @Published private(set) var isMedicationAuthorizationRequestActive = false

    var isTransientUIPresented: Bool {
        showsMedicationAccessHelp || isMedicationAuthorizationRequestActive
    }

    func isExpanded(_ section: ReportDocument.SectionID) -> Bool {
        expandedSections.contains(section)
    }

    func setExpanded(_ section: ReportDocument.SectionID, _ isExpanded: Bool) {
        if isExpanded {
            expandedSections.insert(section)
        } else {
            expandedSections.remove(section)
        }
    }

    func beginMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = true
    }

    func finishMedicationAuthorizationRequest() {
        isMedicationAuthorizationRequestActive = false
    }
}

/// The completed-day Health report. The shell owns its presentation state so
/// screenshot eligibility and the medication help sheet keep one owner.
struct HealthReportView: View {
    @ObservedObject var viewModel: WeeklyReportViewModel
    @ObservedObject var presentationState: WeeklyReportPresentationState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copied = false

    var body: some View {
        let document = ReportDocument(snapshot: viewModel.presentationSnapshot(
            includesMedicationSection: Self.includesMedicationSection,
            showsMorningBloodPressureDetails:
                presentationState.showsMorningBloodPressureDetails,
            showsEveningBloodPressureDetails:
                presentationState.showsEveningBloodPressureDetails
        )).forDisplay()
        let tiles = HealthSummaryTiles.make(from: Self.expandedDocument(viewModel: viewModel).forDisplay())
        return Form {
            Section {
                Picker("Reporting period", selection: $viewModel.selection) {
                    ForEach(ReportPeriodSelection.allCases) { selection in
                        Text(Self.shortTitle(for: selection))
                            .accessibilityLabel(selection.rawValue)
                            .tag(selection)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selection) {
                    Task { await viewModel.refresh() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodText)
                    Text("Completed days only; today is not included.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Section("Summary") {
                LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                    ForEach(tiles) { tile in
                        HealthSummaryTileView(tile: tile)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(document.groupedSections) { grouped in
                if let heading = grouped.heading {
                    ReportGroupHeading(heading: heading)
                }
                ForEach(grouped.sections) { section in
                    reportSection(section)
                }
            }

            Section {
                Button(action: copyAll) {
                    Label(
                        copied ? "Copied" : "Copy all",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCopyAll)
                .accessibilityIdentifier("health.copyAll")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Copy all copies every section as text, with all details shown. The summary tiles are not copied.")
            }

            Section {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.state == .loading)

                if let refreshed = viewModel.lastRefreshed {
                    LabeledContent(
                        "Last refreshed",
                        value: HealthReportFormatter.dateAndTime(refreshed)
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink(value: AppRoute.dailyExport) {
                    Label("Export a day", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("health.export")
            } footer: {
                Text("Nothing is exported until you choose Export on the next screen.")
            }
        }
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: copyAll) {
                    Label(copied ? "Copied" : "Copy all", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(!canCopyAll)
                .accessibilityIdentifier("health.copyAll.toolbar")
            }
        }
    }

    /// One section, in the disclosure style its kind needs. The section stays
    /// the disclosure unit; group headings never collapse anything.
    @ViewBuilder
    private func reportSection(_ section: ReportDocument.Section) -> some View {
        let isExpanded = Binding(
            get: { presentationState.isExpanded(section.id) },
            set: { presentationState.setExpanded(section.id, $0) }
        )
        switch section.id {
        case .bloodPressure:
            BloodPressureReportSection(
                section: section,
                isExpanded: isExpanded,
                showsMorningDetails:
                    $presentationState.showsMorningBloodPressureDetails,
                showsEveningDetails:
                    $presentationState.showsEveningBloodPressureDetails
            )
        case .medications:
            if #available(iOS 26.0, *) {
                MedicationReportSection(
                    section: section,
                    isExpanded: isExpanded,
                    requestAccess: {
                        presentationState.showsMedicationAccessHelp = true
                    }
                )
            }
        default:
            ReportDocumentSectionView(section: section, isExpanded: isExpanded)
        }
    }

    private var tileColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    /// The one gate shared by the toolbar and the in-form Copy all buttons.
    private var canCopyAll: Bool {
        Self.canCopyAll(viewModel: viewModel)
    }

    /// The one Copy all path shared by the toolbar and the in-form button.
    private func copyAll() {
        guard canCopyAll else { return }
        UIPasteboard.general.string = Self.copyAllText(viewModel: viewModel, generatedAt: Date())
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var periodText: String {
        viewModel.period.completedDays.isEmpty
            ? MetricRowVocabulary.noCompletedDays
            : HealthReportFormatter.period(viewModel.period)
    }

    static func canCopyAll(viewModel: WeeklyReportViewModel) -> Bool {
        !viewModel.isRefreshing
    }

    /// Copy all text: the expanded document, whatever is expanded on screen.
    static func copyAllText(
        viewModel: WeeklyReportViewModel,
        generatedAt: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        expandedDocument(viewModel: viewModel, calendar: calendar, locale: locale)
            .plainText(generatedAt: generatedAt, calendar: calendar, locale: locale)
    }

    /// The single expanded document used by the tiles and Copy all.
    static func expandedDocument(
        viewModel: WeeklyReportViewModel,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> ReportDocument {
        ReportDocument.expanded(
            snapshot: viewModel.presentationSnapshot(
                includesMedicationSection: includesMedicationSection,
                showsMorningBloodPressureDetails: true,
                showsEveningBloodPressureDetails: true
            ),
            calendar: calendar,
            locale: locale
        )
    }

    /// Full Page: always the expanded document, or nothing during a refresh
    /// or period mismatch.
    static func fullPageDocument(viewModel: WeeklyReportViewModel) -> ReportDocument? {
        viewModel.screenshotSnapshot(
            includesMedicationSection: includesMedicationSection,
            showsMorningBloodPressureDetails: true,
            showsEveningBloodPressureDetails: true
        ).map { ReportDocument.expanded(snapshot: $0) }
    }

    static func shortTitle(for selection: ReportPeriodSelection) -> String {
        switch selection {
        case .currentWeek: "This week"
        case .previousWeek: "Last week"
        case .lastSevenCompletedDays: "Last 7 days"
        }
    }

    static var includesMedicationSection: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }
}
