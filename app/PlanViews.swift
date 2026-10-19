import SwiftUI

/// Planning de la semaine : ce qui est déjà consommé, puis la part utilisable chaque jour jusqu'au reset.
struct WeekPlanDisclosure: View {
    @ObservedObject var usageManager: UsageManager
    @State private var isOpen = CommandLine.arguments.contains("--open-plan")

    private var segments: [PlanSegment] {
        guard let resetsAt = usageManager.weeklyResetsAt else { return [] }
        return WeekPlan.make(used: Double(usageManager.weeklyUsage), now: Date(), resetsAt: resetsAt)
    }

    var body: some View {
        let plan = segments
        if !plan.isEmpty {
            DisclosureGroup("Planning de la semaine", isExpanded: $isOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            block(width: width(Double(usageManager.weeklyUsage), geo.size.width, count: plan.count),
                                  text: "\(usageManager.weeklyUsage) %", color: Color.primary.opacity(0.16))
                            ForEach(Array(plan.enumerated()), id: \.offset) { _, segment in
                                block(width: width(segment.percent, geo.size.width, count: plan.count),
                                      text: "\(Int(segment.percent.rounded())) %",
                                      color: usageManager.weeklyTone.color.opacity(segment.isToday ? 0.55 : 0.28))
                            }
                        }
                    }
                    .frame(height: 24)
                    labels(plan)
                    Text("Part de la limite à ne pas dépasser chaque jour pour arriver au reset (\(usageManager.weeklyResetsAt.map(AlertRules.dayAndClock) ?? "")) sans être bloqué.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondaryText)
                }
                .padding(.top, 6)
            }
            .font(.caption)
            .foregroundColor(Color.secondaryText)
        }
    }

    /// Largeur d'un bloc au prorata de son pourcentage, en retirant l'espace entre les blocs.
    private func width(_ percent: Double, _ total: CGFloat, count: Int) -> CGFloat {
        max((total - CGFloat(count) * 2) * CGFloat(percent / 100), 2)
    }

    private func block(width: CGFloat, text: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(color)
            if width >= 34 { Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(.primary) }
        }
        .frame(width: width)
    }

    /// Une étiquette par bloc, centrée sous lui, écartée si elle chevaucherait la précédente (blocs étroits en fin de semaine).
    private func labels(_ plan: [PlanSegment]) -> some View {
        GeometryReader { geo in
            let used = width(Double(usageManager.weeklyUsage), geo.size.width, count: plan.count)
            let widths = [used] + plan.map { width($0.percent, geo.size.width, count: plan.count) }
            let texts = ["utilisé"] + plan.map(\.label)
            let placed = Self.placeLabels(texts: texts, blockWidths: widths, gap: 2)
            ZStack(alignment: .topLeading) {
                ForEach(placed, id: \.index) { label in
                    Text(texts[label.index]).font(.system(size: 11)).fixedSize().position(x: label.centerX, y: 7)
                }
            }
        }
        .frame(height: 14)
    }

    /// Centres des étiquettes retenues : on garde une étiquette si elle ne recouvre pas la dernière gardée.
    static func placeLabels(texts: [String], blockWidths: [CGFloat], gap: CGFloat) -> [(index: Int, centerX: CGFloat)] {
        var result: [(index: Int, centerX: CGFloat)] = []
        var cursor: CGFloat = 0
        var lastRight: CGFloat = -.infinity
        for (index, width) in blockWidths.enumerated() {
            let center = cursor + width / 2
            let labelWidth = CGFloat(texts[index].count) * 6.2 + 4
            if center - labelWidth / 2 >= lastRight + 2 {
                result.append((index, center))
                lastRight = center + labelWidth / 2
            }
            cursor += width + gap
        }
        return result
    }
}
