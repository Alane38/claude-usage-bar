import SwiftUI

/// Ligne de prévision sous une barre de limite (session ou hebdo).
struct ForecastLine: View {
    let forecast: WindowForecast
    let showsDailyBudget: Bool

    private var paceColor: Color {
        switch forecast.pace {
        case .over:    return .red
        case .onTrack: return Color.secondaryText
        case .under:   return .green
        }
    }

    private var summary: String {
        if forecast.usedPercent >= 100 { return "Limite atteinte" }
        guard let projected = forecast.projectedPercent else {
            return "Trop tôt pour estimer · rythme régulier : \(Int(forecast.expectedPercent)) %"
        }
        if let exhaustsAt = forecast.exhaustsAt {
            let time = exhaustsAt.formatted(date: .omitted, time: .shortened)
            return "Trop rapide : 100 % vers \(time), avant le reset"
        }
        return "≈ \(Int(projected.rounded())) % au reset · rythme régulier : \(Int(forecast.expectedPercent)) %"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(summary)
                .font(.caption2)
                .foregroundColor(paceColor)
            if showsDailyBudget && forecast.usedPercent < 100 {
                Text("Budget : \(Int(forecast.remainingPerDay.rounded())) % par jour d'ici au reset")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
            }
        }
    }
}

/// Crédits API mensuels (Max/Team) : dépense saisie à la main, reste et budget calculés.
struct ApiCreditsTile: View {
    let credits: ApiCredits

    private func dollars(_ value: Double) -> String {
        String(format: "%.0f $", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Crédits API")
                    .font(.subheadline)
                Spacer()
                Text("expirent dans \(credits.daysLeft()) j")
                    .font(.caption)
                    .foregroundColor(Color.secondaryText)
            }
            UsageBar(value: credits.usedFraction,
                     color: credits.usedFraction < 0.9 ? .accentColor : .orange)
            HStack {
                Text("\(dollars(credits.spent)) dépensés sur \(dollars(credits.monthlyAmount))")
                    .font(.caption)
                    .foregroundColor(Color.secondaryText)
                Spacer()
                if let perDay = credits.dailyBudget() {
                    Text("\(dollars(perDay)) / jour")
                        .font(.caption)
                        .foregroundColor(Color.secondaryText)
                }
            }
        }
    }
}

/// Réglages de la barre de menu et des crédits API.
struct DisplaySettingsView: View {
    @ObservedObject var usageManager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Barre de menu")
                .font(.caption.weight(.semibold))
            Picker("Valeur affichée", selection: Binding(
                get: { usageManager.menuBarMode },
                set: { usageManager.menuBarMode = $0; usageManager.saveDisplaySettings() }
            )) {
                ForEach(MenuBarMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .font(.caption)
            Toggle("Afficher le temps avant le reset", isOn: Binding(
                get: { usageManager.menuBarShowReset },
                set: { usageManager.menuBarShowReset = $0; usageManager.saveDisplaySettings() }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            Divider()

            Text("Crédits API (Max / Team)")
                .font(.caption.weight(.semibold))
            if usageManager.apiCreditCycleEnd == nil {
                Button("Activer la tuile crédits") {
                    usageManager.apiCreditCycleEnd = Date().addingTimeInterval(30 * 86400)
                    usageManager.saveDisplaySettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                creditsFields
            }
        }
    }

    @ViewBuilder
    private var creditsFields: some View {
        HStack {
            Text("Montant mensuel ($)").font(.caption)
            Spacer()
            TextField("100", value: Binding(
                get: { usageManager.apiCreditMonthly },
                set: { usageManager.apiCreditMonthly = $0; usageManager.saveDisplaySettings() }
            ), format: .number)
            .frame(width: 60)
        }
        HStack {
            Text("Dépensé ($)").font(.caption)
            Spacer()
            TextField("0", value: Binding(
                get: { usageManager.apiCreditSpent },
                set: { usageManager.apiCreditSpent = $0; usageManager.saveDisplaySettings() }
            ), format: .number)
            .frame(width: 60)
        }
        DatePicker("Fin du cycle", selection: Binding(
            get: { usageManager.apiCreditCycleEnd ?? Date() },
            set: { usageManager.apiCreditCycleEnd = $0; usageManager.saveDisplaySettings() }
        ), displayedComponents: .date)
        .font(.caption)
        Text("Aucun endpoint public ne donne le solde : relève « Promotional credits » sur platform.claude.com/settings/billing.")
            .font(.caption2)
            .foregroundColor(Color.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        Button("Masquer la tuile crédits") {
            usageManager.apiCreditCycleEnd = nil
            usageManager.saveDisplaySettings()
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
