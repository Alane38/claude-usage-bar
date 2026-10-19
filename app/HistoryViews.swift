import SwiftUI

/// Courbe d'une série. Choix issus des bonnes pratiques de visualisation :
/// ligne de 2 pt, lavis léger sous la courbe, grille pleine et discrète, axe étiqueté, étiquettes ciblées (valeur finale,
/// pic), repère de survol avec info-bulle, tracé interrompu aux remises à zéro et aux trous de données.
struct HistoryChart: View {
    let points: [(time: Date, percent: Double)]
    /// Durée couverte par l'axe horizontal, de `maintenant - span` à maintenant.
    let span: TimeInterval
    let color: Color

    @State private var hoverX: CGFloat?
    private let plotHeight: CGFloat = 76
    /// Marge horizontale : le point final (8 pt + anneau) ne doit pas être rogné au bord.
    private let inset: CGFloat = 7

    private var ceiling: Double {
        UsageAnalytics.chartCeiling(maxPercent: points.map(\.percent).max() ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(context, size) }
                hoverLayer(width: geo.size.width)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let location) = phase { hoverX = location.x } else { hoverX = nil }
            }
        }
        .frame(height: plotHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    // MARK: - Dessin

    private func position(_ point: (time: Date, percent: Double), in size: CGSize) -> CGPoint {
        CGPoint(x: inset + (size.width - 2 * inset) * CGFloat(1 - Date().timeIntervalSince(point.time) / span),
                y: size.height * CGFloat(1 - min(max(point.percent, 0), ceiling) / ceiling))
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        drawGrid(context, size)
        var segments: [[CGPoint]] = []
        var previous: (time: Date, percent: Double)?
        for point in points {
            let location = position(point, in: size)
            if let previous, !UsageAnalytics.breaksLine(from: previous, to: point) { segments[segments.count - 1].append(location) }
            else { segments.append([location]) }
            previous = point
        }
        for segment in segments where segment.count >= 2 {
            var line = Path()
            line.move(to: segment[0])
            segment.dropFirst().forEach { line.addLine(to: $0) }
            var area = line
            area.addLine(to: CGPoint(x: segment[segment.count - 1].x, y: size.height))
            area.addLine(to: CGPoint(x: segment[0].x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(color.opacity(0.10)))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        drawLabels(context, size)
    }

    /// Grille : lignes pleines d'un pixel, une teinte au-dessus du fond ; étiquettes d'axe en encre discrète.
    private func drawGrid(_ context: GraphicsContext, _ size: CGSize) {
        for level in [0.0, ceiling / 2, ceiling] {
            let y = size.height * CGFloat(1 - level / ceiling)
            var rule = Path()
            rule.move(to: CGPoint(x: 0, y: y))
            rule.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(rule, with: .color(.primary.opacity(level == 0 ? 0.22 : 0.10)), lineWidth: 0.5)
            if level > 0 {
                // Le repère du haut se lit sous sa ligne, celui du milieu au-dessus : aucun n'est rogné.
                context.draw(Text("\(Int(level)) %").font(.system(size: 9)).foregroundColor(.secondary),
                             at: CGPoint(x: 0, y: level == ceiling ? y + 7 : y - 6), anchor: .leading)
            }
        }
    }

    /// Étiquettes ciblées : la valeur finale et, si elle s'en distingue, le pic. Jamais un chiffre sur chaque point.
    private func drawLabels(_ context: GraphicsContext, _ size: CGSize) {
        guard let last = points.last else { return }
        let end = position(last, in: size)
        let surface = Color(nsColor: .windowBackgroundColor)
        context.fill(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)), with: .color(surface))
        context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(color))
        context.draw(Text("\(Int(last.percent.rounded())) %").font(.system(size: 11, weight: .medium)).foregroundColor(.primary),
                     at: CGPoint(x: end.x - 9, y: max(end.y - 11, 6)), anchor: .trailing)
        if let peak = points.max(by: { $0.percent < $1.percent }), peak.percent - last.percent >= 8 {
            let location = position(peak, in: size)
            context.draw(Text("pic \(Int(peak.percent.rounded())) %").font(.system(size: 10)).foregroundColor(.secondary),
                         at: CGPoint(x: min(max(location.x, 28), size.width - 28), y: max(location.y - 9, 6)))
        }
    }

    // MARK: - Survol

    @ViewBuilder
    private func hoverLayer(width: CGFloat) -> some View {
        if let hoverX, width > 0 {
            let date = Date().addingTimeInterval(-span * Double(1 - (hoverX - inset) / (width - 2 * inset)))
            if let index = UsageAnalytics.nearestIndex(in: points, to: date) {
                let point = points[index]
                let x = inset + (width - 2 * inset) * CGFloat(1 - Date().timeIntervalSince(point.time) / span)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1, height: plotHeight).offset(x: x)
                    Text("\(AlertRules.clock(point.time)) · \(Int(point.percent.rounded())) %")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .offset(x: min(max(x - 36, 0), max(width - 80, 0)), y: -2)
                }
                .allowsHitTesting(false)
            }
        }
    }

    /// Résumé lu par VoiceOver : la courbe n'est jamais la seule façon d'accéder aux valeurs.
    private var summary: String {
        guard let first = points.first, let last = points.last, let peak = points.map(\.percent).max() else { return "Historique vide" }
        return "Historique de la session sur \(AlertRules.duration(span)) : de \(Int(first.percent.rounded())) % à \(Int(last.percent.rounded())) %, pic à \(Int(peak.rounded())) %."
    }
}

/// Bloc repliable : courbe de la session, consommation du jour.
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
            DisclosureGroup("Historique de la session · \(AlertRules.duration(span))", isExpanded: $isOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HistoryChart(points: points, span: span, color: usageManager.sessionTone.color)
                    HStack {
                        Text("il y a \(AlertRules.duration(span))")
                        Spacer()
                        Text("maintenant")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondaryText)
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
