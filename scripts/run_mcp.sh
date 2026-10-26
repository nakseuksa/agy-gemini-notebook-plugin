#!/usr/bin/env bash
# Portable MCP Server launcher for Antigravity 2, VS Code, Cursor, and Claude Code.
# Automatically resolves the plugin's virtual environment (.venv), `uv`, or system Python.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export PYTHONPATH="${PLUGIN_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"

if [[ -x "${PLUGIN_DIR}/.venv/bin/python" ]]; then
    exec "${PLUGIN_DIR}/.venv/bin/python" -m agy_gemini_notebook.mcp_server "$@"
fi

if [[ -f "${PLUGIN_DIR}/.venv/Scripts/python.exe" ]]; then
    exec "${PLUGIN_DIR}/.venv/Scripts/python.exe" -m agy_gemini_notebook.mcp_server "$@"
fi

if command -v uv >/dev/null 2>&1; then
    exec uv run --project "${PLUGIN_DIR}" agy-gemini-notebook-mcp "$@"
fi

if [[ -x "${HOME}/.local/bin/uv" ]]; then
    exec "${HOME}/.local/bin/uv" run --project "${PLUGIN_DIR}" agy-gemini-notebook-mcp "$@"
fi

if command -v python3 >/dev/null 2>&1 && python3 -c "import sys" >/dev/null 2>&1; then
    exec python3 -m agy_gemini_notebook.mcp_server "$@"
fi
exec python -m agy_gemini_notebook.mcp_server "$@"
