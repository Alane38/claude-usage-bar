import SwiftUI
import AppKit
import WebKit
import Carbon
import ServiceManagement

// Secondary text: system gray in dark; darker in light, where the vibrant
// ~50% gray over the white popover backing reads as washed out.
extension Color {
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .secondaryLabelColor
            : NSColor(white: 0.24, alpha: 1.0) // opaque: vibrancy washes out alpha grays
    })
}

// Main entry point
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var anchorWindow: NSWindow?
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var usageManager: UsageManager!
    var statusManager: StatusManager!
    var eventMonitor: Any?
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSUserNotification (deprecated but works without permissions for unsigned apps)
        NSLog("✅ App launched, notifications ready")

        // Create status bar item with variable length for compact display
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Create Claude logo as initial icon
            updateStatusIcon(percentage: 0)
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self

            // Force the button to be visible
            button.appearsDisabled = false
            button.isEnabled = true
        }

        // Initialize managers
        usageManager = UsageManager(statusItem: statusItem, delegate: self)
        statusManager = StatusManager()

        // Create popover
        popover = NSPopover()
        // Initial guess; SwiftUI's intrinsic size (capped at 600) will drive the actual size.
        popover.contentSize = NSSize(width: 360, height: 320)
        popover.behavior = .transient
        popover.delegate = self
        let hostingController = NSHostingController(rootView: PopoverView(
            usageManager: usageManager,
            statusManager: statusManager
        ))
        // Sans cela le contrôleur ne propage jamais sa taille : le popover reste à 320 pt
        // alors que le contenu est plus haut, et l'en-tête est rogné en haut.
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        // Appearance preference: "system" (default) tracks the macOS light/dark
        // setting; "dark"/"light" force one (dark was hard-forced in v1.3.2 and
        // users complained about losing light mode). Applied after the popover
        // exists so both NSApp and the popover get styled.
        applyAppearancePreference()

        // Re-apply when macOS flips light/dark, so a forced mode that matches
        // the system switches back to the native (inherited) rendering.
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The defaults key can lag the notification; re-resolve a tick later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.applyAppearancePreference()
            }
        }

        // Fetch initial data
        usageManager.fetchUsage()
        statusManager.fetch()

        // Limites, crédits Console et statut Anthropic : une fois par minute (5 min dans l'original),
        // ralenti à 5 min tant que l'API refuse (voir RefreshPolicy).
        scheduleRefresh()

        if CommandLine.arguments.contains("--diagnose") {
            print("diagnostic : cookie claude.ai en mémoire =", !usageManager.sessionCookie.isEmpty,
                  "| cookie Console =", !usageManager.consoleCookie.isEmpty,
                  "| problème trousseau =", usageManager.keychainIssue.isEmpty ? "aucun" : usageManager.keychainIssue)
            exit(0)
        }

        if CommandLine.arguments.contains("--probe-console") {
            DispatchQueue.global().async {
                self.usageManager.probeConsole()
                exit(0)
            }
        }

        // Options de vérification visuelle : appliquées au lancement, jamais enregistrées dans les réglages.
        if let layout = Snapshot.option("--layout").flatMap(PopoverLayout.init(rawValue:)) { usageManager.popoverLayout = layout }
        if let style = Snapshot.option("--menubar").flatMap(MenuBarStyle.init(rawValue:)) { usageManager.menuBarStyle = style }
        if CommandLine.arguments.contains("--reset-in-menubar") { usageManager.menuBarShowReset = true }
        if CommandLine.arguments.contains("--settings-window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.openSettings() }
        }

        if CommandLine.arguments.contains("--show") {
            // Mode développement : ouvre le popover au lancement, pour le vérifier sans cliquer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.openPopover() }
        }

        if let snapshotPath = Snapshot.outputPath {
            // Laisse le temps au statusline/réseau de remplir les données, puis rend le popover et quitte.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let layout = Snapshot.option("--layout").flatMap(PopoverLayout.init(rawValue:)) { self.usageManager.popoverLayout = layout }
                if let style = Snapshot.option("--menubar").flatMap(MenuBarStyle.init(rawValue:)) { self.usageManager.menuBarStyle = style }
                if CommandLine.arguments.contains("--demo") {
                    // Données fictives pour l'aperçu uniquement : jamais écrites ailleurs que dans l'image.
                    self.usageManager.sessionUsage = Snapshot.option("--session").flatMap(Int.init) ?? 8
                    self.usageManager.weeklyUsage = Snapshot.option("--weekly").flatMap(Int.init) ?? 37
                    self.usageManager.sessionResetsAt = Date().addingTimeInterval(Snapshot.option("--session-left").flatMap(Double.init) ?? (2 * 3600 + 14 * 60))
                    self.usageManager.weeklyResetsAt = Date().addingTimeInterval(2 * 86400 + 14 * 3600)
                    self.usageManager.lastUpdated = Date()
                    self.usageManager.hasFetchedData = true
                    self.usageManager.updatePercentages()
                    let deadline = Date().addingTimeInterval(16 * 86400)
                    self.usageManager.consoleBalance = ConsoleBalance(balance: 87.5, currency: "USD", spentThisPeriod: 12.5,
                                                                      periodResetsAt: deadline, nextExpiry: deadline,
                                                                      promoGranted: 100, promoName: "API credit (Max 5x)")
                    self.usageManager.consoleUpdatedAt = Date().addingTimeInterval(-120)
                }
                if CommandLine.arguments.contains("--menubar-styles") {
                    Snapshot.write(view: VStack(alignment: .leading, spacing: 10) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { style in
                            HStack(spacing: 12) {
                                Text(style.label).font(.caption).frame(width: 90, alignment: .leading)
                                MenuBarPreview(usageManager: self.usageManager, style: style)
                            }
                        }
                    }.padding(16), to: snapshotPath, size: NSSize(width: 320, height: 170))
                } else if CommandLine.arguments.contains("--settings") {
                    Snapshot.write(view: SettingsView(usageManager: self.usageManager, statusManager: self.statusManager),
                                   to: snapshotPath, size: NSSize(width: 560, height: 560))
                } else {
                    Snapshot.write(view: PopoverView(usageManager: self.usageManager, statusManager: self.statusManager),
                                   to: snapshotPath, size: NSSize(width: 360, height: 640))
                }
                NSApp.terminate(nil)
            }
        }

        // Le décompte avant reset de la barre de menu avance chaque minute, sans appel réseau.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.usageManager.refreshMenuBar()
        }

        // Set up Cmd+U keyboard shortcut
        setupKeyboardShortcut()
    }

    func applyAppearancePreference() {
        let mode = UserDefaults.standard.string(forKey: "appearance_mode") ?? "system"
        let systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let isDark: Bool
        switch mode {
        case "dark":  isDark = true
        case "light": isDark = false
        default:      isDark = systemIsDark
        }
        // Always set an explicit, resolved appearance ("System" resolves to the
        // current macOS setting) so every mode uses the same rendering path:
        // inherited "vibrant" rendering drops ProgressView tints (bars turn
        // accent-blue) and shades colors slightly differently, which made
        // System and Dark look different. Set on the popover too — it doesn't
        // reliably restyle from NSApp.appearance alone once created.
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        popover?.appearance = appearance
    }

    func setupKeyboardShortcut() {
        // Check Accessibility permissions
        checkAccessibilityPermissions()

        // Only register if user has the shortcut enabled
        if usageManager.shortcutEnabled {
            registerGlobalHotKey()
        }
    }

    func setShortcutEnabled(_ enabled: Bool) {
        if enabled {
            registerGlobalHotKey()
        } else {
            unregisterGlobalHotKey()
        }
    }

    func checkAccessibilityPermissions() {
        // Check if app has Accessibility permissions
        let trusted = AXIsProcessTrusted()

        if !trusted {
            NSLog("⚠️ Accessibility permissions not granted")
            // Show alert to guide user
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "ClaudeUsageBar needs Accessibility permission to use the Cmd+U keyboard shortcut.\n\nPlease enable it in:\nSystem Settings → Privacy & Security → Accessibility"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Skip for Now")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        } else {
            NSLog("✅ Accessibility permissions granted")
        }
    }

    func registerGlobalHotKey() {
        // Guard against double registration
        if hotKeyRef != nil { return }

        var hotKeyID = EventHotKeyID()
        // Use simple numeric ID instead of FourCharCode
        hotKeyID.signature = 0x436C5542 // 'ClUB' as hex
        hotKeyID.id = 1

        // Cmd+U key code
        let keyCode: UInt32 = 32 // 'U' key
        let modifiers: UInt32 = UInt32(cmdKey)

        // Create event spec for hotkey
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Install event handler
        var handler: EventHandlerRef?
        let callback: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            // Get the AppDelegate instance
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()

            // Toggle popover
            DispatchQueue.main.async {
                appDelegate.togglePopover()
            }

            return noErr
        }

        // Install the handler
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handler)

        // Register the hotkey
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr {
            NSLog("✅ Registered Cmd+U hotkey successfully")
        } else {
            NSLog("❌ Failed to register hotkey, status: \(status)")
        }
    }

    func unregisterGlobalHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
            NSLog("🗑️ Unregistered Cmd+U hotkey")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    let settingsController = SettingsWindowController()

    func openSettings() {
        popover.performClose(nil)
        settingsController.show(usageManager: usageManager, statusManager: statusManager)
    }

    private func scheduleRefresh() {
        Timer.scheduledTimer(withTimeInterval: usageManager.refreshPolicy.interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.usageManager.fetchUsage()
            self.statusManager.fetch()
            self.scheduleRefresh()
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right click - show menu
            let menu = NSMenu()
            let toggleItem = NSMenuItem(title: "Toggle Usage (⌘U)", action: #selector(togglePopover), keyEquivalent: "u")
            toggleItem.keyEquivalentModifierMask = .command
            menu.addItem(toggleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit ClaudeUsageBar", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click - toggle popover
            togglePopover()
        }
    }

    func openPopover() {
        if let button = statusItem.button {
            // Force UI refresh by updating percentages
            DispatchQueue.main.async {
                self.usageManager.updatePercentages()
            }

            if isStatusItemVisible {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            } else {
                showPopoverAtScreenCorner()
            }

            // Add event monitor to detect clicks outside the popover
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if self?.popover.isShown == true {
                    self?.closePopover()
                }
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)
        removeAnchorWindow()

        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// `image` nil = étincelle, colorée selon `tone` ; sinon le dessin fourni (double anneau, deux valeurs).
    func updateStatusIcon(percentage: Int, title: String? = nil, image: NSImage? = nil, tone: UsageTone = .ok) {
        guard let button = statusItem.button else { return }
        button.image = image ?? createSparkIcon(color: MenuBarIcons.color(for: tone))
        button.title = title ?? " \(percentage)%"
    }

    func createSparkIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()

        // SVG path: M8 1L9 6L13 3L10 7L15 8L10 9L13 13L9 10L8 15L7 10L3 13L6 9L1 8L6 7L3 3L7 6L8 1Z
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8, y: 1))
        path.line(to: NSPoint(x: 9, y: 6))
        path.line(to: NSPoint(x: 13, y: 3))
        path.line(to: NSPoint(x: 10, y: 7))
        path.line(to: NSPoint(x: 15, y: 8))
        path.line(to: NSPoint(x: 10, y: 9))
        path.line(to: NSPoint(x: 13, y: 13))
        path.line(to: NSPoint(x: 9, y: 10))
        path.line(to: NSPoint(x: 8, y: 15))
        path.line(to: NSPoint(x: 7, y: 10))
        path.line(to: NSPoint(x: 3, y: 13))
        path.line(to: NSPoint(x: 6, y: 9))
        path.line(to: NSPoint(x: 1, y: 8))
        path.line(to: NSPoint(x: 6, y: 7))
        path.line(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 7, y: 6))
        path.close()

        color.setFill()
        path.fill()

        image.unlockFocus()
        image.isTemplate = false

        return image
    }
}

// NSColor extension for hex conversion
extension NSColor {
    var hexString: String {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// Main entry point
@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

class UsageManager: ObservableObject {
    @Published var sessionUsage: Int = 0
    @Published var sessionLimit: Int = 100
    @Published var weeklyUsage: Int = 0
    @Published var weeklyLimit: Int = 100
    @Published var weeklySonnetUsage: Int = 0
    @Published var weeklySonnetLimit: Int = 100
    @Published var weeklyFableUsage: Int = 0
    @Published var weeklyFableLimit: Int = 100
    // Extra usage spend (from /overage_spend_limit). Shown only when there's spend.
    @Published var extraSpentMinor: Int = 0
    @Published var extraLimitMinor: Int = 0
    @Published var extraResetsAt: Date?
    @Published var freeCreditsMinor: Int = 0   // remaining free/promo credits (/prepaid/credits)
    // Banked usage-limit resets the user can trigger on claude.ai (e.g. the Opus 5.5
    // launch grant). Read-only here: using one is a POST on /reset_rate_limits.
    @Published var limitResetsLeft: Int = 0
    @Published var limitResetsEndAt: Date?
    @Published var creditCurrency: String = "USD"
    @Published var hasCreditUsage: Bool = false
    @Published var sessionResetsAt: Date?
    @Published var weeklyResetsAt: Date?
    @Published var weeklySonnetResetsAt: Date?
    @Published var weeklyFableResetsAt: Date?
    @Published var lastUpdated: Date = Date()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var usageNotificationsEnabled: Bool = true
    @Published var statusNotificationsEnabled: Bool = true
    @Published var openAtLogin: Bool = false
    @Published var hasWeeklySonnet: Bool = false
    @Published var hasWeeklyFable: Bool = false
    @Published var hasFetchedData: Bool = false
    @Published var isAccessibilityEnabled: Bool = false
    @Published var shortcutEnabled: Bool = true
    @Published var menuBarMode: MenuBarMode = .session
    @Published var menuBarShowReset: Bool = false
    @Published var menuBarStyle: MenuBarStyle = .spark
    @Published var menuBarShowText: Bool = true
    @Published var popoverLayout: PopoverLayout = .gauges
    // Crédits API mensuels (Max/Team) : saisis à la main, la tuile n'apparaît qu'une fois la fin de cycle définie.
    @Published var apiCreditMonthly: Double = 100
    @Published var apiCreditSpent: Double = 0
    @Published var apiCreditCycleEnd: Date?

    private var statusItem: NSStatusItem?
    var sessionCookie: String = ""
    var consoleCookie: String = ""
    var lastAutoImport: Date?
    @Published var consoleBalance: ConsoleBalance?
    @Published var consoleUpdatedAt: Date?
    @Published var consoleStatus: String = ""
    @Published var browserImportReport: String = ""
    @Published var usageSource: String = ""
    /// Vrai quand l'API a refusé : rafraîchissement ralenti à 5 min jusqu'au prochain succès.
    @Published var isRefreshSlowed: Bool = false
    var refreshPolicy = RefreshPolicy()
    @Published var keychainIssue: String = ""
    private weak var delegate: AppDelegate?
    private var lastNotifiedThreshold: Int = 0

    init(statusItem: NSStatusItem?, delegate: AppDelegate? = nil) {
        self.statusItem = statusItem
        self.delegate = delegate
        loadSessionCookie()
        loadConsoleCookie()
        loadSettings()
        checkAccessibilityStatus()
    }

    func checkAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private static let cookieKeychain = KeychainStore(service: "com.alane.usagebar")
    private static let cookieAccount = "claude_session_cookie"

    /// Lit le cookie dans le Keychain. Un cookie resté en clair dans UserDefaults (anciennes versions)
    /// est migré une fois, puis effacé du .plist.
    func loadSessionCookie() {
        // Les builds de développement n'ont pas l'autorisation du trousseau : `--no-keychain` évite la fenêtre de mot de passe.
        guard !CommandLine.arguments.contains("--no-keychain") else { return }
        let stored = Self.cookieKeychain.readResult(account: Self.cookieAccount)
        if let value = stored.value {
            sessionCookie = value
            return
        }
        if stored.status != errSecItemNotFound {
            // L'élément existe mais macOS refuse la lecture (autorisation du trousseau non accordée).
            keychainIssue = "Trousseau : accès refusé (code \(stored.status))"
        }
        guard let legacy = UserDefaults.standard.string(forKey: "claude_session_cookie") else { return }
        sessionCookie = legacy
        if Self.cookieKeychain.write(legacy, account: Self.cookieAccount) {
            UserDefaults.standard.removeObject(forKey: "claude_session_cookie")
        }
    }

    func loadSettings() {
        // Migrate from legacy single notifications_enabled flag (pre-v1.1) to split flags
        let hasUsageKey  = UserDefaults.standard.object(forKey: "usage_notifications_enabled")  != nil
        let hasStatusKey = UserDefaults.standard.object(forKey: "status_notifications_enabled") != nil

        if !hasUsageKey || !hasStatusKey {
            let legacyHasKey = UserDefaults.standard.object(forKey: "notifications_enabled") != nil
            let legacyValue  = legacyHasKey ? UserDefaults.standard.bool(forKey: "notifications_enabled") : true
            if !hasUsageKey {
                usageNotificationsEnabled = legacyValue
                UserDefaults.standard.set(legacyValue, forKey: "usage_notifications_enabled")
            }
            if !hasStatusKey {
                statusNotificationsEnabled = legacyValue
                UserDefaults.standard.set(legacyValue, forKey: "status_notifications_enabled")
            }
        }
        if hasUsageKey {
            usageNotificationsEnabled = UserDefaults.standard.bool(forKey: "usage_notifications_enabled")
        }
        if hasStatusKey {
            statusNotificationsEnabled = UserDefaults.standard.bool(forKey: "status_notifications_enabled")
        }

        // Reflect the real system login-item state, not just a stored bool.
        if #available(macOS 13.0, *) {
            openAtLogin = (SMAppService.mainApp.status == .enabled)
        } else {
            openAtLogin = UserDefaults.standard.bool(forKey: "open_at_login")
        }
        lastNotifiedThreshold = UserDefaults.standard.integer(forKey: "last_notified_threshold")
        // Default shortcut to enabled if not previously set
        if UserDefaults.standard.object(forKey: "shortcut_enabled") == nil {
            shortcutEnabled = true
        } else {
            shortcutEnabled = UserDefaults.standard.bool(forKey: "shortcut_enabled")
        }
        loadDisplaySettings()
    }

    private func loadDisplaySettings() {
        let defaults = UserDefaults.standard
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: "menubar_mode") ?? "") ?? .session
        menuBarShowReset = defaults.bool(forKey: "menubar_show_reset")
        menuBarShowText = defaults.object(forKey: "menubar_show_text") as? Bool ?? true
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menubar_style") ?? "") ?? .spark
        popoverLayout = PopoverLayout(rawValue: defaults.string(forKey: "popover_layout") ?? "") ?? .gauges
        if defaults.object(forKey: "api_credit_monthly") != nil {
            apiCreditMonthly = defaults.double(forKey: "api_credit_monthly")
        }
        apiCreditSpent = defaults.double(forKey: "api_credit_spent")
        apiCreditCycleEnd = defaults.object(forKey: "api_credit_cycle_end") as? Date
    }

    func saveDisplaySettings() {
        let defaults = UserDefaults.standard
        defaults.set(menuBarMode.rawValue, forKey: "menubar_mode")
        defaults.set(menuBarShowReset, forKey: "menubar_show_reset")
        defaults.set(menuBarShowText, forKey: "menubar_show_text")
        defaults.set(menuBarStyle.rawValue, forKey: "menubar_style")
        defaults.set(popoverLayout.rawValue, forKey: "popover_layout")
        defaults.set(apiCreditMonthly, forKey: "api_credit_monthly")
        defaults.set(apiCreditSpent, forKey: "api_credit_spent")
        if let cycleEnd = apiCreditCycleEnd {
            defaults.set(cycleEnd, forKey: "api_credit_cycle_end")
        } else {
            defaults.removeObject(forKey: "api_credit_cycle_end")
        }
        refreshMenuBar()
    }

    var sessionForecast: WindowForecast? {
        guard let resetsAt = sessionResetsAt else { return nil }
        return UsageForecast.forecast(usedPercent: Double(sessionUsage), resetsAt: resetsAt, windowLength: UsageForecast.sessionLength)
    }

    var weeklyForecast: WindowForecast? {
        guard let resetsAt = weeklyResetsAt else { return nil }
        return UsageForecast.forecast(usedPercent: Double(weeklyUsage), resetsAt: resetsAt, windowLength: UsageForecast.weekLength)
    }

    var apiCredits: ApiCredits? {
        apiCreditCycleEnd.map { ApiCredits(monthlyAmount: apiCreditMonthly, spent: apiCreditSpent, cycleEndsAt: $0) }
    }

    func saveSettings() {
        UserDefaults.standard.set(usageNotificationsEnabled,  forKey: "usage_notifications_enabled")
        UserDefaults.standard.set(statusNotificationsEnabled, forKey: "status_notifications_enabled")
        UserDefaults.standard.set(openAtLogin, forKey: "open_at_login")
        UserDefaults.standard.set(shortcutEnabled, forKey: "shortcut_enabled")
        UserDefaults.standard.synchronize()
    }

    // Actually register/unregister the app as a macOS login item.
    func applyLoginItem(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            NSLog("🔑 Login item \(enabled ? "registered" : "unregistered")")
        } catch {
            NSLog("❌ Login item error: \(error.localizedDescription)")
        }
    }

    func saveSessionCookie(_ cookie: String) {
        NSLog("ClaudeUsage: Saving cookie, length: \(cookie.count)")
        sessionCookie = cookie
        if !Self.cookieKeychain.write(cookie, account: Self.cookieAccount) {
            NSLog("ClaudeUsage: Keychain write failed, cookie kept in memory only")
        }
    }

    func clearSessionCookie() {
        NSLog("ClaudeUsage: Clearing cookie")
        sessionCookie = ""
        Self.cookieKeychain.delete(account: Self.cookieAccount)
        UserDefaults.standard.removeObject(forKey: "claude_session_cookie")

        // Reset all data
        sessionUsage = 0
        weeklyUsage = 0
        weeklySonnetUsage = 0
        weeklyFableUsage = 0
        sessionResetsAt = nil
        weeklyResetsAt = nil
        weeklySonnetResetsAt = nil
        weeklyFableResetsAt = nil
        extraSpentMinor = 0
        extraLimitMinor = 0
        extraResetsAt = nil
        freeCreditsMinor = 0
        limitResetsLeft = 0
        limitResetsEndAt = nil
        hasCreditUsage = false
        hasFetchedData = false
        hasWeeklySonnet = false
        hasWeeklyFable = false
        errorMessage = nil
        lastNotifiedThreshold = 0
        UserDefaults.standard.set(0, forKey: "last_notified_threshold")

        // Update status bar to show 0%
        delegate?.updateStatusIcon(percentage: 0)

        NSLog("ClaudeUsage: Cookie cleared, data reset")
    }

    func fetchOrganizationId(completion: @escaping (String?) -> Void) {
        // Get org ID from the lastActiveOrg cookie value
        let cookieParts = sessionCookie.components(separatedBy: ";")
        for part in cookieParts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                let orgId = trimmed.replacingOccurrences(of: "lastActiveOrg=", with: "")
                NSLog("📋 Found org ID in cookie")
                completion(orgId)
                return
            }
        }

        // If not in cookie, fetch from bootstrap
        guard let url = URL(string: "https://claude.ai/api/bootstrap") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionCookie)", forHTTPHeaderField: "Cookie")

        NSLog("📡 Fetching bootstrap to get org ID...")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["account"] as? [String: Any],
                  let lastActiveOrgId = account["lastActiveOrgId"] as? String else {
                NSLog("❌ Could not parse org ID from bootstrap")
                completion(nil)
                return
            }
            NSLog("✅ Got org ID from bootstrap")
            completion(lastActiveOrgId)
        }.resume()
    }

    func noteFetchResult(statusCode: Int) {
        refreshPolicy.record(statusCode: statusCode)
        isRefreshSlowed = refreshPolicy.isSlowed
    }

    /// Applique les limites lues dans le statusline de Claude Code. Retourne false si la source est absente.
    @discardableResult
    func applyStatuslineUsage() -> Bool {
        guard let usage = StatuslineUsage.load() else { return false }
        // Un statusline plus ancien que la dernière donnée affichée ne doit pas la remplacer :
        // au Refresh, il écrasait les vraies valeurs réseau le temps du chargement.
        guard StatuslineUsage.shouldReplace(displayedAt: lastUpdated, hasDisplayedData: hasFetchedData, capturedAt: usage.capturedAt) else { return true }
        if let session = usage.fiveHour {
            sessionUsage = Int(session.usedPercentage)
            sessionResetsAt = session.resetsAt
        }
        if let weekly = usage.sevenDay {
            weeklyUsage = Int(weekly.usedPercentage)
            weeklyResetsAt = weekly.resetsAt
        }
        lastUpdated = usage.capturedAt
        usageSource = "statusline"
        errorMessage = nil
        hasFetchedData = true
        updatePercentages()
        updateStatusBar()
        return true
    }

    func fetchUsage() {
        // Sans cookie, le statusline suffit ; avec cookie, il sert de repli si le réseau échoue.
        let hasStatusline = applyStatuslineUsage()
        fetchConsoleBalance()
        guard !sessionCookie.isEmpty else {
            if !hasStatusline {
                DispatchQueue.main.async {
                    self.errorMessage = "Session cookie not set"
                    self.updateStatusBar()
                }
            }
            return
        }

        isLoading = true
        errorMessage = nil

        // Extract org ID from cookie
        fetchOrganizationId { [weak self] orgId in
            guard let self = self, let orgId = orgId else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Could not get org ID from cookie"
                    self?.isLoading = false
                }
                return
            }

            self.fetchUsageWithOrgId(orgId)
            self.fetchExtraUsage(orgId)
            self.fetchFreeCredits(orgId)
            self.fetchLimitResets(orgId)
        }
    }

    // Usage-limit resets the account can still use. claude.ai's Settings > Usage reads
    // the same `cedar_ember` object from /usage with `cedar_ember=1`; we only GET it.
    func fetchLimitResets(_ orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage?cedar_ember=1&skip_spend=1") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                let (left, endAt) = Self.parseLimitResets(json["cedar_ember"])
                self.limitResetsLeft = left
                self.limitResetsEndAt = endAt
                NSLog("🔄 Limit resets available: \(left)")
            }
        }.resume()
    }

    /// Counts resets still usable across grants (not paused, inside their window)
    /// and returns the earliest end date among them.
    static func parseLimitResets(_ raw: Any?, now: Date = Date()) -> (Int, Date?) {
        guard let obj = raw as? [String: Any],
              (obj["eligible"] as? Bool) == true,
              let grants = obj["grants"] as? [[String: Any]] else { return (0, nil) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? {
            guard let s = v as? String else { return nil }
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }
        var total = 0
        var earliestEnd: Date?
        for g in grants {
            let left = (g["resets_left"] as? Int) ?? 0
            guard left > 0, (g["paused"] as? Bool) != true,
                  let end = date(g["ends_at"]), end > now else { continue }
            if let start = date(g["starts_at"]), start > now { continue }
            total += left
            earliestEnd = min(earliestEnd ?? end, end)
        }
        return (total, earliestEnd)
    }

    // Remaining free/promo credits (balance) from /prepaid/credits.
    func fetchFreeCredits(_ orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/prepaid/credits") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                // `amount` is the current balance; fall back to summing remaining tranches.
                if let amount = json["amount"] as? Int {
                    self.freeCreditsMinor = amount
                } else {
                    var remaining = 0
                    for key in ["tranches", "promo_tranches"] {
                        if let arr = json[key] as? [[String: Any]] {
                            for t in arr { remaining += (t["remaining_amount_minor_units"] as? Int) ?? 0 }
                        }
                    }
                    self.freeCreditsMinor = remaining
                }
                if let cur = json["currency"] as? String { self.creditCurrency = cur }
                NSLog("🎁 Free credits left: \(self.freeCreditsMinor) \(self.creditCurrency)")
            }
        }.resume()
    }

    // Extra usage spend + monthly limit live on a separate endpoint (not /usage).
    func fetchExtraUsage(_ orgId: String) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/overage_spend_limit") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                let spent = (json["used_credits"] as? Int) ?? 0
                let limit = (json["monthly_credit_limit"] as? Int) ?? 0
                self.extraSpentMinor = spent
                self.extraLimitMinor = limit
                self.creditCurrency = (json["currency"] as? String) ?? "USD"
                if let resetStr = json["disabled_until"] as? String {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    self.extraResetsAt = f.date(from: resetStr) ?? ISO8601DateFormatter().date(from: resetStr)
                }
                self.hasCreditUsage = spent > 0
                NSLog("💳 Extra usage: \(spent)/\(limit) \(self.creditCurrency)")
            }
        }.resume()
    }

    func fetchUsageWithOrgId(_ orgId: String) {
        let urlString = "https://claude.ai/api/organizations/\(orgId)/usage"

        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use the full cookie string (user provides all cookies, not just sessionKey)
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("claude.ai", forHTTPHeaderField: "authority")

        NSLog("🔍 Fetching usage")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    NSLog("❌ Error: \(error.localizedDescription)")
                    self?.errorMessage = "Network error"
                    self?.updateStatusBar()
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    self?.updateStatusBar()
                    return
                }

                NSLog("📡 Status: \(httpResponse.statusCode)")
                self?.noteFetchResult(statusCode: httpResponse.statusCode)

                if httpResponse.statusCode == 200, let data = data {
                    self?.parseUsageData(data)
                } else {
                    self?.errorMessage = "HTTP \(httpResponse.statusCode)"
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403,
                       self?.shouldAutoImport() == true, self?.importBrowserCookies() == true {
                        self?.fetchUsage()
                    }
                }

                self?.updateStatusBar()
            }
        }.resume()
    }

    func parseUsageData(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid JSON"
                return
            }

            NSLog("📊 Parsing usage data...")

            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Parse the actual claude.ai response format
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let sessionUtil = fiveHour["utilization"] as? Double {
                    sessionUsage = Int(sessionUtil)
                    sessionLimit = 100
                }
                if let resetsAtString = fiveHour["resets_at"] as? String {
                    NSLog("🕐 Session resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        sessionResetsAt = resetsAt
                        NSLog("✅ Parsed session reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse session reset time")
                    }
                }
            }

            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let weeklyUtil = sevenDay["utilization"] as? Double {
                    weeklyUsage = Int(weeklyUtil)
                    weeklyLimit = 100
                }
                if let resetsAtString = sevenDay["resets_at"] as? String {
                    NSLog("🕐 Weekly resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        weeklyResetsAt = resetsAt
                        NSLog("✅ Parsed weekly reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse weekly reset time")
                    }
                }
            }

            // Check for seven_day_sonnet (Pro plan feature)
            if let sevenDaySonnet = json["seven_day_sonnet"] as? [String: Any] {
                hasWeeklySonnet = true
                if let sonnetUtil = sevenDaySonnet["utilization"] as? Double {
                    weeklySonnetUsage = Int(sonnetUtil)
                    weeklySonnetLimit = 100
                }
                if let resetsAtString = sevenDaySonnet["resets_at"] as? String {
                    NSLog("🕐 Weekly Sonnet resets_at string: \(resetsAtString)")
                    if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                        weeklySonnetResetsAt = resetsAt
                        NSLog("✅ Parsed weekly Sonnet reset time: \(resetsAt)")
                    } else {
                        NSLog("❌ Failed to parse weekly Sonnet reset time")
                    }
                }
            } else {
                hasWeeklySonnet = false
            }

            // Fable is a new, separately-counted model. It isn't a top-level
            // key like seven_day_sonnet — it lives in the `limits` array as a
            // model-scoped weekly limit (scope.model.display_name == "Fable").
            // The bar is only surfaced in the UI when usage is above 1%.
            hasWeeklyFable = false
            if let limits = json["limits"] as? [[String: Any]] {
                let fableLimit = limits.first { entry in
                    let scope = entry["scope"] as? [String: Any]
                    let model = scope?["model"] as? [String: Any]
                    return (model?["display_name"] as? String) == "Fable"
                }
                if let fable = fableLimit {
                    hasWeeklyFable = true
                    // `percent` may decode as Int or Double depending on payload.
                    if let p = fable["percent"] as? Int {
                        weeklyFableUsage = p
                    } else if let p = fable["percent"] as? Double {
                        weeklyFableUsage = Int(p)
                    }
                    weeklyFableLimit = 100
                    if let resetsAtString = fable["resets_at"] as? String {
                        NSLog("🕐 Weekly Fable resets_at string: \(resetsAtString)")
                        if let resetsAt = iso8601Formatter.date(from: resetsAtString) {
                            weeklyFableResetsAt = resetsAt
                            NSLog("✅ Parsed weekly Fable reset time: \(resetsAt)")
                        } else {
                            NSLog("❌ Failed to parse weekly Fable reset time")
                        }
                    }
                }
            }

            // (Prepaid usage credits are fetched separately from /prepaid/credits.)

            // Log what we found
            NSLog("✅ Parsed: Session \(sessionUsage)%, Weekly \(weeklyUsage)%\(hasWeeklySonnet ? ", Weekly Sonnet \(weeklySonnetUsage)%" : "")\(hasWeeklyFable ? ", Weekly Fable \(weeklyFableUsage)%" : "")")

            lastUpdated = Date()
            usageSource = "claude.ai"
            errorMessage = nil
            hasFetchedData = true

            // Update percentage values for progress bars
            updatePercentages()
        } catch {
            NSLog("❌ Parse error: \(error.localizedDescription)")
            errorMessage = "Parse error"
        }
    }

    func updateStatusBar() {
        let sessionPercent = Int((Double(sessionUsage) / Double(sessionLimit)) * 100)

        refreshMenuBar()

        // Check for notification thresholds
        checkNotificationThresholds(percentage: sessionPercent)
    }

    /// Redessine l'icône et le titre sans toucher aux notifications (appelé aussi chaque minute pour le décompte).
    func refreshMenuBar() {
        let bar = MenuBarDisplay.state(style: menuBarStyle, mode: menuBarMode,
                                       sessionPercent: sessionUsage, sessionResetsAt: sessionResetsAt,
                                       weeklyPercent: weeklyUsage, weeklyResetsAt: weeklyResetsAt,
                                       showReset: menuBarShowReset, showText: menuBarShowText)
        let icon = menuBarIcon()
        delegate?.updateStatusIcon(percentage: bar.percent, title: bar.title, image: icon.image, tone: icon.tone)
    }

    func checkNotificationThresholds(percentage: Int) {
        NSLog("🔔 Checking notifications: percentage=\(percentage)%, enabled=\(usageNotificationsEnabled), lastNotified=\(lastNotifiedThreshold)%")

        guard usageNotificationsEnabled else {
            NSLog("⚠️ Usage notifications disabled")
            return
        }

        let thresholds = [25, 50, 75, 90]

        for threshold in thresholds {
            if percentage >= threshold && lastNotifiedThreshold < threshold {
                NSLog("📬 Sending notification for \(threshold)% threshold")
                sendNotification(percentage: percentage, threshold: threshold)
                lastNotifiedThreshold = threshold
                // Persist the threshold
                UserDefaults.standard.set(lastNotifiedThreshold, forKey: "last_notified_threshold")
                UserDefaults.standard.synchronize()
            }
        }

        // Reset if usage drops below current threshold
        if percentage < lastNotifiedThreshold {
            let newThreshold = thresholds.filter { $0 <= percentage }.last ?? 0
            NSLog("🔄 Resetting notification threshold from \(lastNotifiedThreshold)% to \(newThreshold)%")
            lastNotifiedThreshold = newThreshold
            UserDefaults.standard.set(lastNotifiedThreshold, forKey: "last_notified_threshold")
            UserDefaults.standard.synchronize()
        }
    }

    func sendNotification(percentage: Int, threshold: Int) {
        let notification = NSUserNotification()
        notification.title = "Claude Usage Alert"
        notification.informativeText = "You've reached \(percentage)% of your 5-hour session limit"
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
        NSLog("📬 Sent notification for \(threshold)% threshold")
    }

    func sendTestNotification() {
        NSLog("🔔 Test notification button clicked")

        let notification = NSUserNotification()
        notification.title = "Claude Usage Alert"
        notification.informativeText = "Test notification - You've reached 75% of your 5-hour session limit"
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
        NSLog("📬 Test notification sent successfully")
    }

    @Published var sessionPercentage: Double = 0.0
    @Published var weeklyPercentage: Double = 0.0
    @Published var weeklySonnetPercentage: Double = 0.0
    @Published var weeklyFablePercentage: Double = 0.0

    func updatePercentages() {
        sessionPercentage = Double(sessionUsage) / Double(sessionLimit)
        weeklyPercentage = Double(weeklyUsage) / Double(weeklyLimit)
        weeklySonnetPercentage = Double(weeklySonnetUsage) / Double(weeklySonnetLimit)
        weeklyFablePercentage = Double(weeklyFableUsage) / Double(weeklyFableLimit)
    }
}

// MARK: - Anthropic Service Status

struct StatusIncident: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // investigating | identified | monitoring | resolved
    let latestUpdate: String
    let updatedAt: Date?
    let componentIds: [String]
}

struct AffectedComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // degraded_performance | partial_outage | major_outage
}

struct StatusComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String           // operational | degraded_performance | ...
}

private let defaultTrackedComponents: [StatusComponent] = [
    StatusComponent(id: "c-claude-ai",      name: "claude.ai",                          status: "operational"),
    StatusComponent(id: "c-claude-console", name: "Claude Console (platform.claude.com)", status: "operational"),
    StatusComponent(id: "c-claude-api",     name: "Claude API (api.anthropic.com)",     status: "operational"),
    StatusComponent(id: "c-claude-code",    name: "Claude Code",                         status: "operational"),
    StatusComponent(id: "c-claude-cowork",  name: "Claude Cowork",                       status: "operational"),
    StatusComponent(id: "c-claude-gov",     name: "Claude for Government",              status: "operational"),
]

private let defaultTrackedComponentIdSet: Set<String> = Set(
    defaultTrackedComponents.map { $0.id }.filter { $0 != "c-claude-gov" }
)

class StatusManager: ObservableObject {
    @Published var indicator: String = "none"        // none | minor | major | critical (raw, global)
    @Published var statusDescription: String = "All systems operational"
    @Published var incidents: [StatusIncident] = []
    @Published var affectedComponents: [AffectedComponent] = []
    @Published var allComponents: [StatusComponent] = defaultTrackedComponents
    @Published var selectedComponentIds: Set<String> = defaultTrackedComponentIdSet
    @Published var lastUpdated: Date?
    @Published var hasFetched: Bool = false

    // Canonical URL (status.anthropic.com 302-redirects here)
    private let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    init() {
        if let saved = UserDefaults.standard.array(forKey: "tracked_component_ids") as? [String] {
            selectedComponentIds = Set(saved)
        }
        // Clean up legacy debug pref if present
        UserDefaults.standard.removeObject(forKey: "status_preview_mode")
    }

    func toggleComponent(_ id: String) {
        if selectedComponentIds.contains(id) {
            selectedComponentIds.remove(id)
        } else {
            selectedComponentIds.insert(id)
        }
        UserDefaults.standard.set(Array(selectedComponentIds), forKey: "tracked_component_ids")
    }

    func isTracked(_ id: String) -> Bool {
        selectedComponentIds.contains(id)
    }

    // MARK: - Filtered/effective views (respect tracked components)

    var filteredAffectedComponents: [AffectedComponent] {
        affectedComponents.filter { selectedComponentIds.contains($0.id) }
    }

    var filteredIncidents: [StatusIncident] {
        incidents.filter { incident in
            guard !incident.componentIds.isEmpty else { return true }
            return incident.componentIds.contains(where: { selectedComponentIds.contains($0) })
        }
    }

    var effectiveIndicator: String {
        let trackedComponents = allComponents.filter { selectedComponentIds.contains($0.id) }
        let max = trackedComponents.map { severity(for: $0.status) }.max() ?? 0
        switch max {
        case 0:  return "none"
        case 1:  return "minor"
        case 2:  return "major"
        default: return "critical"
        }
    }

    private func severity(for componentStatus: String) -> Int {
        switch componentStatus {
        case "operational":          return 0
        case "under_maintenance":    return 1
        case "degraded_performance": return 1
        case "partial_outage":       return 2
        case "major_outage":         return 3
        default:                     return 0
        }
    }

    func fetch() {
        let request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            self.parse(data)
        }.resume()
    }

    private func parse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let indicator = status["indicator"] as? String,
              let desc = status["description"] as? String else {
            return
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var parsedIncidents: [StatusIncident] = []
        if let raw = json["incidents"] as? [[String: Any]] {
            for inc in raw {
                guard let id = inc["id"] as? String,
                      let name = inc["name"] as? String,
                      let st = inc["status"] as? String else { continue }
                if st == "resolved" || st == "postmortem" { continue }
                let updates = inc["incident_updates"] as? [[String: Any]] ?? []
                let latest = (updates.first?["body"] as? String) ?? ""
                let dateStr = (updates.first?["created_at"] as? String) ?? (inc["updated_at"] as? String)
                let updatedAt = dateStr.flatMap { iso.date(from: $0) ?? isoNoFrac.date(from: $0) }
                let compIds = (inc["components"] as? [[String: Any]] ?? [])
                    .compactMap { $0["id"] as? String }
                parsedIncidents.append(StatusIncident(
                    id: id, name: name, status: st, latestUpdate: latest,
                    updatedAt: updatedAt,
                    componentIds: compIds
                ))
            }
        }

        var parsedAffected: [AffectedComponent] = []
        var parsedAll: [StatusComponent] = []
        if let raw = json["components"] as? [[String: Any]] {
            for c in raw {
                guard let id = c["id"] as? String,
                      let name = c["name"] as? String,
                      let st = c["status"] as? String else { continue }
                parsedAll.append(StatusComponent(id: id, name: name, status: st))
                if st != "operational" {
                    parsedAffected.append(AffectedComponent(id: id, name: name, status: st))
                }
            }
        }

        DispatchQueue.main.async {
            let isFirstFetch = !self.hasFetched

            self.indicator = indicator
            self.statusDescription = desc
            self.incidents = parsedIncidents
            self.affectedComponents = parsedAffected
            if !parsedAll.isEmpty {
                self.allComponents = parsedAll
                // First time we see real components: track all except Claude for Government by default
                if UserDefaults.standard.array(forKey: "tracked_component_ids") == nil {
                    let defaultIds = parsedAll
                        .filter { !$0.name.localizedCaseInsensitiveContains("Government") }
                        .map { $0.id }
                    self.selectedComponentIds = Set(defaultIds)
                    UserDefaults.standard.set(Array(self.selectedComponentIds),
                                              forKey: "tracked_component_ids")
                }
            }
            self.lastUpdated = Date()
            self.hasFetched = true

            // Notify on transitions of EFFECTIVE (filtered) indicator
            let effective = self.effectiveIndicator
            let previous = UserDefaults.standard.string(forKey: "last_effective_indicator")
            if !isFirstFetch, let previous = previous, previous != effective {
                self.notifyStatusChange(to: effective, description: desc)
            }
            UserDefaults.standard.set(effective, forKey: "last_effective_indicator")
        }
    }

    private func notifyStatusChange(to indicator: String, description: String) {
        guard UserDefaults.standard.bool(forKey: "status_notifications_enabled") else { return }

        let notification = NSUserNotification()
        if indicator == "none" {
            notification.title = "Claude is back online"
            notification.informativeText = "All systems operational"
        } else {
            notification.title = "Claude status: \(description)"
            notification.informativeText = "Visit status.anthropic.com for details"
        }
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        NSLog("📬 Sent status-change notification: \(indicator)")
    }
}

// Custom NSTextField that properly handles paste
class CustomTextField: NSTextField {
    var onTextChange: ((String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if (event.modifierFlags.contains(.command)) {
                switch event.charactersIgnoringModifiers {
                case "v":
                    if let string = NSPasteboard.general.string(forType: .string) {
                        self.stringValue = string
                        onTextChange?(string)
                        NSLog("ClaudeUsage: Pasted text length: \(string.count)")
                        return true
                    }
                case "a":
                    self.currentEditor()?.selectAll(nil)
                    return true
                case "c":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.stringValue, forType: .string)
                    return true
                case "x":
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.stringValue, forType: .string)
                    self.stringValue = ""
                    onTextChange?("")
                    return true
                default:
                    break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?(self.stringValue)
    }
}

// Custom TextView that ensures keyboard commands work
class PasteableNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v": // Paste
                paste(nil)
                return true
            case "c": // Copy
                copy(nil)
                return true
            case "x": // Cut
                cut(nil)
                return true
            case "a": // Select All
                selectAll(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// Multi-line text field with proper paste support
struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = PasteableNSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true

        // Enable wrapping
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? PasteableNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
