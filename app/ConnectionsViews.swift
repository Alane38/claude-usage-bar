import SwiftUI

/// État des sources de données et reconnexion (import depuis le navigateur ou cookie collé).
struct ConnectionsView: View {
    @ObservedObject var usageManager: UsageManager
    @State private var consoleCookieInput = ""
    @State private var showingConsolePaste = false

    private var consoleState: String {
        if usageManager.consoleCookie.isEmpty { return "non connectée" }
        return usageManager.consoleStatus.isEmpty ? "connectée" : usageManager.consoleStatus
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption)
            Spacer()
            Text(value)
                .font(.caption2)
                .foregroundColor(Color.secondaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connexions")
                .font(.caption.weight(.semibold))
            line("Limites", usageManager.usageSource == "claude.ai" ? "claude.ai, en direct" : "statusline Claude Code")
            line("Session claude.ai", !usageManager.keychainIssue.isEmpty ? usageManager.keychainIssue
                 : (usageManager.sessionCookie.isEmpty ? "absente : colle un cookie ou importe-la" : "présente"))
            line("Console (crédits API)", consoleState)

            Button("Importer les sessions depuis Zen / Firefox") {
                if usageManager.importBrowserCookies() { usageManager.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            if !usageManager.browserImportReport.isEmpty {
                Text(usageManager.browserImportReport)
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(showingConsolePaste ? "Annuler" : "Coller le cookie de la Console") {
                showingConsolePaste.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            if showingConsolePaste { consolePasteSection }
        }
    }

    @ViewBuilder
    private var consolePasteSection: some View {
        Text("platform.claude.com/settings/billing > F12 > Réseau > requête « credits » > En-têtes de requête > Cookie. Colle l'en-tête complet.")
            .font(.caption2)
            .foregroundColor(Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        PasteableTextField(text: $consoleCookieInput, placeholder: "Cookie de la Console…")
            .frame(height: 60)
            .cornerRadius(4)
        HStack(spacing: 8) {
            Button("Enregistrer") {
                guard !consoleCookieInput.isEmpty else { return }
                usageManager.saveConsoleCookie(consoleCookieInput)
                consoleCookieInput = ""
                showingConsolePaste = false
                usageManager.fetchConsoleBalance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            if !usageManager.consoleCookie.isEmpty {
                Button("Déconnecter") { usageManager.disconnectConsole() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
