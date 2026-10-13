import SwiftUI
import UIKit
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation

/// The Food Log (#197): day navigation, a totals strip of known values, entries by time,
/// swipe to remove and a collapsed Removed section with Restore. A food-ledger projection,
/// separate from completed-day Health averages and the Daily JSON export.
struct FoodLogView: View {
    private let root: FoodLedgerCompositionRoot
    @StateObject private var model: FoodLogViewModel
    @ObservedObject private var navigation: AppNavigationCoordinator
    @State private var openedEntry: LogItemID?
    @State private var showsRemoved = false
    @State private var showsDatePicker = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(root: FoodLedgerCompositionRoot, navigation: AppNavigationCoordinator) {
        self.root = root
        self.navigation = navigation
        _model = StateObject(wrappedValue: root.foodLogModel())
    }

    var body: some View {
        Form {
            daySection
            switch model.phase {
            case .loading:
                Section { ProgressView("Loading food log") }
                addFoodSection
            case let .failed(failure):
                Section("Food log unavailable") {
                    Label(FoodLogText.failure(failure), systemImage: "exclamationmark.triangle")
                    Button("Try again") { Task { await model.load() } }.frame(minHeight: 44)
                }
                addFoodSection
            case let .loaded(day):
                if let totals = day.totals {
                    totalsSection(totals, plainWater: day.plainWater)
                }
                addFoodSection
                if day.entries.isEmpty {
                    Section {
                        ContentUnavailableView(FoodLogText.emptyTitle, systemImage: "fork.knife",
                                               description: Text(FoodLogText.emptyMessage))
                    }
                } else {
                    entriesSection(day.entries)
                }
                if !day.removed.isEmpty { removedSection(day.removed) }
            }
        }
        .navigationTitle("Food Log")
        // onAppear (not task) so returning from Add food reloads, and the focus day set by Done
        // is consumed whether the log reappears or was already showing.
        .onAppear { Task { await appear() } }
        .onReceive(navigation.$foodLogFocusDay.compactMap { $0 }) { _ in Task { await appear() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refreshAfterTimeChange() } } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.refreshAfterTimeChange() }
        }
        .refreshable { await model.load() }
        .navigationDestination(item: $openedEntry) { id in
            SavedFoodEntryView(model: root.savedEntryModel(id), calendar: model.calendar, now: { root.confirmationNow })
        }
        .onChange(of: openedEntry) { _, entry in if entry == nil { Task { await model.load() } } }
        // `presenting` captures the entry when the alert appears; dismissal clears pendingRemoval
        // before the Remove task runs, so the action must not read it (#211, D9).
        .alert(FoodLogText.removeAlertTitle, isPresented: Binding(get: { model.pendingRemoval != nil },
                                                               set: { if !$0 { model.cancelRemoval() } }),
               presenting: model.pendingRemoval) { entry in
            Button("Cancel", role: .cancel) { model.cancelRemoval() }
            Button("Remove", role: .destructive) { Task { await model.confirmRemoval(entry) } }
        } message: { _ in Text(FoodLogText.removeAlertMessage) }
        .alert("Entry unchanged", isPresented: Binding(get: { model.changeAlert != nil }, set: { if !$0 { model.changeAlert = nil } })) {
            Button("OK") { model.changeAlert = nil }
        } message: { Text(model.changeAlert.map(FoodLogText.changeAlert) ?? "") }
    }

    private func appear() async {
        if let day = navigation.takeFoodLogFocusDay() { await model.showDay(day) } else { await model.load() }
    }

    // MARK: Day

    private var daySection: some View {
        Section {
            HStack {
                Button { Task { await model.previousDay() } } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Previous day")
                Button { showsDatePicker = true } label: {
                    Text(model.selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Food log date, \(model.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .accessibilityHint("Opens the date picker")
                Button { Task { await model.nextDay() } } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Next day")
                .disabled(!model.canMoveForward)
            }
            .buttonStyle(.borderless)
            if !model.isToday {
                Button("Return to today") { Task { await model.returnToToday() } }.frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $showsDatePicker) {
            NavigationStack {
                DatePicker("Food log date", selection: Binding(get: { model.selectedDate },
                                                               set: { date in Task { await model.choose(date) } }),
                           in: ...model.latestSelectableDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Choose a day")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsDatePicker = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Totals

    private func totalsSection(_ totals: [FoodIntakeTotal], plainWater: FoodIntakeTotal?) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 4), alignment: .leading, spacing: 8) {
                ForEach(totals, id: \.key.rawValue) { total in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FoodLogText.stripLabel(total.key)).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(FoodLogText.total(total)).font(.headline).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        if let caption = FoodLogText.totalCaption(total) {
                            Text(caption).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FoodLogText.totalAccessibility(total))
                }
            }
            .padding(.vertical, 4)
            // F1 resolved by #198 (Q8): plain water logged, the same figure as Home.
            LabeledContent(FoodLogText.plainWaterLabel, value: FoodLogText.plainWater(plainWater))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FoodLogText.plainWaterAccessibility(plainWater))
        } footer: { Text(FoodLogText.totalsFootnote) }
    }

    // MARK: Add food

    private var addFoodSection: some View {
        Section {
            // A Button, not a NavigationLink: inside a Form a link ignores the button style.
            Button { navigation.openAddFood(fromFoodLogDay: model.addFoodDayKey) } label: {
                Label("Add food", systemImage: "plus").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let footnote = model.addFoodFootnote { Text(footnote) }
        }
    }

    // MARK: Entries

    private func entriesSection(_ entries: [FoodLogDayContent.Entry]) -> some View {
        Section {
            ForEach(entries, id: \.logItemID) { entry in
                Button { openedEntry = entry.logItemID } label: { row(entry).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Remove", role: .destructive) { model.requestRemoval(entry) }
                    }
                    .contextMenu {
                        Button("Remove from log", role: .destructive) { model.requestRemoval(entry) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FoodLogText.entryAccessibility(entry, time: time(entry.occurredAt)))
                    .accessibilityHint("Opens the saved entry")
                    .accessibilityAction(named: "Remove from log") { model.requestRemoval(entry) }
            }
        } header: { Text("Entries") } footer: { Text(FoodLogText.swipeFootnote) }
    }

    @ViewBuilder
    private func row(_ entry: FoodLogDayContent.Entry) -> some View {
        let flags = FoodLogText.flags(entry)
        if dynamicTypeSize.isAccessibilitySize {
            // Stacked at accessibility sizes so words never break mid-word.
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).foregroundStyle(.primary)
                Text("\(time(entry.occurredAt)) · \(FoodLogText.amount(entry.quantity))").foregroundStyle(.secondary)
                Text(FoodLogText.entryEnergy(entry)).foregroundStyle(.secondary)
                if !flags.isEmpty { Text(flags).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(time(entry.occurredAt)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).foregroundStyle(.primary)
                    Text(FoodLogText.amount(entry.quantity)).font(.subheadline).foregroundStyle(.secondary)
                    if !flags.isEmpty { Text(flags).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Text(FoodLogText.entryEnergy(entry)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
    }

    private func removedSection(_ removed: [FoodLogDayContent.RemovedEntry]) -> some View {
        Section {
            DisclosureGroup(FoodLogText.removedHeader(removed.count), isExpanded: $showsRemoved) {
                ForEach(removed, id: \.logItemID) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                            Text(FoodLogText.removedLine(entry, now: root.confirmationNow, calendar: model.calendar))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { Task { await model.restore(entry) } }
                            .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Restore \(entry.name)")
                    }
                }
            }
        }
    }

    private func time(_ date: Date) -> String { FoodLogText.time(date, calendar: model.calendar) }
}
