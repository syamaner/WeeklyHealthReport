import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

@MainActor
public final class FoodReresolutionViewModel: ObservableObject {
    @Published public private(set) var records: [StoredFoodConfirmation] = []
    @Published public private(set) var targets: [FoodReresolutionTarget] = []
    @Published public var selectedTargetID: String?
    @Published public private(set) var proposals: [FoodReresolutionProposal] = []
    @Published public private(set) var selectedIndex: Int?
    @Published public var reason = ""
    @Published public var confirmsIdentityGaps = false
    @Published public private(set) var message: String?
    @Published public private(set) var pending: PreparedFoodReresolution?
    @Published public private(set) var audit: FoodReresolutionAudit?
    /// What the history list may claim: it is empty only once a read has succeeded.
    public enum HistoryState: Equatable, Sendable { case loading, loaded, failed }
    @Published public private(set) var historyState: HistoryState = .loading
    private let service: FoodReresolutionService

    public init(service: FoodReresolutionService) { self.service = service }
    public var selected: FoodReresolutionProposal? {
        guard let selectedIndex, proposals.indices.contains(selectedIndex) else { return nil }
        return proposals[selectedIndex]
    }

    public func load() {
        guard pending == nil else { return }
        loadSerial += 1
        apply(Result { (try service.history(), try service.targets()) })
    }

    /// The screen's own load: the whole history is read off the main actor, so a long ledger cannot
    /// block the interface (or trip the launch watchdog when the screen is restored at launch).
    /// While it runs the list shows loading, so rows from an older read cannot be acted on, and
    /// only the most recent load (this or a later direct one) may change what is shown.
    public func loadInBackground() async {
        guard pending == nil else { return }
        loadSerial += 1
        let serial = loadSerial
        historyState = .loading
        // Rows are hidden while reading, so no proposal from the older read stays acceptable.
        clearReview()
        let service = service
        let result = await Task.detached { Result { (try service.history(), try service.targets()) } }.value
        guard pending == nil, serial == loadSerial else { return }
        apply(result)
    }

    private var loadSerial = 0

    private func apply(_ result: Result<([StoredFoodConfirmation], [FoodReresolutionTarget]), any Error>) {
        switch result {
        case let .success((history, installed)):
            historyState = .loaded
            records = history
            targets = installed
            if !targets.contains(where: { $0.identifier == selectedTargetID }) { selectedTargetID = nil }
        case .failure:
            // A failed read never leaves older rows actionable.
            historyState = .failed
            records = []
            clearReview()
            message = "History or source versions could not be read. No resolution was changed."
        }
    }

    public func clearReview() {
        guard pending == nil else { return }
        proposals = []
        selectedIndex = nil
        reason = ""
        confirmsIdentityGaps = false
        audit = nil
    }

    public func preview(_ record: StoredFoodConfirmation) {
        guard pending == nil else { return }
        clearReview()
        guard let target = targets.first(where: { $0.identifier == selectedTargetID }) else {
            message = "Choose an installed source and matcher version first."
            return
        }
        do {
            proposals = try service.proposals(logItemID: record.logItem.logItemID, target: target)
            message = proposals.isEmpty ? "No compatible candidate from this source. The current result is unchanged." : "Choose a candidate to compare all nutrient states. Nothing is saved yet."
        } catch { message = "The source or saved item changed or could not be read. Reload before trying again; nothing was saved." }
    }

    public func select(_ index: Int) {
        guard pending == nil, proposals.indices.contains(index) else { return }
        selectedIndex = index
        reason = ""
        confirmsIdentityGaps = false
    }

    public func decline() {
        guard pending == nil else { return }
        clearReview()
        message = "Proposal declined. The current and historical resolutions are unchanged."
    }

    public func showAudit(_ record: StoredFoodConfirmation) {
        do { audit = try service.audit(record.logItem.logItemID) }
        catch { message = "Historical evidence could not be read. Nothing was changed." }
    }

    public func save() {
        guard pending == nil, let selected else { return }
        do {
            pending = try service.prepareAcceptance(selected, reason: LedgerText(reason), confirmsIdentityGaps: confirmsIdentityGaps)
            retry()
        } catch FoodReresolutionError.identityConfirmationRequired {
            message = "Review and explicitly confirm the source's missing identity fields first."
        } catch FoodReresolutionError.noChange {
            message = "No nutrient, provenance or candidate change; no new version was saved."
        } catch {
            message = "Could not prepare the update. Check the reason and reload current source/log versions. Nothing was saved."
        }
    }

    /// A background load that finished while this save was pending was discarded. A successful save
    /// reloads directly (superseding it); the other ways a save clears read once more off the main
    /// actor, so the list never stays on loading.
    private func reloadIfDiscarded() {
        guard historyState == .loading else { return }
        Task { await loadInBackground() }
    }

    public func retry() {
        guard let pending else { return }
        do {
            _ = try service.accept(pending)
            self.pending = nil
            clearReview()
            message = "Accepted as resolution \(pending.newResolutionVersionID.rawValue). Original evidence and earlier results are unchanged. No export or HealthKit write occurred."
            load()
        } catch FoodReresolutionError.staleProposal {
            self.pending = nil
            clearReview()
            message = "The log or resolution history changed. This proposal was not saved; reload and compare again."
            reloadIfDiscarded()
        } catch FoodReresolutionError.unavailableTarget {
            self.pending = nil
            clearReview()
            message = "The selected source version is no longer available. Nothing was changed."
            reloadIfDiscarded()
        } catch {
            message = "Save failed or its result is uncertain. Retry this same update before making another change."
        }
    }
}
