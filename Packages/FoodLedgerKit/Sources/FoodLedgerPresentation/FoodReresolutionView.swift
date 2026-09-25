import FoodLedgerApplication
import FoodLedgerDomain
import SwiftUI

public struct FoodReresolutionView: View {
    @ObservedObject private var model: FoodReresolutionViewModel
    public init(model: FoodReresolutionViewModel) { self.model = model }

    public var body: some View {
        Form {
            Section("Opt-in nutrition update") {
                Text("Compare a saved food with an installed source and matcher. Nothing changes until you explicitly accept. Original evidence, consumed quantity and historical results stay unchanged.")
                Picker("Proposed source / matcher", selection: $model.selectedTargetID) {
                    Text("Choose a version").tag(Optional<String>.none)
                    ForEach(model.targets, id: \.identifier) { target in
                        Text("\(target.sourceRelease.sourceReleaseID.value) · \(target.methodVersion.value)")
                            .tag(Optional(target.identifier))
                    }
                }
                Text("Only accepted installed targets are offered. CoFID 2021 is currently bundled; this is not a claim that a newer release or model exists.").font(.caption)
                Button("Reload saved foods and versions") { model.load() }
            }.disabled(model.pending != nil)
            if let message = model.message {
                Section("Status") {
                    Text(message).textSelection(.enabled)
                    if model.pending != nil { Button("Retry same update") { model.retry() } }
                }
            }
            Section("Saved food history") {
                if model.records.isEmpty { Text("No saved product entries available for re-resolution.") }
                ForEach(model.records, id: \.logItem.logItemID) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.productVersion.name.value).font(.headline)
                        Text("\(record.logItemVersion.reportingDate.value) · \(record.logItemVersion.edibleQuantity.value.formatted()) \(record.logItemVersion.edibleQuantity.unit.rawValue)")
                        Text("Current resolution \(record.resolutionVersion.ordinal.value): \(record.resolutionVersion.methodVersion.value)").font(.caption)
                        Button("Find proposals") { model.preview(record) }
                            .disabled(model.selectedTargetID == nil || model.pending != nil)
                        Button("Inspect original evidence and versions") { model.showAudit(record) }
                    }
                }
            }
            if !model.proposals.isEmpty {
                Section("Candidate choices") {
                    ForEach(model.proposals.indices, id: \.self) { index in
                        let proposal = model.proposals[index]
                        Button { model.select(index) } label: {
                            VStack(alignment: .leading) {
                                Text(proposal.candidate.name.value)
                                Text("Record: \(proposal.candidate.candidate.recordID.value)").font(.caption)
                                Text(proposal.isNoOp ? "No change" : "\(proposal.diff.changes.count) changed nutrient entries").font(.caption)
                            }
                        }.disabled(model.pending != nil)
                    }
                }
            }
            if let selected = model.selected {
                comparison(selected)
            }
            if let audit = model.audit {
                Section("Historical log versions") {
                    ForEach(audit.logVersions, id: \.logItemVersionID) { version in
                        DisclosureGroup("Log revision \(version.ordinal.value)") {
                            Text("Version: \(version.logItemVersionID.rawValue)")
                            Text("Original resolution: \(version.originalResolutionVersionID.rawValue)")
                            Text("Effective resolution: \(version.effectiveResolutionVersionID.rawValue)")
                            Text(version.correctionReason?.value ?? "Original entry")
                        }.textSelection(.enabled)
                    }
                }
                Section("Historical nutrition") {
                    ForEach(audit.resolutionVersions, id: \.resolutionVersionID) { resolution in
                        DisclosureGroup("Resolution \(resolution.ordinal.value) · \(resolution.methodVersion.value)") {
                            Text(resolution.resolutionVersionID.rawValue).textSelection(.enabled)
                            Text("Sources: \(resolution.sourceReleaseIDs.map(\.value).joined(separator: ", "))")
                            ForEach(resolution.nutrients.entries, id: \.key) { entry in
                                Text("\(label(entry.key)): \(value(entry))")
                            }
                        }
                    }
                }
                Section("Immutable capture evidence") {
                    ForEach(audit.evidence, id: \.evidenceID) { evidence in
                        DisclosureGroup("\(evidence.captureMethod.value) · \(evidence.capturedAt.formatted())") {
                            Text(evidence.evidenceID.rawValue)
                            switch evidence.originalPayload {
                            case let .barcode(code, symbology): Text("\(code.value) (\(symbology.value))")
                            case let .text(text), let .descriptor(text): Text(text.value)
                            }
                            if let hash = evidence.byteHash { Text("Attachment SHA-256: \(hash.value)") }
                        }.textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Review nutrition updates")
        .task { model.load() }
        .onChange(of: model.selectedTargetID) { _, _ in model.clearReview() }
    }

    @ViewBuilder
    private func comparison(_ proposal: FoodReresolutionProposal) -> some View {
        Section("Before / proposed") {
            Text("Logged food: \(proposal.before.productVersion.name.value)")
            Text("Proposed source description: \(proposal.candidate.name.value)")
            Text("Before record: \(proposal.before.candidateDecision.candidate.recordID.value)")
            Text("Proposed record: \(proposal.candidate.candidate.recordID.value)")
            Text("Before sources: \(proposal.before.resolutionVersion.sourceReleaseIDs.map(\.value).joined(separator: ", "))")
            Text("Proposed sources: \(proposal.sourceReleaseIDs.map(\.value).joined(separator: ", "))")
            Text("Before method: \(proposal.before.resolutionVersion.methodVersion.value)")
            Text("Proposed method: \(proposal.target.methodVersion.value)")
            Text("Nutrition basis: \(basis(proposal.before.productVersion.identity.servingBasis))")
            Text("The logged product, preparation and consumed amount are not being edited. The values below use the same stored resolution basis, not the consumed serving.").font(.caption)
            DisclosureGroup("Unchanged logged identity and proposed source identity") {
                Text("Logged\n\(detail(proposal.before.productVersion.identity))").font(.caption.monospaced())
                Text("Source\n\(detail(proposal.candidate.candidate.identity))").font(.caption.monospaced())
            }.textSelection(.enabled)
            if !proposal.identityGaps.isEmpty {
                Text("Source identity gaps: \(proposal.identityGaps.map(\.rawValue).joined(separator: ", "))")
                Toggle("I checked that this source applies to the unchanged logged identity despite those gaps", isOn: $model.confirmsIdentityGaps)
                    .disabled(model.pending != nil)
            }
        }
        Section("All 39 nutrient entries") {
            ForEach(proposal.diff.entries, id: \.key) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(label(change.key))\(change.changed ? " · changed" : "")").font(.headline)
                    Text("Before: \(value(change.before))")
                    Text("Proposed: \(value(change.after))")
                    if change.changed {
                        Text("Before sources: \(sources(change.before))").font(.caption)
                        Text("Proposed sources: \(sources(change.after))").font(.caption)
                    }
                    DisclosureGroup("Value, bounds and provenance details") {
                        Text("Before\n\(detail(change.before))").font(.caption.monospaced())
                        Text("Proposed\n\(detail(change.after))").font(.caption.monospaced())
                    }.textSelection(.enabled)
                }
            }
        }
        Section("Explicit decision") {
            TextField("Reason for this nutrition update", text: $model.reason)
            Button("Accept new effective resolution") { model.save() }
                .disabled(proposal.isNoOp || model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!proposal.identityGaps.isEmpty && !model.confirmsIdentityGaps))
            Button("Decline and keep current result") { model.decline() }
            if proposal.isNoOp { Text("No nutrient, provenance or candidate change. Nothing will be saved.") }
        }.disabled(model.pending != nil)
    }

    private func label(_ key: NutrientKey) -> String { key.rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
    private func value(_ entry: NutrientEntry) -> String {
        switch entry.value {
        case let .measured(v): "\(v.amount.formatted()) \(v.unit.rawValue) measured"
        case let .augmented(v): "\(v.amount.formatted()) \(v.unit.rawValue) augmented"
        case let .bounded(v): "\(v.lowerClosed ? "[" : "(")\(v.lower.map { $0.formatted() } ?? "open"), \(v.upper.map { $0.formatted() } ?? "open")\(v.upperClosed ? "]" : ")") \(v.unit.rawValue) bounded (\(v.origin.rawValue))"
        case let .unknown(reason): "Unknown: \(reason.rawValue.replacingOccurrences(of: "_", with: " "))"
        }
    }
    private func sources(_ entry: NutrientEntry) -> String {
        let ids = Set(([entry.value] + entry.conflictCandidates).flatMap { $0.provenance.map(\.sourceReleaseID.value) })
        return ids.isEmpty ? "none" : ids.sorted().joined(separator: ", ")
    }
    private func basis(_ basis: ResolutionBasis) -> String {
        switch basis {
        case .per100Grams: "per 100 g"
        case .per100Millilitres: "per 100 ml"
        case let .perServing(quantity): "per serving (\(quantity.value.formatted()) \(quantity.unit.rawValue))"
        case let .perUnit(quantity): "per unit (\(quantity.value.formatted()) \(quantity.unit.rawValue))"
        case let .named(name, quantity): "\(name.value) (\(quantity.value.formatted()) \(quantity.unit.rawValue))"
        case .unknown: "Unknown"
        }
    }
    private func detail<Value: Encodable>(_ entry: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let bytes = try? encoder.encode(entry) else { return "Detail unavailable" }
        return String(decoding: bytes, as: UTF8.self)
    }
}
