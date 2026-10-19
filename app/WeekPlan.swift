import Foundation

/// Part de la limite hebdomadaire utilisable chaque jour jusqu'au reset, au prorata des heures de chaque jour.
struct PlanSegment: Equatable {
    let label: String
    let percent: Double
    let isToday: Bool
}

enum WeekPlan {
    static func make(used: Double, now: Date, resetsAt: Date, calendar: Calendar = .current) -> [PlanSegment] {
        let totalSeconds = resetsAt.timeIntervalSince(now)
        let remaining = 100 - min(max(used, 0), 100)
        guard totalSeconds > 0, remaining > 0 else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE"

        var segments: [PlanSegment] = []
        var start = now
        var dayIndex = 0
        while start < resetsAt, dayIndex < 10 {
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? resetsAt
            let end = min(nextMidnight, resetsAt)
            let share = remaining * end.timeIntervalSince(start) / totalSeconds
            let label = dayIndex == 0 ? "auj." : (dayIndex == 1 ? "dem." : formatter.string(from: start).replacingOccurrences(of: ".", with: ""))
            segments.append(PlanSegment(label: label, percent: share, isToday: dayIndex == 0))
            start = end
            dayIndex += 1
        }
        return segments
    }
}
