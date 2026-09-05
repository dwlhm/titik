#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLUGINS_DIR="${PROJECT_ROOT}/bin/plugins"
MANIFEST_PATH="${PROJECT_ROOT}/config/notes_manifest.json"

echo "==> Building Notes.bundle..."

# 1. Locate module dependencies
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

mkdir -p "${PROJECT_ROOT}/.build/clang-cache" "${PROJECT_ROOT}/.build/tmp" "${PLUGINS_DIR}"
COMPILED_DYLIB="${PROJECT_ROOT}/.build/libNotes.dylib"

EXTRA_INCLUDES=()
for inc in "${PROJECT_ROOT}/.build/checkouts/swift-markdown/Sources/CAtomic/include" \
           "${PROJECT_ROOT}/.build/checkouts/swift-cmark/extensions/include" \
           "${PROJECT_ROOT}/.build/checkouts/swift-cmark/src/include"; do
    if [ -d "${inc}" ]; then
        EXTRA_INCLUDES+=("-I" "${inc}")
    fi
done

# 2. Compile sources into Mach-O dylib
CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/.build/clang-cache" \
TMPDIR="${PROJECT_ROOT}/.build/tmp" \
swiftc -emit-library \
    -module-name Notes \
    -I "${MODULES_PATH}" \
    "${EXTRA_INCLUDES[@]}" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NoteConfig.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NoteModel.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NoteStorage.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NoteTemplateEngine.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/LiveMarkdownTextView.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NotesViewModel.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NotesView.swift" \
    "${PROJECT_ROOT}/Sources/TitikPlugins/Reference/Notes/NotesPlugin.swift" \
    -o "${COMPILED_DYLIB}"

# 3. Package bundle using build_plugin_bundle.sh
bash "${PROJECT_ROOT}/scripts/build_plugin_bundle.sh" \
    "Notes" \
    "${COMPILED_DYLIB}" \
    "${MANIFEST_PATH}" \
    "${PLUGINS_DIR}"

echo "==> Notes.bundle packaging complete."
