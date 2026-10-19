import Foundation

enum AlertKind: String, CaseIterable {
    case willExhaust, unusedBeforeReset, sessionReleased, sessionExpired, creditsExpiring

    var label: String {
        switch self {
        case .willExhaust:       return "Limite atteinte bientôt"
        case .unusedBeforeReset: return "Part inutilisée avant un reset"
        case .sessionReleased:   return "Session libérée"
        case .sessionExpired:    return "Session claude.ai expirée"
        case .creditsExpiring:   return "Crédits API qui expirent"
        }
    }

    var detail: String {
        switch self {
        case .willExhaust:       return "« Tu atteindras 100 % vers 18 h 40 », avant que ça arrive."
        case .unusedBeforeReset: return "« Reset dans 30 min, 22 % inutilisés » : cette part ne se reporte pas."
        case .sessionReleased:   return "Une fois la limite atteinte : « tu peux reprendre »."
        case .sessionExpired:    return "Quand la connexion à claude.ai ne marche plus et que les données se figent."
        case .creditsExpiring:   return "À 5, 2 et 1 jour de l'échéance, tant qu'il reste du solde."
        }
    }
}

struct AlertMessage: Equatable {
    let kind: AlertKind
    /// Identifiant de dédoublonnage : une même clé n'est notifiée qu'une fois.
    let key: String
    let title: String
    let body: String
}

struct AlertSettings: Equatable {
    var enabled: Set<AlertKind> = Set(AlertKind.allCases)
    func isOn(_ kind: AlertKind) -> Bool { enabled.contains(kind) }
}

struct AlertContext {
    var now: Date
    var sessionPercent: Double
    var sessionResetsAt: Date?
    var sessionETA: Date?
    var weeklyPercent: Double
    var weeklyResetsAt: Date?
    var weeklyETA: Date?
    var previousSessionPercent: Double?
    var consecutiveAuthFailures: Int
    var credits: ConsoleBalance?
}

/// Règles d'alerte pures. L'appelant fournit un registre (`alreadySent`) pour ne jamais répéter un message.
enum AlertRules {
    static func evaluate(_ context: AlertContext, settings: AlertSettings, alreadySent: (String) -> Bool) -> [AlertMessage] {
        var messages: [AlertMessage] = []
        if settings.isOn(.willExhaust) { messages += willExhaust(context) }
        if settings.isOn(.unusedBeforeReset) { messages += unused(context) }
        if settings.isOn(.sessionReleased) { messages += released(context) }
        if settings.isOn(.sessionExpired) { messages += expired(context) }
        if settings.isOn(.creditsExpiring) { messages += creditsExpiring(context) }
        return messages.filter { !alreadySent($0.key) }
    }

    // MARK: - Règles

    private static func willExhaust(_ c: AlertContext) -> [AlertMessage] {
        var result: [AlertMessage] = []
        if let eta = c.sessionETA, let resetsAt = c.sessionResetsAt, c.sessionPercent >= 25, c.sessionPercent < 100,
           eta > c.now, eta < resetsAt, eta.timeIntervalSince(c.now) <= 90 * 60 {
            let imminent = eta.timeIntervalSince(c.now) <= 15 * 60
            result.append(AlertMessage(
                kind: .willExhaust, key: "exhaust-session-\(minute(resetsAt))\(imminent ? "-imminent" : "")",
                title: imminent ? "Limite de session dans \(minutesLeft(until: eta, from: c.now)) min" : "Tu atteindras 100 % vers \(clock(eta))",
                body: "Session à \(Int(c.sessionPercent.rounded())) %, reset à \(clock(resetsAt)). Ralentis pour tenir jusqu'au reset."))
        }
        if let eta = c.weeklyETA, let resetsAt = c.weeklyResetsAt, c.weeklyPercent >= 40, c.weeklyPercent < 100,
           eta > c.now, eta < resetsAt, eta.timeIntervalSince(c.now) <= 36 * 3600 {
            result.append(AlertMessage(
                kind: .willExhaust, key: "exhaust-weekly-\(minute(resetsAt))-\(day(c.now))",
                title: "Semaine à 100 % \(dayAndClock(eta))",
                body: "À ce rythme tu seras bloqué jusqu'au reset (\(dayAndClock(resetsAt))). Étale ta consommation."))
        }
        return result
    }

    private static func unused(_ c: AlertContext) -> [AlertMessage] {
        var result: [AlertMessage] = []
        if let resetsAt = c.sessionResetsAt, c.sessionPercent >= 10, c.sessionPercent <= 80 {
            let left = minutesLeft(until: resetsAt, from: c.now)
            if left > 0, left <= 30 {
                result.append(AlertMessage(
                    kind: .unusedBeforeReset, key: "unused-session-\(minute(resetsAt))",
                    title: "Reset dans \(left) min, \(Int((100 - c.sessionPercent).rounded())) % inutilisés",
                    body: "Cette part de la session ne se reporte pas. C'est le moment d'en profiter."))
            }
        }
        if let resetsAt = c.weeklyResetsAt, c.weeklyPercent < 75 {
            let hours = resetsAt.timeIntervalSince(c.now) / 3600
            if hours > 0, hours <= 6 {
                result.append(AlertMessage(
                    kind: .unusedBeforeReset, key: "unused-weekly-\(minute(resetsAt))",
                    title: "Reset de la semaine dans \(Int(hours.rounded(.up))) h, \(Int((100 - c.weeklyPercent).rounded())) % inutilisés",
                    body: "Cette part ne se reporte pas : lance les tâches que tu as repoussées."))
            }
        }
        return result
    }

    private static func released(_ c: AlertContext) -> [AlertMessage] {
        guard let previous = c.previousSessionPercent, previous >= 95, c.sessionPercent <= previous - 20 else { return [] }
        return [AlertMessage(kind: .sessionReleased, key: "released-\(minute(c.sessionResetsAt ?? c.now))",
                             title: "Session libérée, tu peux reprendre",
                             body: "La limite de 5 h est remise à zéro (\(Int(c.sessionPercent.rounded())) %).")]
    }

    private static func expired(_ c: AlertContext) -> [AlertMessage] {
        guard c.consecutiveAuthFailures >= 3 else { return [] }
        return [AlertMessage(kind: .sessionExpired, key: "expired-\(Int(c.now.timeIntervalSince1970 / 21600))",
                             title: "Session claude.ai expirée",
                             body: "Les données ne se mettent plus à jour. Recolle un cookie dans Réglages > Connexions.")]
    }

    private static func creditsExpiring(_ c: AlertContext) -> [AlertMessage] {
        guard let balance = c.credits, balance.balance >= 10, let days = balance.daysLeft(now: c.now),
              let threshold = [1, 2, 5].first(where: { days <= $0 }), (balance.promoUsedFraction ?? 0) < 0.9,
              let expiry = balance.nextExpiry else { return [] }
        let amount = CreditsSummary.money(balance.balance, balance.currency)
        let spent = balance.spentThisPeriod.map { CreditsSummary.money($0, balance.currency) } ?? "0 $"
        return [AlertMessage(kind: .creditsExpiring, key: "credits-\(day(expiry))-d\(threshold)",
                             title: "Crédits API : \(amount) expirent \(days <= 1 ? "demain" : "dans \(days) j")",
                             body: "Dépensé ce cycle : \(spent). Les crédits non utilisés ne se reportent pas.")]
    }

    // MARK: - Formatage

    private static func minutesLeft(until date: Date, from now: Date) -> Int { max(Int((date.timeIntervalSince(now) / 60).rounded(.up)), 0) }
    private static func minute(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 60) }
    private static func day(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 86400) }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = pattern
        return f
    }

    static func clock(_ date: Date) -> String { formatter("HH:mm").string(from: date).replacingOccurrences(of: ":", with: " h ") }
    static func dayAndClock(_ date: Date) -> String { formatter("EEEE").string(from: date) + " à " + clock(date) }
}

/// Registre des alertes déjà envoyées, pour ne jamais notifier deux fois la même chose.
struct AlertLedger: Equatable {
    private(set) var sent: [String: TimeInterval] = [:]
    static let retention: TimeInterval = 30 * 86400

    init(sent: [String: TimeInterval] = [:]) { self.sent = sent }

    func has(_ key: String) -> Bool { sent[key] != nil }

    mutating func mark(_ key: String, now: Date = Date()) {
        sent[key] = now.timeIntervalSince1970
        let cutoff = now.timeIntervalSince1970 - Self.retention
        sent = sent.filter { $0.value >= cutoff }
    }
}
