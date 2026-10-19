#!/bin/bash
# Tests unitaires de la logique pure (sans UI) : compile le module avec les tests puis les exécute.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -o build/tests app/StatuslineUsage.swift app/KeychainStore.swift app/SecretStore.swift app/AppSecrets.swift app/UsageForecast.swift app/MenuBarDisplay.swift app/ApiCredits.swift app/ConsoleBalance.swift app/SyncHelpers.swift app/RefreshPolicy.swift app/DesignModels.swift app/PaceText.swift app/UsageAnalytics.swift app/AlertRules.swift app/WeekPlan.swift app/ForecastExport.swift app/UsageHistory.swift app/CreditsSummary.swift app/FirefoxCookies.swift tests/main.swift 2>&1 | grep -E 'error' || true
build/tests
