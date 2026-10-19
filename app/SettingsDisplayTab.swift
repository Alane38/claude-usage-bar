import AppKit
import SwiftUI

/// Aperçu en direct de ce que la barre de menu affichera avec les réglages courants.
struct MenuBarPreview: View {
    @ObservedObject var usageManager: UsageManager
    var style: MenuBarStyle?

    var body: some View {
        let bar = MenuBarDisplay.state(style: style ?? usageManager.menuBarStyle, mode: usageManager.menuBarMode,
                                       sessionPercent: usageManager.sessionUsage, sessionResetsAt: usageManager.sessionResetsAt,
                                       weeklyPercent: usageManager.weeklyUsage, weeklyResetsAt: usageManager.weeklyResetsAt,
                                       showReset: usageManager.menuBarShowReset)
        let icon = usageManager.menuBarIcon(style: style)
        let image = icon.image
            ?? (NSApp.delegate as? AppDelegate)?.createSparkIcon(color: MenuBarIcons.color(for: icon.tone))
        HStack(spacing: 6) {
            if let image { Image(nsImage: image) }
            Text(bar.title.trimmingCharacters(in: .whitespaces)).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(8)
    }
}

struct DisplayTab: View {
    @ObservedObject var usageManager: UsageManager
    @AppStorage("appearance_mode") private var appearanceMode: String = "system"

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<UsageManager, T>) -> Binding<T> {
        Binding(get: { usageManager[keyPath: keyPath] },
                set: { usageManager[keyPath: keyPath] = $0; usageManager.saveDisplaySettings() })
    }

    var body: some View {
        Form {
            Section("Popover") {
                Picker("Disposition", selection: bind(\.popoverLayout)) {
                    ForEach(PopoverLayout.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(usageManager.popoverLayout.summary).font(.caption).foregroundColor(.secondary)
            }
            Section("Barre de menu") {
                Picker("Style", selection: bind(\.menuBarStyle)) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(usageManager.menuBarStyle.summary).font(.caption).foregroundColor(.secondary)
                if usageManager.menuBarStyle == .spark {
                    Picker("Valeur affichée", selection: bind(\.menuBarMode)) {
                        ForEach(MenuBarMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Toggle("Afficher le temps avant le reset", isOn: bind(\.menuBarShowReset))
                LabeledContent("Aperçu") { MenuBarPreview(usageManager: usageManager) }
            }
            Section("Apparence") {
                Picker("Thème", selection: $appearanceMode) {
                    Text("Système").tag("system")
                    Text("Sombre").tag("dark")
                    Text("Clair").tag("light")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { _ in (NSApp.delegate as? AppDelegate)?.applyAppearancePreference() }
            }
        }
        .formStyle(.grouped)
    }
}
