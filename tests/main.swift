import Foundation

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok   \(label)" : "FAIL \(label)")
    if !condition { failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_000_000)
func payload(_ json: String) -> Data { Data(json.utf8) }

let full = StatuslineUsage.parse(payload("""
{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1003600},"seven_day":{"used_percentage":35.5,"resets_at":1500000}}}
"""), capturedAt: now, now: now)
check(full?.fiveHour?.usedPercentage == 1, "5h lue (entier)")
check(full?.sevenDay?.usedPercentage == 35.5, "7j lue (décimal)")

let expired = StatuslineUsage.parse(payload("""
{"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":999000},"seven_day":{"used_percentage":35,"resets_at":1500000}}}
"""), capturedAt: now, now: now)
check(expired?.fiveHour == nil, "fenêtre 5h expirée abandonnée")
check(expired?.sevenDay != nil, "fenêtre 7j gardée")

check(StatuslineUsage.parse(payload("{}"), capturedAt: now, now: now) == nil, "sans rate_limits -> nil")
check(StatuslineUsage.parse(payload("pas du json"), capturedAt: now, now: now) == nil, "JSON invalide -> nil")
check(StatuslineUsage.parse(payload("""
{"rate_limits":{"five_hour":{"used_percentage":250,"resets_at":1003600}}}
"""), capturedAt: now, now: now)?.fiveHour?.usedPercentage == 100, "pourcentage borné à 100")

let keychain = KeychainStore(service: "com.alane.usagebar.tests")
keychain.delete(account: "t")
check(keychain.read(account: "t") == nil, "Keychain : absent au départ")
check(keychain.write("secret-1", account: "t") && keychain.read(account: "t") == "secret-1", "Keychain : écriture puis lecture")
keychain.write("secret-2", account: "t")
check(keychain.read(account: "t") == "secret-2", "Keychain : écriture idempotente (remplace)")
keychain.delete(account: "t")
check(keychain.read(account: "t") == nil, "Keychain : suppression")

// --- Prévisions ---
let weekEnd = now.addingTimeInterval(2.5 * 86400)           // 4,5 j écoulés sur 7
let week = UsageForecast.forecast(usedPercent: 35, resetsAt: weekEnd, windowLength: UsageForecast.weekLength, now: now)
check(abs(week.expectedPercent - 64.2857) < 0.01, "hebdo : rythme régulier attendu 64 %")
check(abs((week.projectedPercent ?? 0) - 54.44) < 0.1, "hebdo : projection ≈ 54 % au reset")
check(week.pace == .under && week.exhaustsAt == nil, "hebdo : en dessous du rythme, pas d'épuisement")
check(abs(week.remainingPerDay - 26) < 0.01, "hebdo : 26 %/jour utilisables")

let fast = UsageForecast.forecast(usedPercent: 60, resetsAt: now.addingTimeInterval(3 * 3600), windowLength: UsageForecast.sessionLength, now: now)
check(fast.pace == .over, "session : 60 % après 2 h sur 5 h -> trop vite")
if let at = fast.exhaustsAt {
    check(abs(at.timeIntervalSince(now) - 4800) < 1, "session : 100 % atteint dans 1 h 20")
} else { check(false, "session : heure d'épuisement attendue") }

let early = UsageForecast.forecast(usedPercent: 10, resetsAt: now.addingTimeInterval(UsageForecast.sessionLength - 600), windowLength: UsageForecast.sessionLength, now: now)
check(early.projectedPercent == nil && early.pace == .onTrack, "session : pas de projection avant 5 % écoulé")

let maxed = UsageForecast.forecast(usedPercent: 100, resetsAt: now.addingTimeInterval(3600), windowLength: UsageForecast.sessionLength, now: now)
check(maxed.pace == .over && maxed.exhaustsAt == nil && maxed.remainingPerDay == 0, "limite atteinte : over, budget 0")

let past = UsageForecast.forecast(usedPercent: 50, resetsAt: now.addingTimeInterval(-60), windowLength: UsageForecast.weekLength, now: now)
check(past.remainingPerDay == 0 && past.expectedPercent == 100, "reset passé : fenêtre terminée")

// --- Barre de menu ---
let in2h14 = now.addingTimeInterval(2 * 3600 + 14 * 60 + 5)
let barSession = MenuBarDisplay.state(mode: .session, sessionPercent: 12, sessionResetsAt: in2h14, weeklyPercent: 35, weeklyResetsAt: nil, showReset: true, now: now)
check(barSession.title == " 12% · 2h14" && barSession.percent == 12, "barre : session avec reset")
let barWorst = MenuBarDisplay.state(mode: .worst, sessionPercent: 12, sessionResetsAt: nil, weeklyPercent: 35, weeklyResetsAt: nil, showReset: false, now: now)
check(barWorst.title == " 35% 7j" && barWorst.percent == 35, "barre : la plus haute = hebdo")
let barWorstSession = MenuBarDisplay.state(mode: .worst, sessionPercent: 80, sessionResetsAt: nil, weeklyPercent: 35, weeklyResetsAt: nil, showReset: false, now: now)
check(barWorstSession.title == " 80% 5h", "barre : la plus haute = session")
check(MenuBarDisplay.countdown(to: now.addingTimeInterval(45 * 60), now: now) == "45 min", "décompte : minutes")
check(MenuBarDisplay.countdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600), now: now) == "3j 4h", "décompte : jours")
check(MenuBarDisplay.countdown(to: now.addingTimeInterval(-5), now: now) == "0 min", "décompte : passé borné à 0")

// --- Crédits API ---
let credits = ApiCredits(monthlyAmount: 100, spent: 40, cycleEndsAt: now.addingTimeInterval(10 * 86400 - 3600))
check(credits.remaining == 60 && credits.daysLeft(now: now) == 10, "crédits : 60 $ restants, 10 jours")
check(credits.dailyBudget(now: now) == 6, "crédits : 6 $/jour")
let overspent = ApiCredits(monthlyAmount: 100, spent: 130, cycleEndsAt: now.addingTimeInterval(86400))
check(overspent.remaining == 0 && overspent.usedFraction == 1, "crédits : dépassement borné")
check(ApiCredits(monthlyAmount: 100, spent: 0, cycleEndsAt: now.addingTimeInterval(-1)).dailyBudget(now: now) == nil, "crédits : cycle fini -> pas de budget")

// --- Solde Console (formes supposées, voir ConsoleBalance) ---
let creditsJSON = Data("""
{"amount":8750,"currency":"USD","tranches":[{"remaining_amount_minor_units":8750,"expires_at":"2026-11-05T00:00:00Z"},{"remaining_amount_minor_units":0,"expires_at":"2026-10-01T00:00:00Z"}]}
""".utf8)
let spendJSON = Data("""
{"amount":1250,"resets_at":"2026-11-01T00:00:00Z"}
""".utf8)
let balanceNow = ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z")!
let balance = ConsoleBalance.parse(credits: creditsJSON, spend: spendJSON, now: balanceNow)
check(balance?.balance == 87.5 && balance?.currency == "USD", "console : solde 87,50 $")
check(balance?.spentThisPeriod == 12.5, "console : dépense de la période 12,50 $")
check(balance?.nextExpiry == ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z"), "console : échéance = lot encore valide")
check(balance?.daysLeft(now: balanceNow) == 16, "console : 16 jours avant échéance")
check(ConsoleBalance.parse(credits: Data("{}".utf8), spend: nil) == nil, "console : sans amount -> nil")
check(ConsoleBalance.parse(credits: Data("[1]".utf8), spend: nil) == nil, "console : JSON inattendu -> nil")
let noSpend = ConsoleBalance.parse(credits: Data("{\"amount\":500}".utf8), spend: nil)
check(noSpend?.spentThisPeriod == nil && noSpend?.daysLeft() == nil && noSpend?.dailyBudget() == nil, "console : champs absents tolérés")

// --- Cookies Firefox (base SQLite factice) ---
let fakeProfiles = FileManager.default.temporaryDirectory.appendingPathComponent("cub-test-\(UUID().uuidString)")
let fakeProfile = fakeProfiles.appendingPathComponent("abc.default-release")
try? FileManager.default.createDirectory(at: fakeProfile, withIntermediateDirectories: true)
let fakeDatabase = fakeProfile.appendingPathComponent("cookies.sqlite")
let seed = Process()
seed.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
seed.arguments = [fakeDatabase.path, """
CREATE TABLE moz_cookies (host TEXT, name TEXT, value TEXT);
INSERT INTO moz_cookies VALUES ('.claude.ai','sessionKey','AAA');
INSERT INTO moz_cookies VALUES ('claude.ai','lastActiveOrg','org-1');
INSERT INTO moz_cookies VALUES ('.claude.ai','shared','general');
INSERT INTO moz_cookies VALUES ('claude.ai','shared','precis');
INSERT INTO moz_cookies VALUES ('.platform.claude.com','sessionKey','BBB');
INSERT INTO moz_cookies VALUES ('.notclaude.ai','intrus','X');
"""]
try? seed.run(); seed.waitUntilExit()
check(FirefoxCookies.cookieDatabases(roots: [fakeProfiles]).first?.resolvingSymlinksInPath() == fakeDatabase.resolvingSymlinksInPath(), "firefox : profil détecté")
check(FirefoxCookies.cookieHeader(domain: "claude.com", roots: [fakeProfiles]) == "sessionKey=BBB", "firefox : recherche dans tous les profils")
let claudeHeader = FirefoxCookies.cookieHeader(database: fakeDatabase, domain: "claude.ai") ?? ""
check(claudeHeader == "lastActiveOrg=org-1; sessionKey=AAA; shared=precis", "firefox : en-tête claude.ai (précis > général, sans intrus)")
check(FirefoxCookies.cookieHeader(database: fakeDatabase, domain: "claude.com") == "sessionKey=BBB", "firefox : domaine Console séparé")
check(FirefoxCookies.cookieHeader(database: fakeDatabase, domain: "absent.example") == nil, "firefox : domaine inconnu -> nil")
try? FileManager.default.removeItem(at: fakeProfiles)

// --- Aides de synchronisation ---
check(SyncHelpers.organizationId(fromCookie: "a=1; lastActiveOrg=abc-123; b=2") == "abc-123", "cookie : lastActiveOrg trouvé")
check(SyncHelpers.organizationId(fromCookie: "a=1; lastActiveOrg=") == nil, "cookie : lastActiveOrg vide -> nil")
check(SyncHelpers.organizationId(fromCookie: "a=1; b=2") == nil, "cookie : sans lastActiveOrg -> nil")
check(SyncHelpers.age(since: now.addingTimeInterval(-20), now: now) == "à l'instant", "âge : à l'instant")
check(SyncHelpers.age(since: now.addingTimeInterval(-12 * 60), now: now) == "il y a 12 min", "âge : minutes")
check(SyncHelpers.age(since: now.addingTimeInterval(-3 * 3600), now: now) == "il y a 3 h", "âge : heures")
check(SyncHelpers.age(since: now.addingTimeInterval(-2 * 86400), now: now) == "il y a 2 j", "âge : jours")
check(SyncHelpers.isStale(now.addingTimeInterval(-11 * 60), now: now) && !SyncHelpers.isStale(now.addingTimeInterval(-9 * 60), now: now), "âge : périmé après 10 min")

// --- Réponse réelle de la Console (Max 5x, identifiants retirés) ---
let realCredits = Data("""
{"amount":10000,"currency":"USD","balance":{"money":null,"credits":{"amount_minor":10000,"exponent":2}},"balance_credits":100,"amount_without_scoped_credits":0,"auto_reload_settings":null,"tranches":[],"promo_tranches":[{"remaining_amount_minor_units":10000,"currency":"USD","expires_at":"2026-11-05T00:00:00Z","granted_amount_minor_units":10000,"granted_at":"2026-10-18T20:15:36.082000Z","program_id":"subscription_api_credit","name":"API credit (Max 5x)"}],"next_expires_at":"2026-11-05T00:00:00Z"}
""".utf8)
let realSpend = Data("{\"amount\":0,\"resets_at\":\"2026-11-01T00:00:00Z\"}".utf8)
let realNow = ISO8601DateFormatter().date(from: "2026-10-18T20:30:00Z")!
let real = ConsoleBalance.parse(credits: realCredits, spend: realSpend, now: realNow)
check(real?.balance == 100 && real?.promoGranted == 100, "réel : 100 $ restants sur 100 $ accordés")
check(real?.promoUsedFraction == 0 && real?.spentThisPeriod == 0, "réel : rien consommé")
check(real?.promoName == "API credit (Max 5x)", "réel : nom du programme")
check(real?.nextExpiry == ISO8601DateFormatter().date(from: "2026-11-05T00:00:00Z") && real?.daysLeft(now: realNow) == 18, "réel : échéance 05/11, 18 jours")
check(abs((real?.dailyBudget(now: realNow) ?? 0) - 100.0 / 18) < 0.001, "réel : ≈ 5,56 $/jour")
let partial = ConsoleBalance.parse(credits: Data(String(decoding: realCredits, as: UTF8.self)
    .replacingOccurrences(of: "\"amount\":10000", with: "\"amount\":6250")
    .replacingOccurrences(of: "\"remaining_amount_minor_units\":10000", with: "\"remaining_amount_minor_units\":6250").utf8), spend: nil, now: realNow)
check(partial?.balance == 62.5 && partial?.promoUsedFraction == 0.375, "réel : 37,5 % consommés")

// --- Le statusline ne doit pas écraser une donnée plus récente (Refresh) ---
check(!StatuslineUsage.shouldReplace(displayedAt: now, hasDisplayedData: true, capturedAt: now.addingTimeInterval(-3600)), "refresh : statusline ancien ignoré")
check(StatuslineUsage.shouldReplace(displayedAt: now, hasDisplayedData: true, capturedAt: now.addingTimeInterval(60)), "refresh : statusline plus récent appliqué")
check(StatuslineUsage.shouldReplace(displayedAt: now, hasDisplayedData: false, capturedAt: now.addingTimeInterval(-3600)), "démarrage : statusline appliqué faute de donnée")

// --- Cadence de rafraîchissement ---
var policy = RefreshPolicy()
check(policy.interval == 60 && !policy.isSlowed, "cadence : 60 s au départ")
policy.record(statusCode: 429)
check(policy.interval == 300 && policy.isSlowed, "cadence : 429 -> 5 min")
policy.record(statusCode: nil)
check(policy.interval == 300, "cadence : réseau coupé ne change rien")
policy.record(statusCode: 404)
check(policy.interval == 300, "cadence : 404 ne change rien")
policy.record(statusCode: 200)
check(policy.interval == 60 && !policy.isSlowed, "cadence : succès -> retour à 60 s")
for code in [401, 403, 500, 503] {
    var p = RefreshPolicy(); p.record(statusCode: code)
    check(p.isSlowed, "cadence : \(code) -> ralenti")
}
var untouched = RefreshPolicy(); untouched.record(statusCode: nil)
check(!untouched.isSlowed, "cadence : pas de réponse au départ -> reste à 60 s")

// --- Styles et tonalités ---
check(PopoverLayout(rawValue: "cards") == .cards && PopoverLayout(rawValue: "inconnu") == nil, "style : disposition relue depuis sa clé")
check(MenuBarStyle.allCases.count == 3, "style : trois dessins de barre de menu")
check(UsageTone.of(percent: 8, pace: .under, isStale: false) == .ok, "tonalité : 8 % sous le rythme -> ok")
check(UsageTone.of(percent: 60, pace: .over, isStale: false) == .warning, "tonalité : trop vite -> avertissement")
check(UsageTone.of(percent: 74, pace: .onTrack, isStale: false) == .warning, "tonalité : 74 % -> avertissement")
check(UsageTone.of(percent: 95, pace: .onTrack, isStale: false) == .danger, "tonalité : 95 % -> danger")
check(UsageTone.of(percent: 95, pace: .over, isStale: true) == .stale, "tonalité : donnée ancienne -> neutre")
check(UsageTone.worst([.ok, .warning, .stale]) == .warning && UsageTone.worst([.stale, .ok]) == .stale && UsageTone.worst([]) == .ok, "tonalité : la plus grave l'emporte")
let ring = RingGeometry.dash(percent: 25, radius: 10)
check(abs(ring.on - 15.708) < 0.001 && abs(ring.on + ring.off - 62.832) < 0.001, "anneau : 25 % d'un cercle de rayon 10")
check(RingGeometry.dash(percent: 150, radius: 10).off == 0 && RingGeometry.dash(percent: -5, radius: 10).on == 0, "anneau : pourcentage borné")

// --- Titre de la barre de menu selon le style ---
let ringTitle = MenuBarDisplay.state(style: .dualRing, mode: .worst, sessionPercent: 8, sessionResetsAt: in2h14, weeklyPercent: 37, weeklyResetsAt: nil, showReset: true, now: now)
check(ringTitle.title == " 8% · 2h14" && ringTitle.percent == 8, "barre : double anneau = session + reset")
let twoTitle = MenuBarDisplay.state(style: .twoValues, mode: .session, sessionPercent: 8, sessionResetsAt: nil, weeklyPercent: 37, weeklyResetsAt: nil, showReset: false, now: now)
check(twoTitle.title == " 8 · 37" && twoTitle.percent == 37, "barre : deux valeurs, la plus haute pilote la couleur")

// --- Résumé des crédits ---
let summaryLive = CreditsSummary.make(console: real, manual: nil, now: realNow)
check(summaryLive?.title == "Crédits API · Max 5x" && summaryLive?.valueText == "100 $", "crédits : titre court et montant")
check(summaryLive?.detail == "Expirent dans 18 j · ≈ 5,56 $ par jour", "crédits : échéance et budget par jour en français")
check(summaryLive?.usedFraction == 0, "crédits : rien consommé")
let manualCredits = ApiCredits(monthlyAmount: 100, spent: 40, cycleEndsAt: now.addingTimeInterval(10 * 86400 - 3600))
let summaryManual = CreditsSummary.make(console: nil, manual: manualCredits, now: now)
check(summaryManual?.valueText == "60 $" && summaryManual?.usedFraction == 0.4, "crédits manuels : reste et part consommée")
check(summaryManual?.title == "Crédits API (saisie manuelle)", "crédits manuels : source indiquée")
check(CreditsSummary.make(console: nil, manual: nil) == nil, "crédits : rien à afficher sans source")
check(CreditsSummary.make(console: real, manual: manualCredits, now: realNow)?.title == "Crédits API · Max 5x", "crédits : la Console prime sur la saisie")
check(CreditsSummary.money(87.5, "USD") == "87,5 $" && CreditsSummary.money(12, "EUR") == "12 EUR", "crédits : formatage des montants")

// --- Libellés de rythme ---
func forecastAt(_ used: Double, left: TimeInterval, length: TimeInterval) -> WindowForecast {
    UsageForecast.forecast(usedPercent: used, resetsAt: now.addingTimeInterval(left), windowLength: length, now: now)
}
let calm = forecastAt(8, left: 3 * 3600, length: UsageForecast.sessionLength)
check(PaceText.chip(for: calm, percent: 8) == "En dessous du rythme", "libellé : faible usage -> en dessous du rythme")
check(PaceText.chip(for: forecastAt(40, left: 3 * 3600, length: UsageForecast.sessionLength), percent: 40) == "En rythme" || PaceText.chip(for: forecastAt(40, left: 3 * 3600, length: UsageForecast.sessionLength), percent: 40) == "Trop rapide", "libellé : 40 % après 2 h -> rythme ou trop rapide, jamais vide")
check(PaceText.chip(for: forecastAt(74, left: 2.5 * 3600, length: UsageForecast.sessionLength), percent: 74) == "Trop rapide", "libellé : 74 % à mi-fenêtre -> trop rapide")
check(PaceText.chip(for: forecastAt(74, left: 3600, length: UsageForecast.sessionLength), percent: 74) == "Usage élevé", "libellé : 74 % à 80 % de la fenêtre -> usage élevé")
check(PaceText.chip(for: forecastAt(75, left: 3600, length: UsageForecast.weekLength), percent: 75) == "Usage élevé", "libellé : 75 % sans dérive -> usage élevé")
check(PaceText.chip(for: calm, percent: 93) == "Limite proche" && PaceText.chip(for: calm, percent: 100) == "Limite atteinte", "libellé : 93 % et 100 %")
check(PaceText.chip(for: nil, percent: 10) == nil && PaceText.chip(for: nil, percent: 80) == "Usage élevé", "libellé : sans prévision")
check(PaceText.summary(for: calm, showsDailyBudget: false).hasPrefix("≈ "), "résumé : prévision au reset")
check(PaceText.summary(for: forecastAt(5, left: UsageForecast.sessionLength - 60, length: UsageForecast.sessionLength), showsDailyBudget: false) == "", "résumé : vide trop tôt dans la fenêtre")

// --- Icône seule ---
let textless = MenuBarDisplay.state(style: .dualRing, mode: .session, sessionPercent: 8, sessionResetsAt: in2h14, weeklyPercent: 37, weeklyResetsAt: nil, showReset: true, showText: false, now: now)
check(textless.title.isEmpty && textless.percent == 8, "barre : icône seule, aucun texte")
let withText = MenuBarDisplay.state(style: .dualRing, mode: .session, sessionPercent: 8, sessionResetsAt: nil, weeklyPercent: 37, weeklyResetsAt: nil, showReset: false, showText: true, now: now)
check(withText.title == " 8%", "barre : texte par défaut inchangé")

// --- Stockage des secrets par fichier (mode développement) ---
let secretsDir = FileManager.default.temporaryDirectory.appendingPathComponent("cub-secrets-\(UUID().uuidString)")
let fileStore = FileSecretStore(directory: secretsDir)
check(fileStore.readResult(account: "a").value == nil && fileStore.readResult(account: "a").status == errSecItemNotFound, "fichier : absent -> introuvable")
check(fileStore.write("valeur-1", account: "a") && fileStore.read(account: "a") == "valeur-1", "fichier : écriture puis lecture")
check(fileStore.write("valeur-2", account: "a") && fileStore.read(account: "a") == "valeur-2", "fichier : écriture idempotente (remplace)")
func permissions(_ url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? Int) ?? -1 }
check(permissions(secretsDir.appendingPathComponent("a")) == 0o600, "fichier : droits 0600")
check(permissions(secretsDir) == 0o700, "fichier : dossier 0700")
check(fileStore.readResult(account: "a").status == errSecSuccess, "fichier : statut succès")
check(fileStore.delete(account: "a") && fileStore.read(account: "a") == nil, "fichier : suppression")
check(fileStore.delete(account: "jamais-existé"), "fichier : supprimer l'absent réussit")
try? FileManager.default.removeItem(at: secretsDir)
check(!AppSecrets.isRelease && AppSecrets.storageLabel.contains("développement"), "mode : la compilation de test est en développement")

exit(failures == 0 ? 0 : 1)
