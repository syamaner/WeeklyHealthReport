import SwiftUI

/// A deliberately closed ordering. Adding a section is a reviewed change to
/// presentation order, not a plug-in.
enum SettingsSectionID: Int, Comparable, CaseIterable {
    case foodSearch
    case export
    case data
    case appleHealth
    case about

    static func < (lhs: SettingsSectionID, rhs: SettingsSectionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A Boolean preference row. `set` writes through the owning feature's store
/// and then re-reads it, so the row shows what was actually stored.
@MainActor
final class SettingsToggle: ObservableObject {
    let title: String
    let caption: String?
    let isEnabled: Bool
    @Published private(set) var isOn: Bool
    private let read: @MainActor () -> Bool
    private let write: @MainActor (Bool) -> Void

    init(
        title: String,
        caption: String? = nil,
        isEnabled: Bool = true,
        read: @escaping @MainActor () -> Bool,
        write: @escaping @MainActor (Bool) -> Void
    ) {
        self.title = title
        self.caption = caption
        self.isEnabled = isEnabled
        self.read = read
        self.write = write
        isOn = read()
    }

    func set(_ value: Bool) {
        write(value)
        isOn = read()
    }

    func reload() {
        isOn = read()
    }
}

struct SettingsRow: Identifiable {
    enum Kind {
        case link(detail: @MainActor () -> String?, route: AppRoute)
        case toggle(SettingsToggle)
    }

    let id: String
    let title: String
    let kind: Kind

    static func link(
        _ title: String,
        route: AppRoute,
        detail: @escaping @MainActor () -> String? = { nil }
    ) -> SettingsRow {
        SettingsRow(id: "route." + route.rawValue, title: title, kind: .link(detail: detail, route: route))
    }

    static func toggle(_ id: String, _ toggle: SettingsToggle) -> SettingsRow {
        SettingsRow(id: "toggle." + id, title: toggle.title, kind: .toggle(toggle))
    }

    var route: AppRoute? {
        if case let .link(_, route) = kind { return route }
        return nil
    }
}

/// An external reference shown under a section, such as a data licence.
struct SettingsExternalLink {
    let title: String
    let url: URL
}

struct SettingsSection: Identifiable {
    let id: SettingsSectionID
    let title: String
    var footer: String?
    var footerLink: SettingsExternalLink? = nil
    let rows: [SettingsRow]
}

/// Sections contributed by the composed features, assembled at the composition root.
struct AppSettings {
    let sections: [SettingsSection]
    let developerTools: SettingsToggle

    init(sections: [SettingsSection], developerTools: SettingsToggle) {
        self.sections = sections.sorted { $0.id < $1.id }
        self.developerTools = developerTools
    }

    var linkedRoutes: [AppRoute] {
        sections.flatMap { $0.rows.compactMap(\.route) }
    }

    /// Fixed routes plus every route a composed section links to.
    var availableRoutes: Set<AppRoute> {
        AppRoute.fixedRoutes.union(linkedRoutes)
    }

    var toggles: [SettingsToggle] {
        sections.flatMap { section in
            section.rows.compactMap { row in
                if case let .toggle(toggle) = row.kind { return toggle }
                return nil
            }
        }
    }
}

struct SettingsView: View {
    let settings: AppSettings
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            ForEach(settings.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let footer = section.footer { Text(footer) }
                        if let link = section.footerLink { Link(link.title, destination: link.url) }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            settings.toggles.forEach { $0.reload() }
            refresh += 1
        }
    }

    @ViewBuilder
    private func rowView(_ row: SettingsRow) -> some View {
        switch row.kind {
        case let .link(detail, route):
            NavigationLink(value: route) {
                LabeledContent(row.title) {
                    if let detail = detail() { Text(detail) }
                }
            }
            .accessibilityIdentifier("settings." + route.rawValue)
        case let .toggle(toggle):
            SettingsToggleRow(toggle: toggle)
        }
    }
}

struct SettingsToggleRow: View {
    @ObservedObject var toggle: SettingsToggle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(toggle.title, isOn: Binding(get: { toggle.isOn }, set: { toggle.set($0) }))
                .disabled(!toggle.isEnabled)
            if let caption = toggle.caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
