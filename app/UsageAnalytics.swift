import Foundation

/// Un relevé de l'usage : instant et pourcentages de la session et de la semaine.
struct UsageSample: Codable, Equatable {
    let time: TimeInterval
    let session: Double?
    let weekly: Double?

    var date: Date { Date(timeIntervalSince1970: time) }
}

enum UsageSeries {
    case session, weekly

    func value(of sample: UsageSample) -> Double? {
        self == .session ? sample.session : sample.weekly
    }
}

/// Analyses pures de l'historique : rythme récent, consommation du jour, courbe, prévision au rythme récent.
enum UsageAnalytics {
    /// Une baisse de plus de 5 points entre deux relevés = la fenêtre a été remise à zéro.
    static let resetDropThreshold = 5.0

    /// Points (instant, pourcentage) d'une série, dans l'ordre du temps.
    static func points(_ samples: [UsageSample], series: UsageSeries) -> [(time: Date, percent: Double)] {
        samples.sorted { $0.time < $1.time }.compactMap { sample in
            series.value(of: sample).map { (sample.date, $0) }
        }
    }

    /// Rythme en points de pourcentage par heure sur les `lookback` dernières secondes, depuis le dernier reset.
    /// nil tant qu'il n'y a pas au moins 5 minutes de relevés ; 0 si rien n'a bougé.
    static func recentRate(_ samples: [UsageSample], series: UsageSeries, now: Date = Date(),
                           lookback: TimeInterval = 30 * 60) -> Double? {
        var window = points(samples, series: series).filter { now.timeIntervalSince($0.time) <= lookback && $0.time <= now }
        // Le relevé qui suit la dernière grosse baisse ouvre la fenêtre courante.
        if let firstAfterReset = window.indices.dropFirst().last(where: { window[$0 - 1].percent - window[$0].percent > resetDropThreshold }) {
            window = Array(window[firstAfterReset...])
        }
        guard let first = window.first, let last = window.last else { return nil }
        let elapsed = last.time.timeIntervalSince(first.time)
        guard elapsed >= 5 * 60 else { return nil }
        return max(last.percent - first.percent, 0) / (elapsed / 3600)
    }

    /// Points de pourcentage consommés depuis minuit (heure locale) : somme des hausses, les remises à zéro sont ignorées.
    static func usedToday(_ samples: [UsageSample], series: UsageSeries, now: Date = Date(),
                          calendar: Calendar = .current) -> Double? {
        let midnight = calendar.startOfDay(for: now)
        let today = points(samples, series: series).filter { $0.time >= midnight && $0.time <= now }
        guard today.count >= 2 else { return nil }
        return zip(today, today.dropFirst()).reduce(0.0) { total, pair in
            let delta = pair.1.percent - pair.0.percent
            return delta > 0 ? total + delta : total
        }
    }

    /// Série des dernières heures pour la courbe.
    static func series(_ samples: [UsageSample], series: UsageSeries, hours: Double = 24,
                       now: Date = Date()) -> [(time: Date, percent: Double)] {
        points(samples, series: series).filter { now.timeIntervalSince($0.time) <= hours * 3600 && $0.time <= now }
    }
}

/// Prévision au rythme récent : plus réactive que la moyenne depuis le début de la fenêtre.
struct RecentForecast: Equatable {
    let ratePerHour: Double
    let projectedPercent: Double
    /// Heure d'atteinte de 100 % si le rythme récent continue, seulement si c'est avant le reset.
    let exhaustsAt: Date?

    static func make(ratePerHour: Double, used: Double, resetsAt: Date, now: Date = Date()) -> RecentForecast {
        let hoursLeft = max(resetsAt.timeIntervalSince(now), 0) / 3600
        let projected = used + ratePerHour * hoursLeft
        var exhaustsAt: Date?
        if ratePerHour > 0, used < 100, projected > 100 {
            exhaustsAt = now.addingTimeInterval((100 - used) / ratePerHour * 3600)
        }
        return RecentForecast(ratePerHour: ratePerHour, projectedPercent: projected, exhaustsAt: exhaustsAt)
    }
}
