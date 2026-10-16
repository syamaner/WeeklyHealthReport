import Foundation

/// Health report section groups (docs/health-report-section-groups-v1.md, #216).
///
/// Groups are headings over the existing sections: no section is merged or
/// renamed, and row ids, labels and values are unchanged. `groups` is the one
/// ordered table that the Health screen, Copy all and Full Page all read, so
/// their order cannot drift. Developer tools reads model states and keeps its
/// own order (decision 4).
extension ReportDocument {
    enum GroupID: String, CaseIterable {
        case dailyActivity
        /// Food and water (#214, groups contract decision 5): its own standalone
        /// group straight after `dailyActivity` and never inside it, so logged
        /// food energy is never shown beside active energy.
        case foodAndWater
        case body
        case heartAndSleep
        case fitnessAndBloodOxygen
        case glucose
        case medications
    }

    struct Group: Equatable, Identifiable {
        let id: GroupID
        /// Screen and Full Page wording, sentence case like the display section
        /// titles. Copy all writes it in capitals.
        let heading: String
        let sectionIDs: [SectionID]
    }

    /// The group order and each group's section order.
    static let groups: [Group] = [
        Group(id: .dailyActivity, heading: "Daily activity", sectionIDs: [.steps, .activity]),
        Group(id: .foodAndWater, heading: "Food and water", sectionIDs: [.foodLog]),
        Group(id: .body, heading: "Body", sectionIDs: [.weight, .bodyComposition]),
        Group(id: .heartAndSleep, heading: "Heart and sleep", sectionIDs: [.heart, .bloodPressure, .sleep]),
        Group(
            id: .fitnessAndBloodOxygen,
            heading: "Fitness and blood oxygen",
            sectionIDs: [.cardiorespiratory]
        ),
        Group(id: .glucose, heading: "Glucose", sectionIDs: [.glucose]),
        Group(id: .medications, heading: "Medications", sectionIDs: [.medications])
    ]

    /// Every section belongs to exactly one group. The switch is exhaustive, so
    /// a new section cannot be added without being placed.
    static func group(for section: SectionID) -> GroupID {
        switch section {
        case .steps, .activity: .dailyActivity
        case .foodLog: .foodAndWater
        case .weight, .bodyComposition: .body
        case .heart, .bloodPressure, .sleep: .heartAndSleep
        case .cardiorespiratory: .fitnessAndBloodOxygen
        case .glucose: .glucose
        case .medications: .medications
        }
    }

    /// The present sections of one group, in the table's order.
    struct GroupedSections: Equatable, Identifiable {
        let group: Group
        let sections: [Section]

        var id: GroupID { group.id }

        /// Every present group has a heading, including a single-section group
        /// (contract v1.1), so a standalone section never reads as part of the
        /// group above it.
        var heading: String { group.heading }
    }

    /// `sections` in group order. A section missing from the table (none today)
    /// keeps its relative position at the end rather than being dropped.
    static func ordered(sections: [Section]) -> [Section] {
        let rank = Dictionary(
            uniqueKeysWithValues: groups.flatMap(\.sectionIDs).enumerated().map { ($1, $0) }
        )
        return sections.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.id] ?? Int.max
                let right = rank[rhs.element.id] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// The document's sections under their groups. Groups with no present
    /// section (for example Medications when that section is not included) are
    /// left out, so there is never an empty group.
    var groupedSections: [GroupedSections] {
        Self.groups.compactMap { group in
            let present = group.sectionIDs.compactMap { id in
                sections.first { $0.id == id }
            }
            return present.isEmpty ? nil : GroupedSections(group: group, sections: present)
        }
    }
}
