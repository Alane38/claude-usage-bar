import Foundation

/// Textes du rythme : le libellé suit la même logique que la couleur, pour ne jamais dire « en rythme » en jaune.
enum PaceText {
    static func chip(for forecast: WindowForecast?, percent: Int) -> String? {
        if percent >= 100 { return "Limite atteinte" }
        if percent >= 90 { return "Limite proche" }
        guard let forecast else { return percent >= 70 ? "Usage élevé" : nil }
        if forecast.pace == .over { return "Trop rapide" }
        if percent >= 70 { return "Usage élevé" }
        return forecast.pace == .under ? "En dessous du rythme" : "En rythme"
    }

    static func summary(for forecast: WindowForecast?, showsDailyBudget: Bool) -> String {
        var parts: [String] = []
        if let projected = forecast?.projectedPercent {
            parts.append("≈ \(Int(projected.rounded())) % au reset")
        }
        if showsDailyBudget, let perDay = forecast?.remainingPerDay, (forecast?.usedPercent ?? 0) < 100 {
            parts.append("\(Int(perDay.rounded())) % par jour")
        }
        return parts.joined(separator: " · ")
    }
}
