import SwiftUI
import UIKit
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

/// Current-day food intake is separate from completed-day HealthKit reporting.
struct FoodIntakeHomeView: View {
    let root: FoodLedgerCompositionRoot?
    var isHome = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var projection: FoodIntakeProjection?
    @State private var failure: String?
    @State private var savedEntry: SavedFoodEntrySession?
    @State private var recentDays: [FoodIntakeDayPreview] = []
    @State private var pendingRemoval: FoodIntakeLogRow?
    /// Entries whose current version is a labelled estimate (FoodEntryEstimateStatus, #195).
    @State private var estimates: Set<LogItemID> = []
    @State private var confirmsRemoval = false
    @State private var managementFailure: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Form {
            Section {
                if isHome {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Your intake so far").font(.title2.bold())
                        Text("Logged food on this device").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                } else {
                    HStack {
                        Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Previous day")
                        DatePicker("Food log date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().frame(maxWidth: .infinity)
                            .accessibilityLabel("Food log date")
                        Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Next day").disabled(Calendar.current.isDateInToday(selectedDate))
                    }.buttonStyle(.borderless)
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button("Return to today") { selectedDate = Date() }
                    }
                }
            }
            if !isHome {
                Section {
                    NavigationLink(value: AppRoute.addFood) { Label("Add food", systemImage: "plus.circle") }
                } header: { Text("Log food") } footer: {
                    if !Calendar.current.isDateInToday(selectedDate) {
                        Text("New foods are logged for now. To log on this day, set When on the confirm screen. Changes do not update an already exported snapshot.")
                    }
                }
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
                } header: {
                    Text("Logged intake · \(Self.entryCount(projection.summary.itemCount))")
                } footer: {
                    Text("Totals cover known values only. Missing or bounded nutrients are not counted as zero.")
                }
                if isHome {
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
                }
                if !projection.rows.isEmpty {
                    Section(isHome ? "Recent food entries" : "Food entries") {
                        ForEach(displayedRows(projection), id: \.logItemID) { row in
                            entryButton(row)
                                .swipeActions(allowsFullSwipe: false) {
                                    if !isHome {
                                        Button("Remove", role: .destructive) {
                                            pendingRemoval = row; confirmsRemoval = true
                                        }
                                    }
                                }
                                .contextMenu {
                                    if !isHome {
                                        Button("Remove from log", role: .destructive) {
                                            pendingRemoval = row; confirmsRemoval = true
                                        }
                                    }
                                }
                        }
                        if isHome && projection.rows.count > 3 {
                            NavigationLink("View all \(projection.rows.count) entries", value: AppRoute.foodLog)
                        }
                    }
                }
                if !isHome && !projection.removedRows.isEmpty {
                    Section {
                        ForEach(projection.removedRows, id: \.logItemID) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.name).font(.body.weight(.medium))
                                Text(Self.entryDetail(row)).font(.subheadline).foregroundStyle(.secondary)
                                Button("Restore entry") { changeEntry(row, restoring: true) }
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Restore \(row.name)")
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("Removed entries") } footer: {
                        Text("Excluded from this day's totals. Saved evidence and history are retained. Restoring does not change an already exported snapshot.")
                    }
                }
            } else {
                Section { ProgressView("Loading intake") }
            }
            if !isHome {
                Section("Past 7 days") {
                    ForEach(recentDays, id: \.date) { day in
                        Button { selectedDate = day.date } label: {
                            HStack {
                                Text(day.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let summary = day.summary {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(summary.itemCount == 0 ? "No entries" : Self.entryCount(summary.itemCount))
                                        if summary.itemCount > 0,
                                           let energy = summary.totals.first(where: { $0.key == .energyConsumed }) {
                                            Text(Self.amount(energy)).font(.caption)
                                        }
                                    }.foregroundStyle(.secondary)
                                } else {
                                    Text("Unavailable").foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }.accessibilityHint("Shows this day's food log")
                    }
                }
            } else {
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
        }
        .navigationTitle(isHome ? "Today" : "Food Log")
        .onAppear { reload() }
        .onChange(of: selectedDate) { reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
        .refreshable { reload() }
        .confirmationDialog("Remove this food entry?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove entry", role: .destructive) {
                if let pendingRemoval { changeEntry(pendingRemoval, restoring: false) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The entry will leave this day's totals. You can restore it from Removed entries; its saved evidence and history remain.")
        }
        .alert("Entry unchanged", isPresented: Binding(get: { managementFailure != nil },
                                                     set: { if !$0 { managementFailure = nil } })) {
            Button("OK") { managementFailure = nil }
        } message: { Text(managementFailure ?? "") }
        .sheet(item: $savedEntry, onDismiss: { reload() }) { session in
            SavedFoodEntrySheet(session: session) { savedEntry = nil }
        }
    }

    private var summaryKeys: [NutrientKey] {
        isHome ? [.energyConsumed, .protein, .carbohydrates, .fatTotal]
            : [.energyConsumed, .protein, .carbohydrates, .fatTotal, .fiber]
    }

    private func displayedRows(_ projection: FoodIntakeProjection) -> [FoodIntakeLogRow] {
        isHome ? Array(projection.rows.suffix(3)) : projection.rows
    }

    private func entryButton(_ row: FoodIntakeLogRow) -> some View {
        Button { open(row) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let energy = row.totals.first(where: { $0.key == .energyConsumed }) {
                        Text(Self.amount(energy)).font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(Self.entryDetail(row)).font(.subheadline).foregroundStyle(.secondary)
                Text(Self.sourceStatus(row, isEstimate: estimates.contains(row.logItemID))).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }.accessibilityHint("Opens the saved food confirmation")
    }

    private func changeEntry(_ row: FoodIntakeLogRow, restoring: Bool) {
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            try root.changeLogEntry(row, restoring: restoring)
            reload()
        } catch {
            managementFailure = "The entry could not be changed. Refresh the log and try again."
        }
    }

    private func moveDay(_ offset: Int) {
        if let day = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate), day <= Date() { selectedDate = day }
    }

    private func open(_ row: FoodIntakeLogRow) {
        savedEntry = SavedFoodEntrySession(id: row.logItemID) {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            return try root.model(reopening: row.logItemID)
        }
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
        let time = row.occurredAt.formatted(date: .omitted, time: .shortened)
        let quantity = row.quantity.value.formatted(.number.precision(.fractionLength(0...2)))
        return "\(time) · \(quantity) \(row.quantity.unit.rawValue)"
    }

    private static func sourceStatus(_ row: FoodIntakeLogRow, isEstimate: Bool) -> String {
        let names = row.sourceIDs.map { source in
            if source == "cofid" { return "UK CoFID" }
            if source.hasPrefix("usda-") { return "USDA" }
            if source == "open-food-facts" { return "Open Food Facts" }
            return "Saved food source"
        }
        let source = Array(Set(names)).sorted().joined(separator: " · ")
        let status = row.totals.contains { $0.includesEstimates } ? "Source estimate" : "Saved nutrition"
        let incomplete = row.totals.contains { $0.incompleteContributions > 0 } ? " · Incomplete nutrients" : ""
        return (isEstimate ? "Estimate · " : "") + (source.isEmpty ? status : source + " · " + status) + incomplete
    }

    private static func symbol(_ key: NutrientKey) -> String {
        switch key { case .energyConsumed: "flame"; case .protein: "p.circle"; case .carbohydrates: "c.circle"; default: "f.circle" }
    }

    private func reload() {
        if isHome && !Calendar.current.isDateInToday(selectedDate) { selectedDate = Date() }
        do {
            guard let root else { throw FoodIntakeProjectionError.missingReference }
            projection = try root.intakeProjection(for: selectedDate)
            estimates = projection.map { root.estimateLogItemIDs(in: $0.rows) } ?? []
            if !isHome { recentDays = try root.recentIntakeDays(before: Date()) }
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
