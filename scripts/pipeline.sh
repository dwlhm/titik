#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Parse flags
FAST=false
STRICT=false

if [ "${STRICT:-}" = "1" ] || [ "${STRICT:-}" = "true" ]; then
    STRICT=true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --fast)
            FAST=true
            shift
            ;;
        --strict)
            STRICT=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--fast] [--strict]" >&2
            exit 1
            ;;
    esac
done

echo "======================================================================="
echo "  Titik Verification Pipeline"
echo "  Mode: Fast=${FAST}, Strict=${STRICT}"
echo "======================================================================="

# Environment resolution
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)}"
export NCPU="${NCPU:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

mkdir -p "${PROJECT_ROOT}/.build/clang-cache" "${PROJECT_ROOT}/.build/tmp"
export CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/.build/clang-cache"
export TMPDIR="${PROJECT_ROOT}/.build/tmp"
export DYLD_LIBRARY_PATH="${DEVELOPER_DIR}/Library/Developer/usr/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export DYLD_FRAMEWORK_PATH="${DEVELOPER_DIR}/Library/Developer/Frameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
export SWIFT_TEST_FLAGS="-Xswiftc -F${DEVELOPER_DIR}/Library/Developer/Frameworks -Xlinker -rpath -Xlinker ${DEVELOPER_DIR}/Library/Developer/Frameworks -Xlinker -rpath -Xlinker ${DEVELOPER_DIR}/Library/Developer/usr/lib"

SWIFT_FORMAT_BIN="$(command -v swift-format 2>/dev/null || true)"
SWIFTLINT_BIN="$(command -v swiftlint 2>/dev/null || true)"

# ----------------------------------------------------------------------
# Stage 1: Format Check
# ----------------------------------------------------------------------
echo ""
echo "--> [Stage 1/4] Checking code formatting..."
if [ -n "${SWIFT_FORMAT_BIN}" ]; then
    make format-check
elif [ "${STRICT}" = true ]; then
    echo "ERROR: swift-format is required in strict mode but not installed." >&2
    exit 1
else
    echo "--> [WARN] swift-format not found; skipping format check (non-strict mode)."
fi

# ----------------------------------------------------------------------
# Stage 2: SwiftLint Static Analysis
# ----------------------------------------------------------------------
echo ""
echo "--> [Stage 2/4] Running SwiftLint..."
if [ -n "${SWIFTLINT_BIN}" ]; then
    make lint
elif [ "${STRICT}" = true ]; then
    echo "ERROR: swiftlint is required in strict mode but not installed." >&2
    exit 1
else
    echo "--> [WARN] swiftlint not found; skipping lint check (non-strict mode)."
fi

# ----------------------------------------------------------------------
# Stage 3: Test Suite Verification
# ----------------------------------------------------------------------
echo ""
if [ "${FAST}" = true ]; then
    echo "--> [Stage 3/4] Running modular fast unit tests (--fast mode)..."
    make test-unit
else
    echo "--> [Stage 3/4] Running comprehensive full test suite (58 suites)..."
    make test
fi

# ----------------------------------------------------------------------
# Stage 4: Bundle & Packaging Verification
# ----------------------------------------------------------------------
echo ""
if [ "${FAST}" = true ]; then
    echo "--> [Stage 4/4] Skipping bundle & packaging (--fast mode enabled)."
else
    echo "--> [Stage 4/4] Building release binary, dynamic plugins, and app bundle..."
    make bundle
fi

echo ""
echo "======================================================================="
echo "  All pipeline stages passed successfully!"
echo "======================================================================="
