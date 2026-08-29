#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${PROJECT_ROOT}/bin"
APP_BUNDLE="${BIN_DIR}/Titik.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
PLUGINS="${CONTENTS}/PlugIns"

echo "==> Packaging Titik.app..."

mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"
mkdir -p "${PLUGINS}"

if [ ! -f "${BIN_DIR}/titik" ]; then
    echo "ERROR: Executable ${BIN_DIR}/titik not found. Run 'make build' first." >&2
    exit 1
fi

cp "${BIN_DIR}/titik" "${MACOS}/titik"
chmod +x "${MACOS}/titik"

if [ -f "${PROJECT_ROOT}/config/config.default.json" ]; then
    cp "${PROJECT_ROOT}/config/config.default.json" "${RESOURCES}/config.default.json"
fi

if [ -f "${PROJECT_ROOT}/plugins/math_plugin/math.dylib" ]; then
    cp "${PROJECT_ROOT}/plugins/math_plugin/math.dylib" "${PLUGINS}/math.dylib"
fi

cat > "${CONTENTS}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>titik</string>
    <key>CFBundleIdentifier</key>
    <string>com.titik.app</string>
    <key>CFBundleName</key>
    <string>Titik</string>
    <key>CFBundleDisplayName</key>
    <string>Titik</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Titik requires permission to run system actions such as sleep, restart, and dark mode.</string>
</dict>
</plist>
EOF

codesign -s - --force --deep "${APP_BUNDLE}" 2>/dev/null || true

echo "==> Titik.app created successfully at ${APP_BUNDLE}"
