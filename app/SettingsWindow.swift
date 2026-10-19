import AppKit
import SwiftUI

/// Fenêtre de réglages séparée du popover.
final class SettingsWindowController {
    private var window: NSWindow?

    func show(usageManager: UsageManager, statusManager: StatusManager) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(usageManager: usageManager, statusManager: statusManager))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Réglages de ClaudeUsageBar"
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 560, height: 560))
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var statusManager: StatusManager

    var body: some View {
        TabView {
            DisplayTab(usageManager: usageManager)
                .tabItem { Label("Affichage", systemImage: "paintbrush") }
            ConnectionsTab(usageManager: usageManager)
                .tabItem { Label("Connexions", systemImage: "link") }
            CreditsTab(usageManager: usageManager)
                .tabItem { Label("Crédits", systemImage: "creditcard") }
            AlertsTab(usageManager: usageManager, statusManager: statusManager)
                .tabItem { Label("Alertes", systemImage: "bell") }
            GeneralTab(usageManager: usageManager)
                .tabItem { Label("Général", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 560)
    }
}
