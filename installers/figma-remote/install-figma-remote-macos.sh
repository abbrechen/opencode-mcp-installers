#!/bin/bash
set -euo pipefail

OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
MCP_AUTH="$HOME/.local/share/opencode/mcp-auth.json"

# ---------------------------------------------------------------------------
# Step 1: Check if OpenCode is installed; auto-install if missing
# ---------------------------------------------------------------------------
if ! command -v opencode &>/dev/null; then
    echo "OpenCode is not installed. Installing now…"
    curl -fsSL https://opencode.ai/install | bash

    # The installer places the binary at ~/.opencode/bin/opencode
    # but on macOS it often can't find a shell config file to
    # permanently add PATH (no pre-created .zshrc/.bashrc).
    # Fix that here so future terminals find opencode too.
    export PATH="$HOME/.opencode/bin:$PATH"

    if ! command -v opencode &>/dev/null; then
        echo "Error: OpenCode installation completed but 'opencode' not found." >&2
        exit 1
    fi

    # Permanently add opencode to PATH if the installer didn't
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
        # No config file exists — create .zshrc (default on macOS, common on Linux)
        SHELL_CONFIG="$HOME/.zshrc"
    fi

    if ! grep -q '.opencode/bin' "$SHELL_CONFIG" 2>/dev/null; then
        echo >> "$SHELL_CONFIG"
        echo '# opencode' >> "$SHELL_CONFIG"
        echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> "$SHELL_CONFIG"
        echo "✓ Added opencode to \$PATH in $SHELL_CONFIG"
    fi
fi
echo "✓ OpenCode is installed."

# ---------------------------------------------------------------------------
# Step 1.1: Ensure config directory and opencode.json exist
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
# Step 1.5: Bail if figma-remote is already configured
# ---------------------------------------------------------------------------
if [ -f "$OPENCODE_CONFIG" ]; then
    if python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    config = json.load(f)
if 'mcp' in config and 'figma-remote' in config['mcp']:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        echo "Error: figma-remote is already configured in opencode.json." >&2
        echo "Remove it manually or run a fresh install on a clean config." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 2: Register Figma OAuth MCP client
# ---------------------------------------------------------------------------
echo "Registering Figma OAuth MCP client..."
FIGMA_RESPONSE=$(curl -s -X POST https://api.figma.com/v1/oauth/mcp/register \
    -H "Content-Type: application/json" \
    -d '{
        "client_name": "Claude Code (figma)",
        "redirect_uris": ["http://127.0.0.1:19876/mcp/oauth/callback"],
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none"
    }')

if [ -z "$FIGMA_RESPONSE" ]; then
    echo "Error: Empty response from Figma API (check your network)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Extract client_id and client_secret (snake_case from API)
#         → map to clientId / clientSecret (camelCase for opencode.json)
# ---------------------------------------------------------------------------
CLIENT_ID=$(echo "$FIGMA_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('client_id', ''))
except json.JSONDecodeError as e:
    print('', end='')
")

CLIENT_SECRET=$(echo "$FIGMA_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('client_secret', ''))
except json.JSONDecodeError as e:
    print('', end='')
")

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Error: Failed to extract client credentials from Figma response." >&2
    echo "Response was:" >&2
    echo "$FIGMA_RESPONSE" >&2
    exit 1
fi
echo "✓ Got client credentials (ID: ${CLIENT_ID:0:8}…)."

# ---------------------------------------------------------------------------
# Step 4: Add (or merge) figma-remote into opencode.json
# ---------------------------------------------------------------------------
echo "Updating opencode.json…"
CLIENT_ID="$CLIENT_ID" CLIENT_SECRET="$CLIENT_SECRET" python3 << 'PYEOF'
import json, os

client_id = os.environ['CLIENT_ID']
client_secret = os.environ['CLIENT_SECRET']
config_path = os.environ['HOME'] + '/.config/opencode/opencode.json'

# Load existing config or start fresh
config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

# Ensure the 'mcp' key exists (preserving everything else)
if 'mcp' not in config or config['mcp'] is None:
    config['mcp'] = {}

# Add / overwrite the figma-remote entry
config['mcp']['figma-remote'] = {
    "type": "remote",
    "url": "https://mcp.figma.com/mcp",
    "enabled": True,
    "oauth": {
        "clientId": client_id,
        "clientSecret": client_secret
    }
}

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')
PYEOF
echo "✓ Added figma-remote to opencode.json."

# ---------------------------------------------------------------------------
# Step 5: Remove any figma‑related entries from mcp-auth.json
# ---------------------------------------------------------------------------
if [ -f "$MCP_AUTH" ]; then
    python3 << 'PYEOF'
import json, os

auth_path = os.environ['HOME'] + '/.local/share/opencode/mcp-auth.json'

if not os.path.exists(auth_path):
    exit(0)

with open(auth_path) as f:
    auth = json.load(f)

keys_to_remove = [k for k in auth if 'figma' in k.lower()]
for k in keys_to_remove:
    del auth[k]

with open(auth_path, 'w') as f:
    json.dump(auth, f, indent=2)
    f.write('\n')

if keys_to_remove:
    print('Removed entries:', keys_to_remove)
PYEOF
    echo "✓ Cleaned figma entries from mcp-auth.json."
else
    echo "ℹ mcp-auth.json not found – skipping cleanup."
fi

# ---------------------------------------------------------------------------
# Step 6: Run opencode MCP auth flow
# ---------------------------------------------------------------------------
echo "Launching 'opencode mcp auth figma-remote' (this may open a browser)…"
opencode mcp auth figma-remote

echo "✓ Figma remote MCP configuration complete."
