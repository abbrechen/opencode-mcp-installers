#!/bin/bash
# Version: 1.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/opencode-lib.sh"

# Path to the OpenCode MCP auth store (cleaned in step 7)
MCP_AUTH="$HOME/.local/share/opencode/mcp-auth.json"

# ---------------------------------------------------------------------------
# Step 1: Ensure OpenCode is installed
# ---------------------------------------------------------------------------
ensure_opencode_installed

# ---------------------------------------------------------------------------
# Step 2: Ensure opencode.json exists and is valid
# ---------------------------------------------------------------------------
ensure_opencode_config

# ---------------------------------------------------------------------------
# Step 3: Bail if figma-remote is already configured
# ---------------------------------------------------------------------------
ensure_mcp_not_configured "figma-remote"

# ---------------------------------------------------------------------------
# Step 4: Register an OAuth client with the Figma API
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
# Step 5: Extract client_id and client_secret from the JSON response
# ---------------------------------------------------------------------------
CLIENT_ID=$(echo "$FIGMA_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('client_id', ''))
except json.JSONDecodeError:
    print('', end='')
")

CLIENT_SECRET=$(echo "$FIGMA_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('client_secret', ''))
except json.JSONDecodeError:
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
# Step 6: Add figma-remote as a remote MCP entry with OAuth config
# ---------------------------------------------------------------------------
MCP_ENTRY=$(python3 -c "
import json
print(json.dumps({
    'type': 'remote',
    'url': 'https://mcp.figma.com/mcp',
    'enabled': True,
    'oauth': {
        'clientId': '$CLIENT_ID',
        'clientSecret': '$CLIENT_SECRET'
    }
}))
")
add_mcp_entry "figma-remote" "$MCP_ENTRY"

# ---------------------------------------------------------------------------
# Step 7: Remove stale figma entries from mcp-auth.json
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
# Step 8: Run the OpenCode MCP OAuth auth flow (opens a browser)
# ---------------------------------------------------------------------------
if [ -n "${OPENCODE_CI:-}" ]; then
    echo "ℹ OPENCODE_CI is set – skipping OAuth flow."
else
    echo "Launching 'opencode mcp auth figma-remote' (this may open a browser)…"
    opencode mcp auth figma-remote
fi

echo "✓ Figma remote MCP configuration complete."
