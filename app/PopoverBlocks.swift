import SwiftUI

extension UsageTone {
    var color: Color { Color(nsColor: MenuBarIcons.color(for: self)) }
}

/// Barre de jauge : valeur actuelle, projection au reset (voile) et repère du rythme régulier (trait).
struct GaugeBar: View {
    let used: Double
    let projected: Double?
    let expected: Double?
    let tone: UsageTone

    private func width(_ percent: Double, _ total: CGFloat) -> CGFloat {
        total * CGFloat(min(max(percent, 0), 100) / 100)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if let projected, projected > used {
                    Capsule().fill(tone.color.opacity(0.35)).frame(width: width(projected, geo.size.width))
                }
                Capsule().fill(tone.color).frame(width: used > 0 ? max(width(used, geo.size.width), 6) : 0)
                if let expected {
                    Rectangle().fill(Color.primary).frame(width: 2, height: 14)
                        .offset(x: width(expected, geo.size.width) - 1)
                }
            }
        }
        .frame(height: 8)
    }
}

/// Puce « En rythme », « Trop rapide »…
struct PaceChip: View {
    let text: String
    let tone: UsageTone

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tone.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(tone.color.opacity(0.15))
            .cornerRadius(6)
    }
}

/// Anneau de progression avec une valeur au centre.
struct RingView: View {
    let percent: Double
    let tone: UsageTone
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                .stroke(tone.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent.rounded())) %").font(.system(size: 12, weight: .medium))
        }
        .frame(width: size, height: size)
    }
}

/// Fond des cartes du popover.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(10)
    }
}

extension View {
    func popoverCard() -> some View { modifier(CardBackground()) }
}

enum PaceText {
    static func chip(for forecast: WindowForecast?, percent: Int) -> String? {
        if percent >= 100 { return "Limite atteinte" }
        switch forecast?.pace {
        case .under:   return "En dessous du rythme"
        case .onTrack: return "En rythme"
        case .over:    return "Trop rapide"
        case nil:      return nil
        }
    }

    static func summary(for forecast: WindowForecast?, showsDailyBudget: Bool) -> String {
        var parts: [String] = []
        if let projected = forecast?.projectedPercent {
            parts.append("≈ \(Int(projected.rounded())) % au reset")
        } else if forecast != nil {
            parts.append("estimation dans quelques minutes")
        }
        if showsDailyBudget, let perDay = forecast?.remainingPerDay, (forecast?.usedPercent ?? 0) < 100 {
            parts.append("\(Int(perDay.rounded())) % par jour")
        }
        return parts.joined(separator: " · ")
    }
}
