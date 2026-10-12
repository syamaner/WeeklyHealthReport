import SwiftUI
import UIKit
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

/// Home's current-day food intake, separate from completed-day HealthKit reporting. The Food
/// Log is `FoodLogView` (#197); Home itself is redesigned in #199.
struct FoodIntakeHomeView: View {
    let root: FoodLedgerCompositionRoot?
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var projection: FoodIntakeProjection?
    @State private var failure: String?
    @State private var openedEntry: LogItemID?
    /// Entries whose current version is a labelled estimate (FoodEntryEstimateStatus, #195).
    @State private var estimates: Set<LogItemID> = []
    /// Quick-add chips (#198): the first four items; nil when favourites cannot be read.
    @State private var quickAddItems: [QuickAddItem]? = []
    @State private var quickAddRequest: QuickAddItem?
    /// Plain water logged today (Q8). Nil means No data.
    @State private var plainWater: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Your intake so far").font(.title2.bold())
                    Text("Logged food on this device").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            if let failure {
                Section("Intake unavailable") {
                    Label(failure, systemImage: "exclamationmark.triangle")
                    Button("Try again") { reload() }
                }
            } else if let projection {
                Section {
                    if projection.rows.isEmpty {
                        ContentUnavailableView("No food logged", systemImage: "fork.knife",
                            description: Text("Logged intake will appear here after you confirm a food. An empty log does not mean no food was eaten."))
                    } else {
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(summaryKeys, id: \.rawValue) { key in
                                if let total = projection.summary.totals.first(where: { $0.key == key }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label(Self.label(key), systemImage: Self.symbol(key))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Text(Self.amount(total)).font(.title2.weight(.semibold)).monospacedDigit()
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(total.incompleteContributions > 0 ? "\(Self.entryCount(total.incompleteContributions)) incomplete" : total.includesEstimates ? "Includes estimates" : "Known values")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                    LabeledContent(FoodLogText.plainWaterLabel, value: FoodLogText.plainWater(plainWater))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(FoodLogText.plainWaterAccessibility(plainWater))
                } header: {
                    Text("Logged intake · \(Self.entryCount(projection.summary.itemCount))")
                } footer: {
                    Text("Totals cover known values only. Missing or bounded nutrients are not counted as zero.")
                }
                Section {
                    if let items = quickAddItems {
                        QuickAddChipRow(items: Array(items.prefix(FavouritesProjection.todayCount))) { quickAddRequest = $0 }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        NavigationLink("Manage favourites", value: AppRoute.favourites)
                    } else {
                        Label("Favourites could not be read.", systemImage: "exclamationmark.triangle")
                        NavigationLink("Review favourites", value: AppRoute.favourites)
                    }
                } header: { Text("Quick add") } footer: {
                    Text("A quick add opens a short confirmation. Nothing is logged until you choose Log.")
                }
                Section {
                    NavigationLink(value: AppRoute.addFood) {
                        actionLabel("Add food", subtitle: "Search, scan a barcode or log a recent food", symbol: "plus.circle.fill")
                    }
                    NavigationLink(value: AppRoute.foodLog) {
                        actionLabel("Manage food intake", subtitle: "Review and change today's entries", symbol: "fork.knife.circle.fill")
                    }
                    NavigationLink(value: AppRoute.dailyExport) {
                        actionLabel("Export health data", subtitle: "Prepare and review your Apple Health export", symbol: "square.and.arrow.up.circle.fill")
                    }
                }
                if !projection.rows.isEmpty {
                    Section("Recent food entries") {
                        ForEach(projection.rows.suffix(3), id: \.logItemID) { row in
                            entryButton(row)
                        }
                        if projection.rows.count > 3 {
                            NavigationLink("View all \(projection.rows.count) entries", value: AppRoute.foodLog)
                        }
                    }
                }
            } else {
                Section { ProgressView("Loading intake") }
            }
            if projection == nil || failure != nil {
                Section("Manage your day") {
                    NavigationLink("Manage food intake", value: AppRoute.foodLog)
                    NavigationLink("Export health data", value: AppRoute.dailyExport)
                }
            }
            Section("Review") {
                NavigationLink(value: AppRoute.healthReport) { Label("View health report", systemImage: "heart.text.square") }
            }
        }
        .navigationTitle("Today")
        .onAppear { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
        .refreshable { reload() }
        .navigationDestination(item: $openedEntry) { id in
            if let root {
                SavedFoodEntryView(model: root.savedEntryModel(id), calendar: root.confirmationDayCalendar,
                                   now: { root.confirmationNow })
            }
        }
        .onChange(of: openedEntry) { _, entry in if entry == nil { reload() } }
        .modifier(OptionalQuickAdd(root: root, request: $quickAddRequest, logged: reload))
    }

    private var summaryKeys: [NutrientKey] { [.energyConsumed, .protein, .carbohydrates, .fatTotal] }

    private func entryButton(_ row: FoodIntakeLogRow) -> some View {
        Button { openedEntry = row.logItemID } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let energy = row.totals.first(where: { $0.key == .energyConsumed }) {
                        Text(energy.knownAmount == nil ? "Energy unknown" : Self.amount(energy)).font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(Self.entryDetail(row)).font(.subheadline).foregroundStyle(.secondary)
                if estimates.contains(row.logItemID) || row.totals.contains(where: { $0.includesEstimates }) {
                    Text("Estimate").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the saved entry")
    }

    private func actionLabel(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }.accessibilityElement(children: .combine)
    }

    private static func entryDetail(_ row: FoodIntakeLogRow) -> String {
        "\(FoodLogText.time(row.occurredAt, calendar: .autoupdatingCurrent)) · \(FoodLogText.amount(row.quantity))"
    }

    private static func symbol(_ key: NutrientKey) -> String {
        switch key { case .energyConsumed: "flame"; case .protein: "p.circle"; case .carbohydrates: "c.circle"; default: "f.circle" }
    }

    private func reload() {
        if !Calendar.current.isDateInToday(selectedDate) { selectedDate = Date() }
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            projection = try root.intakeProjection(for: selectedDate)
            estimates = projection.map { root.estimateLogItemIDs(in: $0.rows) } ?? []
            plainWater = try root.plainWaterMillilitres(for: selectedDate)
            quickAddItems = root.quickAddItems()
            failure = nil
        } catch FoodIntakeProjectionError.competingVersions {
            projection = nil; failure = "Conflicting food versions need review before an intake total can be shown."
        } catch FoodIntakeProjectionError.unsupportedMixture {
            projection = nil; failure = "This day includes a mixed meal that cannot yet be totalled safely."
        } catch {
            projection = nil; failure = "The local food log could not be read. Unlock your device and try again."
        }
    }

    private static func label(_ key: NutrientKey) -> String {
        switch key { case .energyConsumed: "Energy"; case .protein: "Protein"; case .carbohydrates: "Carbohydrates"; case .fiber: "Fibre"; default: "Fat" }
    }

    static func entryCount(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    private static func amount(_ total: FoodIntakeTotal) -> String {
        guard let amount = total.knownAmount else { return "Unknown" }
        let value = "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(total.key.canonicalUnit.rawValue)"
        return total.incompleteContributions == 0 ? value : value + " known"
    }
}

/// Quick add on Home when the food ledger is composed.
private struct OptionalQuickAdd: ViewModifier {
    let root: FoodLedgerCompositionRoot?
    @Binding var request: QuickAddItem?
    let logged: () -> Void

    func body(content: Content) -> some View {
        if let root { content.quickAdd(root: root, request: $request, logged: logged) } else { content }
    }
}
