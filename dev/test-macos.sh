#!/bin/bash
set -euo pipefail

TEST_USER="figmatest"
TEST_PASS="test123"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/install-figma-remote.sh"
TEST_HOME="/tmp/figma-remote-test-home"

# ---------------------------------------------------------------------------
# Create temporary user with home in /tmp (world-traversable)
# ---------------------------------------------------------------------------
echo "Creating temporary user '$TEST_USER'…"
mkdir -p "$TEST_HOME"
sudo sysadminctl -addUser "$TEST_USER" -fullName "Figma Test" \
    -password "$TEST_PASS" -home "$TEST_HOME" 2>/dev/null
sudo chown "$TEST_USER" "$TEST_HOME"

echo "✓ User '$TEST_USER' created (home: $TEST_HOME)."

# ---------------------------------------------------------------------------
# Run installer as the temporary user
# ---------------------------------------------------------------------------
echo ""
# Copy installer to /tmp (world-traversable — test user can reach it)
cp "$INSTALLER" /tmp/install-figma-remote.sh
chmod 755 /tmp/install-figma-remote.sh
echo "Running installer as '$TEST_USER'…"
echo "═══════════════════════════════════════════════════════════════════"
sudo -u "$TEST_USER" -i /bin/bash /tmp/install-figma-remote.sh
echo "═══════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
# Wait for manual inspection
# ---------------------------------------------------------------------------
echo ""
echo "Installer finished. The temporary user '$TEST_USER' is still present."
echo "All config is in $TEST_HOME"
echo ""
read -p "Press Enter to delete the temporary user and clean up…"

# ---------------------------------------------------------------------------
# Delete temporary user and project test-home
# ---------------------------------------------------------------------------
echo "Deleting temporary user '$TEST_USER'…"
sudo sysadminctl -deleteUser "$TEST_USER" 2>/dev/null || true
sudo rm -rf "$TEST_HOME"
echo "✓ User '$TEST_USER' removed and $TEST_HOME cleaned up."
