import Foundation

struct MedicationDoseRecord: Identifiable, Equatable {
    let id: UUID
    let medicationKey: String
    let medicationName: String
    let date: Date
    let quantity: Double?
    let unitLabel: String
}

struct MedicationDoseGroup: Identifiable, Equatable {
    let medicationKey: String
    let medicationName: String
    let doses: [MedicationDoseRecord]

    var id: String { medicationKey }
    var latestDose: MedicationDoseRecord { doses[doses.count - 1] }
    var count: Int { doses.count }
}

struct MedicationSummary: Equatable {
    let groups: [MedicationDoseGroup]

    var allDoses: [MedicationDoseRecord] {
        groups.flatMap(\.doses).sorted { $0.date > $1.date }
    }

    static func aggregate(_ records: [MedicationDoseRecord]) -> MedicationSummary? {
        guard !records.isEmpty else { return nil }

        let groups = Dictionary(grouping: records, by: \.medicationKey)
            .compactMap { key, doses -> MedicationDoseGroup? in
                guard let first = doses.first else { return nil }
                return MedicationDoseGroup(
                    medicationKey: key,
                    medicationName: first.medicationName,
                    doses: doses.sorted { $0.date < $1.date }
                )
            }
            .sorted {
                if $0.latestDose.date != $1.latestDose.date {
                    return $0.latestDose.date > $1.latestDose.date
                }
                return $0.medicationName.localizedCaseInsensitiveCompare($1.medicationName)
                    == .orderedAscending
            }

        return MedicationSummary(groups: groups)
    }
}
