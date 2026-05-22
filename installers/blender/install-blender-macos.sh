#!/bin/bash
# Version: 1.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/opencode-lib.sh"

# ---------------------------------------------------------------------------
# Step 1: Install uv (Python package manager)
# ---------------------------------------------------------------------------
if ! command -v uv &>/dev/null; then
    echo "uv is not installed. Installing now…"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uv &>/dev/null; then
        echo "Error: uv installation failed – 'uv' not found after install." >&2
        exit 1
    fi
    add_to_shell_config "uv" ".local/bin" '$HOME/.local/bin:$PATH'
fi
echo "✓ uv is installed."

# ---------------------------------------------------------------------------
# Step 2: Install blender-mcp via uv
# ---------------------------------------------------------------------------
echo "Installing blender-mcp package via uv…"
uv tool install blender-mcp
echo "✓ blender-mcp installed."

# ---------------------------------------------------------------------------
# Step 3: Ensure opencode.json exists and is valid
# ---------------------------------------------------------------------------
ensure_opencode_config

# ---------------------------------------------------------------------------
# Step 4: Bail if blender is already configured
# ---------------------------------------------------------------------------
ensure_mcp_not_configured "blender"

# ---------------------------------------------------------------------------
# Step 5: Add blender MCP server to opencode.json
# ---------------------------------------------------------------------------
add_mcp_entry "blender" '{"type": "command", "command": "blender-mcp", "args": []}'

echo ""
echo "✓ Blender MCP configuration complete."
