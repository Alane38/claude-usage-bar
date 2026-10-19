import SwiftUI
import AppKit
import WebKit
import Carbon
import ServiceManagement

extension UsageManager {
    func checkAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    static let cookieStore = AppSecrets.store
    static let cookieAccount = AppSecrets.claudeAccount

    /// Lit le cookie dans le Keychain. Un cookie resté en clair dans UserDefaults (anciennes versions)
    /// est migré une fois, puis effacé du .plist.
    func loadSessionCookie() {
        guard !CommandLine.arguments.contains("--no-keychain") else { return }
        let stored = Self.cookieStore.readResult(account: Self.cookieAccount)
        if let value = stored.value {
            sessionCookie = value
            return
        }
        if stored.status != errSecItemNotFound {
            // L'élément existe mais la lecture est refusée (autorisation du trousseau non accordée).
            keychainIssue = "Stockage des secrets : accès refusé (code \(stored.status))"
        }
        guard let legacy = UserDefaults.standard.string(forKey: "claude_session_cookie") else { return }
        sessionCookie = legacy
        if Self.cookieStore.write(legacy, account: Self.cookieAccount) {
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

    func loadDisplaySettings() {
        let defaults = UserDefaults.standard
        for style in MenuBarStyle.allCases {
            let key = style == .spark ? "menubar_mode" : "menubar_mode_\(style.rawValue)"
            menuBarModes[style] = MenuBarMode(rawValue: defaults.string(forKey: key) ?? "") ?? MenuBarMode.defaultMode(for: style)
        }
        menuBarShowReset = defaults.bool(forKey: "menubar_show_reset")
        menuBarShowText = defaults.object(forKey: "menubar_show_text") as? Bool ?? true
        exportsForecast = defaults.object(forKey: "export_forecast") as? Bool ?? true
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
        for (style, mode) in menuBarModes {
            defaults.set(mode.rawValue, forKey: style == .spark ? "menubar_mode" : "menubar_mode_\(style.rawValue)")
        }
        defaults.set(menuBarShowReset, forKey: "menubar_show_reset")
        defaults.set(menuBarShowText, forKey: "menubar_show_text")
        defaults.set(exportsForecast, forKey: "export_forecast")
        if !exportsForecast { try? FileManager.default.removeItem(at: ForecastExport.defaultURL) }
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
        if !Self.cookieStore.write(cookie, account: Self.cookieAccount) {
            NSLog("ClaudeUsage: secret storage write failed, cookie kept in memory only")
        }
    }

    func clearSessionCookie() {
        NSLog("ClaudeUsage: Clearing cookie")
        sessionCookie = ""
        Self.cookieStore.delete(account: Self.cookieAccount)
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

}
