import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

// Approved estimates from Your food database, as Confirm, the saved entry and the re-resolution
// screen word them (estimates on catalogue v2 sections 3.2, 3.3 and 5). Built from the candidate's
// stored provenance and the verified capture manifest, never from a view-only flag. The tier is
// always said in words; a colour only ever accompanies its label. No medical wording, target or
// classification appears with an estimate.

public enum ApprovedEstimateText {
    /// The closed label list (contract section 3.3). A similar food is never shown as the food's
    /// own, and no label exists for a similar-food estimate at `high`.
    public static func label(method: PersonalFoodDatabaseEstimateMethod, quality: PersonalFoodDatabaseEstimateQuality) -> String? {
        switch (method == .carriedFromSimilarFood, quality) {
        case (false, .high): "Estimated, good match"
        case (false, .medium): "Estimated, some doubt"
        case (false, .low): "Estimated, rough"
        case (true, .medium): "Estimated from a similar food, some doubt"
        case (true, .low): "Estimated from a similar food, rough"
        case (true, .high): nil
        }
    }

    public static let labels = ["Estimated, good match", "Estimated, some doubt", "Estimated, rough",
                                "Estimated from a similar food, some doubt", "Estimated from a similar food, rough"]

    /// The tier in words: what the colour stands for, wherever it is shown.
    public static func tier(_ quality: PersonalFoodDatabaseEstimateQuality) -> String {
        switch quality {
        case .high: "good match"
        case .medium: "some doubt"
        case .low: "rough"
        }
    }

    public static func sourceType(_ type: PersonalFoodDatabaseEstimateSourceType) -> String {
        switch type {
        case .nationalComposition: "Food composition table"
        case .manufacturerPage: "Maker's web page"
        case .aggregator: "Food database website"
        }
    }

    public static let withheldByDetails = "Estimate left out: it does not match these details"
    public static let withheldUnreadable = "Estimate left out: its source record could not be read"
    public static let leftOutWhenLogged = "Estimate left out when this was logged"
    public static let leftOutByYou = "Left out by you"
    public static let evidenceNotAvailable = "Evidence not available"
    public static let notCarried = "Values you left out before are not carried over"
    public static let pageNotReadDirectly = "Page not read directly"
    public static let similarFood = "Estimated from a similar food"
    public static let savedRowsUnavailable = "The estimate details for this entry could not be read. Its saved values are unchanged."
    public static let leaveOut = "Leave out"
    public static let putBack = "Put back"
    public static let sectionTitle = "Estimated values"
    public static let sectionNote = "These values are estimates you approved for your food database. You can leave one out of this entry; it then stays unknown."

    public static func notice(_ reason: ApprovedEstimateWithholding) -> String {
        switch reason {
        case .facet, .basis: withheldByDetails
        case .unreadableRecord: withheldUnreadable
        case .evidenceUnavailable: evidenceNotAvailable
        }
    }

    /// Which detail withheld an estimate, for Developer tools and the row's details.
    public static func withholdingDetail(_ reason: ApprovedEstimateWithholding) -> String {
        switch reason {
        case let .facet(facet): "Left out because of: \(facet.rawValue.replacingOccurrences(of: "_", with: " "))"
        case .basis: "Left out because of: serving basis"
        case .unreadableRecord: "Left out because of: source record not readable"
        case .evidenceUnavailable: "Left out because of: evidence not available"
        }
    }

    /// The details behind one estimate, in plain words; identifiers last.
    public static func details(_ evidence: PersonalFoodDatabaseEstimateEvidence) -> [String] {
        var lines = [sourceType(evidence.sourceType)]
        if evidence.method == .carriedFromSimilarFood { lines.append(similarFood) }
        lines.append("Source describes: \(evidence.sourceState)")
        lines.append("Assumed for your food: \(evidence.targetState)")
        lines.append(evidence.assumption)
        if evidence.pageAccess == .indexedCopy { lines.append(pageNotReadDirectly) }
        if let source = evidence.compositionSource {
            lines.append("Record: \(source.rawValue) \(evidence.sourceReference)")
        } else {
            lines.append("Page: \(evidence.sourceReference)")
        }
        return lines
    }
}

/// One estimated nutrient of the entry being confirmed or shown.
public struct ApprovedEstimateRow: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Shown with its label; can be left out.
        case offered
        /// Left out on this Confirm; can be put back.
        case leftOut
        /// Withheld by the check; nothing is substituted.
        case withheld(ApprovedEstimateWithholding)
        /// A saved unknown on a reopened log.
        case saved(ApprovedEstimateSavedState)
    }

    public let key: NutrientKey
    public let title: String
    /// The estimate's own value per 100 g or 100 ml; nil while it is not part of the entry.
    public let value: String?
    /// From the closed list; nil when the evidence cannot be read.
    public let label: String?
    public let quality: PersonalFoodDatabaseEstimateQuality?
    public let status: Status
    public let notice: String?
    public let details: [String]
    public var id: String { key.rawValue }

    public var canLeaveOut: Bool { status == .offered }
    public var canPutBack: Bool {
        switch status {
        case .leftOut, .saved(.leftOutByYou): true
        default: false
        }
    }

    /// What VoiceOver reads: the label carries the tier in words, never a colour name alone.
    public var accessibilityLabel: String {
        [title, value, label, notice].compactMap { $0 }.joined(separator: ", ")
    }
}

public enum ApprovedEstimatePresentation {
    /// The estimate's own value with its basis, so it is never read as the amount eaten: "500 mg
    /// per 100 g". The consumed amount is in the nutrition section.
    static func number(_ amount: Double, unit: NutrientUnit, basis: ResolutionBasis) -> String {
        let text = amount == amount.rounded() ? String(Int(amount)) : String(amount)
        let per: String = switch basis {
        case .per100Grams: " per 100 g"
        case .per100Millilitres: " per 100 mL"
        default: ""
        }
        return "\(text) \(unit.rawValue)\(per)"
    }

    /// The estimated nutrients of the state's selected candidate, in nutrient catalogue order.
    public static func rows(_ state: FoodConfirmationState) -> [ApprovedEstimateRow] {
        let keys = state.estimateKeys
        guard !keys.isEmpty else { return [] }
        let manifest = state.estimateManifest
        let effective = state.effectiveNutrients
        let withheld = state.withheldEstimates
        let saved = state.savedEstimateStates
        let unchangedReopen = state.reopened != nil && state.correction == nil
        return NutrientKey.allCases.filter(keys.contains).map { key in
            let evidence = manifest?.estimate(key)?.evidence.typed
            let shown = effective.entries.first { $0.key == key }?.value
            let status: ApprovedEstimateRow.Status
            if let shown, ApprovedEstimateSource.isEstimate(shown) {
                status = .offered
            } else if state.leftOutEstimates.contains(key), !unchangedReopen || !state.estimateSeed.leftOut.contains(key) {
                status = .leftOut
            } else if unchangedReopen, let state = saved[key] {
                status = .saved(state)
            } else if let reason = withheld[key] {
                status = .withheld(reason)
            } else if state.leftOutEstimates.contains(key) {
                status = .leftOut
            } else {
                status = .saved(state.estimateSeed.evidenceAvailable ? .leftOutWhenLogged : .evidenceNotAvailable)
            }
            var value: String?
            if case let .augmented(exact)? = shown, status == .offered {
                value = number(exact.amount, unit: exact.unit, basis: state.selectedCandidate.candidate.identity.servingBasis)
            }
            let notice: String? = switch status {
            // A saved value whose manifest no longer verifies has no label to show: say so, so
            // it is never a bare value under "Estimated values".
            case .offered: evidence == nil ? ApprovedEstimateText.evidenceNotAvailable : nil
            case .leftOut, .saved(.leftOutByYou): ApprovedEstimateText.leftOutByYou
            case let .withheld(reason): ApprovedEstimateText.notice(reason)
            case .saved(.leftOutWhenLogged): ApprovedEstimateText.leftOutWhenLogged
            case .saved(.evidenceNotAvailable): ApprovedEstimateText.evidenceNotAvailable
            }
            var details = evidence.map(ApprovedEstimateText.details) ?? []
            if case let .withheld(reason) = status { details.append(ApprovedEstimateText.withholdingDetail(reason)) }
            return ApprovedEstimateRow(
                key: key, title: FoodLogText.label(key), value: value,
                label: evidence.flatMap { ApprovedEstimateText.label(method: $0.method, quality: $0.quality) },
                quality: evidence?.quality, status: status, notice: notice, details: details)
        }
    }

    /// The lines the re-resolution screen shows for a proposal whose fresh candidate has approved
    /// estimates: each estimate's label, a notice for each withheld one, and that earlier leave-outs
    /// are not carried. Leave-out is not offered there.
    public static func reresolutionNotes(_ proposal: FoodReresolutionProposal) -> [String] {
        // The service verified the manifest before deciding what to withhold; an unverified one
        // withholds every estimate, so reading the payload here only supplies labels.
        let manifests = proposal.input.evidence.filter(ApprovedEstimateSource.isManifest).compactMap { evidence -> ApprovedEstimateCaptureManifest? in
            guard case let .text(payload) = evidence.originalPayload else { return nil }
            return ApprovedEstimateCaptureManifest.decode(Data(payload.value.utf8))
        }
        return reresolutionNotes(proposal, manifests: manifests)
    }

    static func reresolutionNotes(_ proposal: FoodReresolutionProposal, manifests: [ApprovedEstimateCaptureManifest]) -> [String] {
        let keys = ApprovedEstimateSource.estimateKeys(proposal.candidate.candidate)
        guard !keys.isEmpty else { return [] }
        let manifest = manifests.first { $0.entryID == proposal.candidate.candidate.recordID.value }
        var lines: [String] = []
        for key in NutrientKey.allCases where keys.contains(key) {
            let title = FoodLogText.label(key)
            if let reason = proposal.withheldEstimates[key] {
                lines.append("\(title): \(ApprovedEstimateText.notice(reason))")
            } else if let evidence = manifest?.estimate(key)?.evidence.typed,
                      let label = ApprovedEstimateText.label(method: evidence.method, quality: evidence.quality) {
                lines.append("\(title): \(label)")
            } else {
                lines.append("\(title): \(ApprovedEstimateText.evidenceNotAvailable)")
            }
        }
        lines.append(ApprovedEstimateText.notCarried)
        return lines
    }
}

/// The one renderer of an entry's approved estimates, on Confirm (with Leave out and Put back) and
/// on the saved entry (read only). Each estimated nutrient shows its label from the closed list: the
/// tier in words, with its colour only beside those words, never alone and never on the value.
public struct ApprovedEstimateSection: View {
    private let rows: [ApprovedEstimateRow]
    private let leaveOut: ((NutrientKey) -> Void)?
    private let putBack: ((NutrientKey) -> Void)?

    public init(rows: [ApprovedEstimateRow], leaveOut: ((NutrientKey) -> Void)? = nil, putBack: ((NutrientKey) -> Void)? = nil) {
        self.rows = rows; self.leaveOut = leaveOut; self.putBack = putBack
    }

    /// Green, amber and red for good match, some doubt and rough.
    public static func tierColour(_ quality: PersonalFoodDatabaseEstimateQuality?) -> Color {
        switch quality {
        case .high: .green
        case .medium: .orange
        case .low: .red
        case nil: .secondary
        }
    }

    public var body: some View {
        if !rows.isEmpty {
            Section(ApprovedEstimateText.sectionTitle) {
                if leaveOut != nil {
                    Text(ApprovedEstimateText.sectionNote).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        // VoiceOver reads the nutrient with its value, label and notice in one phrase:
                        // the tier is in the words, never in the colour.
                        LabeledContent(row.title, value: row.value ?? "Unknown")
                            .accessibilityLabel(row.accessibilityLabel)
                        if let label = row.label, row.status == .offered {
                            HStack(spacing: 6) {
                                Circle().fill(Self.tierColour(row.quality)).frame(width: 10, height: 10).accessibilityHidden(true)
                                Text(label).font(.subheadline)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(label)
                        }
                        if let notice = row.notice { Text(notice).font(.subheadline).foregroundStyle(.secondary) }
                        if !row.details.isEmpty {
                            DisclosureGroup("Details") {
                                ForEach(row.details, id: \.self) { Text($0).font(.caption) }
                            }
                            .font(.caption)
                            .frame(minHeight: 44)
                        }
                        if row.canLeaveOut, let leaveOut {
                            // Borderless: in a list row a plain button takes every tap on the row, so
                            // opening Details would also leave the value out (journey QA, #511).
                            Button(ApprovedEstimateText.leaveOut) { leaveOut(row.key) }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44).accessibilityLabel("\(ApprovedEstimateText.leaveOut): \(row.title)")
                                .accessibilityIdentifier("estimate-leave-out-\(row.key.rawValue)")
                        } else if row.canPutBack, let putBack {
                            Button(ApprovedEstimateText.putBack) { putBack(row.key) }
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44).accessibilityLabel("\(ApprovedEstimateText.putBack): \(row.title)")
                                .accessibilityIdentifier("estimate-put-back-\(row.key.rawValue)")
                        }
                    }
                    .accessibilityIdentifier("estimate-row-\(row.key.rawValue)")
                }
            }
        }
    }
}
