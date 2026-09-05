#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLUGINS_DIR="${PROJECT_ROOT}/bin/plugins"
BUNDLE_DIR="${PLUGINS_DIR}/ZenBrowser.bundle"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ZenBrowser.bundle..."

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 1. Generate Resources/manifest.json
cat > "${RESOURCES_DIR}/manifest.json" << 'MANIFEST_EOF'
{
  "id": "titik.plugin.zen",
  "name": "Zen Browser",
  "icon": "🧘",
  "version": "1.0.0",
  "sdkVersion": 2,
  "description": "Control Zen Browser tabs, windows, and profiles",
  "entrypoint": "ZenBrowserPlugin",
  "triggers": [
    "!zen",
    "zen"
  ],
  "permissions": [
    "workspace:launch"
  ]
}
MANIFEST_EOF

# 2. Generate Contents/Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>titik.plugin.zen</string>
    <key>CFBundleName</key>
    <string>ZenBrowser</string>
    <key>CFBundleExecutable</key>
    <string>ZenBrowser</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>NSPrincipalClass</key>
    <string>ZenBrowserPlugin</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
PLIST_EOF

# 3. Locate module dependencies
MODULES_PATH=""
if [ -d "${PROJECT_ROOT}/.build/release/Modules" ]; then
    MODULES_PATH="${PROJECT_ROOT}/.build/release/Modules"
elif [ -d "${PROJECT_ROOT}/.build/arm64-apple-macosx/release/Modules" ]; then
    MODULES_PATH="${PROJECT_ROOT}/.build/arm64-apple-macosx/release/Modules"
elif [ -d "${PROJECT_ROOT}/.build/debug/Modules" ]; then
    MODULES_PATH="${PROJECT_ROOT}/.build/debug/Modules"
elif [ -d "${PROJECT_ROOT}/.build/arm64-apple-macosx/debug/Modules" ]; then
    MODULES_PATH="${PROJECT_ROOT}/.build/arm64-apple-macosx/debug/Modules"
else
    MODULES_PATH=$(find "${PROJECT_ROOT}/.build" -type d -name "Modules" 2>/dev/null | head -n 1)
fi

if [ -z "${MODULES_PATH}" ] || [ ! -d "${MODULES_PATH}" ]; then
    echo "==> Building Titik dependencies..."
    swift build --disable-sandbox
    MODULES_PATH=$(find "${PROJECT_ROOT}/.build" -type d -name "Modules" 2>/dev/null | head -n 1)
fi

mkdir -p "${PROJECT_ROOT}/.build/clang-cache" "${PROJECT_ROOT}/.build/tmp"

EXTRA_INCLUDES=()
for inc in "${PROJECT_ROOT}/.build/checkouts/swift-markdown/Sources/CAtomic/include" \
           "${PROJECT_ROOT}/.build/checkouts/swift-cmark/extensions/include" \
           "${PROJECT_ROOT}/.build/checkouts/swift-cmark/src/include"; do
    if [ -d "${inc}" ]; then
        EXTRA_INCLUDES+=("-I" "${inc}")
    fi
done

# 4. Compile Mach-O bundle library
CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/.build/clang-cache" \
TMPDIR="${PROJECT_ROOT}/.build/tmp" \
swiftc -emit-library \
    -module-name ZenBrowser \
    -target arm64-apple-macosx13.0 \
    -swift-version 6 \
    -O \
    -I "${MODULES_PATH}" \
    "${EXTRA_INCLUDES[@]}" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/ZenBrowser/ZenBrowserPlugin.swift" \
    -o "${MACOS_DIR}/ZenBrowser"

chmod +x "${MACOS_DIR}/ZenBrowser"

# 5. Codesign the bundle
codesign -s - -f "${BUNDLE_DIR}"
touch "${BUNDLE_DIR}"

echo "==> ZenBrowser.bundle built and signed at ${BUNDLE_DIR}"
