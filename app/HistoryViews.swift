import SwiftUI

/// Courbe d'une série sur les dernières heures. Le tracé est interrompu à chaque remise à zéro.
struct HistoryChart: View {
    let points: [(time: Date, percent: Double)]
    let hours: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            let now = Date()
            let span = hours * 3600
            func position(_ point: (time: Date, percent: Double)) -> CGPoint {
                CGPoint(x: size.width * CGFloat(1 - now.timeIntervalSince(point.time) / span),
                        y: size.height * CGFloat(1 - min(max(point.percent, 0), 100) / 100))
            }
            for level in [50.0, 100.0] {
                var guide = Path()
                let y = size.height * CGFloat(1 - level / 100)
                guide.move(to: CGPoint(x: 0, y: y))
                guide.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(guide, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            var path = Path()
            var previous: (time: Date, percent: Double)?
            for point in points {
                let location = position(point)
                if let previous, !UsageAnalytics.breaksLine(from: previous, to: point) {
                    path.addLine(to: location)
                } else {
                    path.move(to: location)
                }
                previous = point
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: 56)
    }
}

/// Bloc repliable : courbe de la session sur 24 h, consommation du jour.
struct HistoryDisclosure: View {
    @ObservedObject var usageManager: UsageManager
    @State private var isOpen = CommandLine.arguments.contains("--open-history")

    private var points: [(time: Date, percent: Double)] {
        UsageAnalytics.series(usageManager.historySamples, series: .session)
    }

    /// Durée affichée : celle de l'historique réellement disponible (1, 3, 6, 12 ou 24 h).
    private var hours: Double {
        guard let first = points.first else { return 24 }
        return UsageAnalytics.chartHours(forSpan: Date().timeIntervalSince(first.time))
    }

    var body: some View {
        if points.count >= 10 {
            DisclosureGroup("Historique · \(Int(hours)) h", isExpanded: $isOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HistoryChart(points: points, hours: hours, color: usageManager.sessionTone.color)
                    HStack {
                        Text("il y a \(Int(hours)) h").font(.system(size: 10)).foregroundColor(Color.secondaryText)
                        Spacer()
                        Text("session · maintenant").font(.system(size: 10)).foregroundColor(Color.secondaryText)
                    }
                    if let today = PaceText.todayLine(usageManager.weeklyUsedToday) {
                        Text(today).font(.caption).foregroundColor(Color.secondaryText)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
            .foregroundColor(Color.secondaryText)
        }
    }
}
