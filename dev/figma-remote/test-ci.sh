#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/../../installers/figma-remote/install-figma-remote-macos.sh"
TEST_HOME="/tmp/figma-remote-ci-test"

# ---------------------------------------------------------------------------
# Clean up from previous runs
# ---------------------------------------------------------------------------
rm -rf "$TEST_HOME"
mkdir -p "$TEST_HOME"

# ---------------------------------------------------------------------------
# Mock external dependencies
# ---------------------------------------------------------------------------
MOCK_DIR="$TEST_HOME/.mock"
mkdir -p "$MOCK_DIR"

# Create a mock opencode binary so installer skips Step 1 (installation)
cat > "$MOCK_DIR/opencode" << 'MOCKEOF'
#!/bin/bash
echo "mock opencode: auth for figma-remote"
exit 0
MOCKEOF
chmod +x "$MOCK_DIR/opencode"

# Create a mock curl that returns a valid Figma API registration response
cat > "$MOCK_DIR/curl" << 'MOCKEOF'
#!/bin/bash
# Forward non-figma requests to real curl
for arg; do
  if [[ "$arg" == *"api.figma.com"* ]]; then
    cat << 'RESP'
{"client_id": "ci_test_client_id", "client_secret": "ci_test_client_secret"}
RESP
    exit 0
  fi
done
# Fallback to real curl for everything else
exec /usr/bin/curl "$@"
MOCKEOF
chmod +x "$MOCK_DIR/curl"

export PATH="$MOCK_DIR:$PATH"
export HOME="$TEST_HOME"

# ---------------------------------------------------------------------------
# Run installer as the mock user
# ---------------------------------------------------------------------------
echo "Running installer in CI mode (home: $TEST_HOME)…"
echo "═══════════════════════════════════════════════════════════════════"
bash "$INSTALLER"
echo "═══════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
# Verify adjustments were successful
# ---------------------------------------------------------------------------
echo ""
echo "=== Verification ==="

ERRORS=0

OPENCODE_CONFIG="$TEST_HOME/.config/opencode/opencode.json"
if [ ! -f "$OPENCODE_CONFIG" ]; then
    echo "FAIL: opencode.json was not created"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ opencode.json exists"

    if python3 -c "import json; json.load(open('$OPENCODE_CONFIG'))" 2>/dev/null; then
        echo "✓ opencode.json is valid JSON"
    else
        echo "FAIL: opencode.json contains invalid JSON"
        ERRORS=$((ERRORS + 1))
    fi

    if python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    config = json.load(f)
fr = config.get('mcp', {}).get('figma-remote', {})
assert fr.get('type') == 'remote', 'type mismatch'
assert fr.get('url') == 'https://mcp.figma.com/mcp', 'url mismatch'
assert fr.get('enabled') == True, 'enabled should be True'
assert 'oauth' in fr, 'oauth missing'
assert fr['oauth'].get('clientId') == 'ci_test_client_id', 'clientId mismatch'
assert fr['oauth'].get('clientSecret') == 'ci_test_client_secret', 'clientSecret mismatch'
print('✓ figma-remote configuration is correct')
"; then
        :
    else
        echo "FAIL: figma-remote config verification failed"
        ERRORS=$((ERRORS + 1))
    fi
fi

MCP_AUTH="$TEST_HOME/.local/share/opencode/mcp-auth.json"
if [ -f "$MCP_AUTH" ]; then
    if python3 -c "
import json
with open('$MCP_AUTH') as f:
    auth = json.load(f)
figma_keys = [k for k in auth if 'figma' in k.lower()]
assert len(figma_keys) == 0, f'figma keys remaining: {figma_keys}'
print('✓ mcp-auth.json is clean of figma entries')
"; then
        :
    else
        echo "FAIL: mcp-auth.json still contains figma entries"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "✓ mcp-auth.json not present (no cleanup needed)"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== All checks passed! ==="
else
    echo "=== $ERRORS check(s) failed! ==="
    exit 1
fi
