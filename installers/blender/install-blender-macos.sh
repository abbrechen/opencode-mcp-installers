#!/bin/bash
set -euo pipefail

OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

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

    # Persist uv in PATH
    SHELL_CONFIG=""
    if [ -n "${ZDOTDIR:-}" ] && [ -f "$ZDOTDIR/.zshrc" ]; then
        SHELL_CONFIG="$ZDOTDIR/.zshrc"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    fi

    if [ -z "$SHELL_CONFIG" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    fi

    if ! grep -q '.local/bin' "$SHELL_CONFIG" 2>/dev/null; then
        echo >> "$SHELL_CONFIG"
        echo '# uv' >> "$SHELL_CONFIG"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_CONFIG"
        echo "✓ Added uv to \$PATH in $SHELL_CONFIG"
    fi
fi
echo "✓ uv is installed."

# ---------------------------------------------------------------------------
# Step 2: Install blender-mcp via uv
# ---------------------------------------------------------------------------
echo "Installing blender-mcp package via uv…"
uv tool install blender-mcp
echo "✓ blender-mcp installed."

# ---------------------------------------------------------------------------
# Step 3: Ensure config directory and opencode.json exist
# ---------------------------------------------------------------------------
echo "Validating OpenCode setup…"

CONFIG_DIR="$(dirname "$OPENCODE_CONFIG")"
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
fi

if [ ! -f "$OPENCODE_CONFIG" ]; then
    echo "{}" > "$OPENCODE_CONFIG"
    echo "ℹ Created empty opencode.json."
fi

if ! python3 -c "import json; json.load(open('$OPENCODE_CONFIG'))" 2>/dev/null; then
    echo "Error: opencode.json contains invalid JSON." >&2
    exit 1
fi

echo "✓ OpenCode setup is valid."

# ---------------------------------------------------------------------------
# Step 4: Bail if blender is already configured
# ---------------------------------------------------------------------------
if [ -f "$OPENCODE_CONFIG" ]; then
    if python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    config = json.load(f)
if 'mcp' in config and 'blender' in config['mcp']:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "Error: blender is already configured in opencode.json." >&2
        echo "Remove it manually or run a fresh install on a clean config." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Add blender MCP server to opencode.json
# ---------------------------------------------------------------------------
echo "Updating opencode.json with blender MCP server…"
python3 << 'PYEOF'
import json, os

config_path = os.environ['HOME'] + '/.config/opencode/opencode.json'

# Load existing config or start fresh
config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

# Ensure the 'mcp' key exists
if 'mcp' not in config or config['mcp'] is None:
    config['mcp'] = {}

# Add / overwrite the blender entry
config['mcp']['blender'] = {
    "type": "command",
    "command": "blender-mcp",
    "args": []
}

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print("✓ Added blender MCP server to opencode.json.")
PYEOF

echo ""
echo "✓ Blender MCP configuration complete."
