#!/usr/bin/env bash
set -euo pipefail

# Scaffolding directories for Titik
CONFIG_DIR="${HOME}/.config/titik"
PLUGINS_DIR="${HOME}/.config/titik/plugins"
STATE_DIR="${HOME}/.local/state/titik"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_CONFIG="${PROJECT_ROOT}/config/config.default.json"
TARGET_CONFIG="${CONFIG_DIR}/config.json"

FORCE=0
for arg in "$@"; do
    if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
        FORCE=1
    fi
done

echo "==> Setting up Titik directories..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${PLUGINS_DIR}"
mkdir -p "${STATE_DIR}"

if [ ! -f "${TARGET_CONFIG}" ] || [ "${FORCE}" -eq 1 ]; then
    echo "==> Installing default configuration to ${TARGET_CONFIG}..."
    cp "${DEFAULT_CONFIG}" "${TARGET_CONFIG}"
    echo "==> Configuration installed successfully."
else
    echo "==> Existing configuration detected at ${TARGET_CONFIG}. Keeping existing config (pass --force to overwrite)."
fi

# Ensure log directory is writable
touch "${STATE_DIR}/titik.log"

echo "==> Titik environment setup complete."
echo "    Config:  ${TARGET_CONFIG}"
echo "    Plugins: ${PLUGINS_DIR}"
echo "    Logs:    ${STATE_DIR}/titik.log"
