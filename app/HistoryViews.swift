import SwiftUI

/// Courbe d'une série sur les dernières heures. Le tracé est interrompu à chaque remise à zéro.
struct HistoryChart: View {
    let points: [(time: Date, percent: Double)]
    /// Durée couverte par l'axe horizontal, de `maintenant - span` à maintenant.
    let span: TimeInterval
    let color: Color

    var body: some View {
        Canvas { context, size in
            let now = Date()
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
                context.draw(Text("\(Int(level)) %").font(.system(size: 9)).foregroundColor(.secondary),
                             at: CGPoint(x: 2, y: y + (level == 100 ? 7 : -7)), anchor: .leading)
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
            if let last = points.last {
                let end = position(last)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
            }
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

    /// Durée affichée : exactement celle des relevés disponibles.
    private var span: TimeInterval { UsageAnalytics.chartSpan(firstSample: points.first?.time) }

    var body: some View {
        if points.count >= 10 {
            DisclosureGroup("Historique · \(AlertRules.duration(span))", isExpanded: $isOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HistoryChart(points: points, span: span, color: usageManager.sessionTone.color)
                    HStack {
                        Text("il y a \(AlertRules.duration(span))").font(.system(size: 10)).foregroundColor(Color.secondaryText)
                        Spacer()
                        Text("session · maintenant \(usageManager.sessionUsage) %").font(.system(size: 10)).foregroundColor(Color.secondaryText)
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
