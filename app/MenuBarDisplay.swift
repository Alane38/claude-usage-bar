import Foundation

/// Ce que la barre de menu affiche : la session, l'hebdo, ou la fenêtre la plus proche de la limite.
enum MenuBarMode: String, CaseIterable {
    case session, weekly, worst

    var label: String {
        switch self {
        case .session: return "Session (5 h)"
        case .weekly:  return "Hebdo (7 j)"
        case .worst:   return "La plus haute"
        }
    }
}

struct MenuBarState: Equatable {
    let title: String
    /// Pourcentage qui pilote la couleur de l'icône.
    let percent: Int
}

enum MenuBarDisplay {
    /// Titre à droite de l'icône. Le mode (session, hebdo, la plus haute) ne vaut que pour l'étincelle :
    /// les deux autres styles montrent déjà session et semaine dans leur dessin.
    static func state(style: MenuBarStyle = .spark, mode: MenuBarMode,
                      sessionPercent: Int, sessionResetsAt: Date?,
                      weeklyPercent: Int, weeklyResetsAt: Date?,
                      showReset: Bool, now: Date = Date()) -> MenuBarState {
        var title: String
        var percent = sessionPercent
        var resetsAt = sessionResetsAt

        switch style {
        case .dualRing:
            title = " \(sessionPercent)%"
        case .twoValues:
            title = " \(sessionPercent) · \(weeklyPercent)"
            percent = max(sessionPercent, weeklyPercent)
        case .spark:
            let showsWeekly: Bool
            switch mode {
            case .session: showsWeekly = false
            case .weekly:  showsWeekly = true
            case .worst:   showsWeekly = weeklyPercent > sessionPercent
            }
            percent = showsWeekly ? weeklyPercent : sessionPercent
            resetsAt = showsWeekly ? weeklyResetsAt : sessionResetsAt
            title = " \(percent)%"
            if mode == .worst { title += showsWeekly ? " 7j" : " 5h" }
        }

        if showReset, let resetsAt {
            title += " · \(countdown(to: resetsAt, now: now))"
        }
        return MenuBarState(title: title, percent: percent)
    }

    /// « 45 min », « 2h14 », « 3j 4h » : le plus court lisible d'un coup d'œil.
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let totalMinutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)j \(hours)h" }
        if hours > 0 { return String(format: "%dh%02d", hours, minutes) }
        return "\(minutes) min"
    }
}
