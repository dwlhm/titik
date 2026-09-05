#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <name> <dylib_or_source> <manifest_path> <output_dir>"
    exit 1
fi

NAME="$1"
BINARY_OR_SOURCE="$2"
MANIFEST_PATH="$3"
OUTPUT_DIR="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUNDLE_DIR="${OUTPUT_DIR}/${NAME}.bundle"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 1. Parse manifest fields for Info.plist
BUNDLE_ID=$(python3 -c "import json; data=json.load(open('${MANIFEST_PATH}')); print(data.get('id', 'titik.plugin.${NAME}'))")
VERSION=$(python3 -c "import json; data=json.load(open('${MANIFEST_PATH}')); print(data.get('version', '1.0.0'))")
ENTRYPOINT=$(python3 -c "import json; data=json.load(open('${MANIFEST_PATH}')); print(data.get('entrypoint', '${NAME}Plugin'))")

# 2. Build or copy executable
TARGET_EXEC="${MACOS_DIR}/${NAME}"

if [[ "${BINARY_OR_SOURCE}" == *.swift ]]; then
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

    CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/.build/clang-cache" \
    TMPDIR="${PROJECT_ROOT}/.build/tmp" \
    swiftc -emit-library \
        -I "${MODULES_PATH}" \
        "${EXTRA_INCLUDES[@]}" \
        -Xlinker -undefined -Xlinker dynamic_lookup \
        "${BINARY_OR_SOURCE}" \
        -o "${TARGET_EXEC}"
else
    cp "${BINARY_OR_SOURCE}" "${TARGET_EXEC}"
fi

chmod +x "${TARGET_EXEC}"

# 3. Copy manifest.json into Contents/Resources
cp "${MANIFEST_PATH}" "${RESOURCES_DIR}/manifest.json"

# 4. Generate Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${NAME}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>NSPrincipalClass</key>
    <string>${ENTRYPOINT}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
</dict>
</plist>
PLIST_EOF

# 5. Codesign bundle
codesign -s - -f "${BUNDLE_DIR}" 2>/dev/null || true

echo "==> Plugin bundle created successfully at ${BUNDLE_DIR}"
