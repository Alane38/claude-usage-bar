#!/bin/bash
# Tests unitaires de la logique pure (sans UI) : compile le module avec les tests puis les exécute.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -o build/tests app/StatuslineUsage.swift app/KeychainStore.swift app/UsageForecast.swift app/MenuBarDisplay.swift app/ApiCredits.swift tests/main.swift 2>&1 | grep -E 'error' || true
build/tests
