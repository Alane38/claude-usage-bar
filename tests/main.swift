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

exit(failures == 0 ? 0 : 1)
