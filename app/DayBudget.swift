import Foundation

/// Budget conseillé pour la journée en cours : la part de la limite hebdomadaire à consommer aujourd'hui
/// pour arriver au reset sans être bloqué, comparée à ce qui est déjà consommé.
struct DayBudget: Equatable {
    enum Level: Equatable { case ok, close, over, exception }

    /// Part conseillée pour toute la journée, en % de la limite hebdomadaire.
    let allowed: Double
    /// Déjà consommé depuis minuit, en % de la limite hebdomadaire.
    let used: Double
    /// Jour déclaré exceptionnel (développement intensif, journée de rattrapage) : la consommation reste affichée, sans alerte de couleur.
    var isException = false

    var fraction: Double { allowed > 0 ? used / allowed : (used > 0 ? 2 : 0) }
    var overBy: Double { max(used - allowed, 0) }
    /// En dessous de 80 % du budget tout va bien, jusqu'à 100 % il est presque atteint, au-delà il est dépassé.
    var level: Level { isException ? .exception : (fraction > 1 ? .over : (fraction >= 0.8 ? .close : .ok)) }

    /// Le budget de la journée est celui calculé au début de la journée : (100 − usage de minuit) × part du temps restant
    /// que représente aujourd'hui. Il ne rétrécit donc pas quand on consomme, et le dépassement reste visible.
    /// nil sans historique du jour, sans reset connu, ou si la limite hebdomadaire est déjà atteinte.
    static func make(weeklyUsed: Double, usedToday: Double?, now: Date, resetsAt: Date?,
                     calendar: Calendar = .current, isException: Bool = false) -> DayBudget? {
        guard let usedToday, let resetsAt, resetsAt > now, weeklyUsed < 100 else { return nil }
        let midnight = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) ?? now.addingTimeInterval(86_400)
        let span = resetsAt.timeIntervalSince(midnight)
        guard span > 0 else { return nil }
        let usedAtMidnight = min(max(weeklyUsed - usedToday, 0), 100)
        let todayShare = min(tomorrow, resetsAt).timeIntervalSince(midnight) / span
        return DayBudget(allowed: (100 - usedAtMidnight) * todayShare, used: usedToday, isException: isException)
    }
}

enum DayBudgetText {
    static func line(_ budget: DayBudget) -> String {
        let allowed = Int(budget.allowed.rounded()), used = Int(budget.used.rounded())
        switch budget.level {
        case .ok, .close: return "Aujourd'hui : \(used) % sur \(allowed) % conseillés"
        case .exception: return "Aujourd'hui : \(used) % sur \(allowed) % conseillés · jour exceptionnel"
        case .over: return "Aujourd'hui : \(used) % sur \(allowed) % conseillés, dépassé de \(Int(budget.overBy.rounded())) %"
        }
    }

    /// Ce que ça change : un dépassement se rattrape sur les jours suivants.
    static func consequence(_ budget: DayBudget) -> String? {
        budget.level == .over ? "Les jours suivants auront d'autant moins." : nil
    }
}

/// Jours déclarés exceptionnels, stockés sous la forme « AAAA-MM-JJ » (réglage `exceptional_days`).
enum ExceptionalDays {
    static func stamp(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func contains(_ days: [String], date: Date, calendar: Calendar = .current) -> Bool {
        days.contains(stamp(for: date, calendar: calendar))
    }
}
