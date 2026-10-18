#!/bin/bash
# Build local sans Xcode.app ni certificat Developer ID : Command Line Tools + signature ad-hoc.
# Pourquoi le SDK 26 : avec le SDK 27, @State devient une macro (plugin SwiftUIMacros)
# qui n'est livrée qu'avec Xcode.app.
set -euo pipefail

cd "$(dirname "$0")/.."
SDK_ROOT=/Library/Developer/CommandLineTools/SDKs
SDK="${CUB_SDK:-$SDK_ROOT/MacOSX26.5.sdk}"
[ -d "$SDK" ] || SDK="$SDK_ROOT/MacOSX26.sdk"
[ -d "$SDK" ] || { echo "SDK 26 introuvable dans $SDK_ROOT" >&2; exit 1; }

APP=build/ClaudeUsageBar.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/"
cp app/ClaudeUsageBar.icns "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

swiftc -parse-as-library -sdk "$SDK" -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/ClaudeUsageBar" app/*.swift \
    -framework SwiftUI -framework AppKit -framework WebKit

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"
echo "OK : $APP"
