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
                                  text: "\(usageManager.weeklyUsage) %", color: Color.primary.opacity(0.35))
                            ForEach(Array(plan.enumerated()), id: \.offset) { _, segment in
                                block(width: width(segment.percent, geo.size.width, count: plan.count),
                                      text: "\(Int(segment.percent.rounded())) %",
                                      color: usageManager.weeklyTone.color.opacity(segment.isToday ? 0.9 : 0.55))
                            }
                        }
                    }
                    .frame(height: 24)
                    labels(plan)
                    Text("Part de la limite à ne pas dépasser chaque jour pour arriver au reset (\(usageManager.weeklyResetsAt.map(AlertRules.dayAndClock) ?? "")) sans être bloqué.")
                        .font(.system(size: 10))
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
            if width >= 34 { Text(text).font(.system(size: 10, weight: .medium)).foregroundColor(.white) }
        }
        .frame(width: width)
    }

    private func labels(_ plan: [PlanSegment]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Color.clear.frame(width: width(Double(usageManager.weeklyUsage), geo.size.width, count: plan.count))
                ForEach(Array(plan.enumerated()), id: \.offset) { _, segment in
                    Text(segment.label)
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: width(segment.percent, geo.size.width, count: plan.count))
                }
            }
        }
        .frame(height: 26)
    }
}
