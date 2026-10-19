import AppKit

/// Outils de développement lancés en ligne de commande : ils impriment des statuts (jamais de secret) puis quittent.
extension AppDelegate {
    func runCommandLineTools() {
        if CommandLine.arguments.contains("--diagnose") {
            print("diagnostic : cookie claude.ai en mémoire =", !usageManager.sessionCookie.isEmpty,
                  "| cookie Console =", !usageManager.consoleCookie.isEmpty,
                  "| problème trousseau =", usageManager.keychainIssue.isEmpty ? "aucun" : usageManager.keychainIssue)
            exit(0)
        }

        if let flag = CommandLine.arguments.firstIndex(of: "--test-install"), CommandLine.arguments.count > flag + 5 {
            // `--test-install zip somme application-cible version dossier-corbeille` : même chemin que le bouton, sur des fichiers locaux,
            // sans relancer ni quitter. Imprime seulement des statuts.
            let a = Array(CommandLine.arguments[(flag + 1)...])
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageBar-test-install")
            do {
                let newApp = try UpdateInstaller.prepare(zip: URL(fileURLWithPath: a[0]), checksum: URL(fileURLWithPath: a[1]), version: a[3],
                                                         bundleID: "com.alane.usagebar", workDirectory: work)
                print("préparé :", newApp.lastPathComponent)
                let process = try UpdateInstaller.launchReplacement(newApp: newApp, target: URL(fileURLWithPath: a[2]), trash: URL(fileURLWithPath: a[4]),
                                                                    pid: 999_999, relaunch: false, workDirectory: work)
                process.waitUntilExit()
                print("remplacement : code", process.terminationStatus)
                exit(process.terminationStatus)
            } catch {
                print("refusé :", (error as? UpdateInstaller.Failure)?.message ?? error.localizedDescription)
                exit(1)
            }
        }

        if CommandLine.arguments.contains("--import-browser") {
            // Même chemin que le bouton des Réglages : importe Zen/Firefox, interroge la Console, n'imprime que des statuts.
            let imported = usageManager.importBrowserCookies()
            print("import :", usageManager.browserImportReport)
            guard imported else { exit(1) }
            usageManager.fetchConsoleBalance()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                print("console :", self.usageManager.consoleStatus,
                      "| solde lu =", self.usageManager.consoleBalance != nil)
                exit(0)
            }
        }

        if CommandLine.arguments.contains("--probe-console") {
            DispatchQueue.global().async {
                self.usageManager.probeConsole()
                exit(0)
            }
        }
    }
}
