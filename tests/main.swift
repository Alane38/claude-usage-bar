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

exit(failures == 0 ? 0 : 1)
