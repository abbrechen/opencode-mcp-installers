#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

source "$PROJECT_ROOT/installers/lib/opencode-lib.sh"

ERRORS=0
TESTS_RUN=0

rm -rf "$PROJECT_ROOT/tmp/"

for installer in "$PROJECT_ROOT"/installers/*/install-*.sh; do
    if [ ! -f "$installer" ]; then
        continue
    fi

    dir_name="$(basename "$(dirname "$installer")")"
    base_name="$(basename "$installer")"
    test_home="$PROJECT_ROOT/tmp/${dir_name}-test-home"
    bundle_dir="$test_home/bundle"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Testing: $dir_name ($base_name)"
    echo "═══════════════════════════════════════════════════════════════════"

    command_path="$(create_bundle "$installer" "$bundle_dir")"

    TESTS_RUN=$((TESTS_RUN + 1))

    set +e
    HOME="$test_home" bash "$command_path"
    EXIT_CODE=$?
    set -e

    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "FAIL: $dir_name installer failed with exit code $EXIT_CODE"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    echo "✓ $dir_name installer completed."

    opencode_config="$test_home/.config/opencode/opencode.json"
    if [ ! -f "$opencode_config" ]; then
        echo "FAIL: $dir_name - opencode.json was not created"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if python3 -c "import json; json.load(open('$opencode_config'))" 2>/dev/null; then
        echo "✓ $dir_name - opencode.json is valid JSON"
    else
        echo "FAIL: $dir_name - opencode.json contains invalid JSON"
        ERRORS=$((ERRORS + 1))
        continue
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "Results: $TESTS_RUN test(s) run, $ERRORS failure(s)"
echo "═══════════════════════════════════════════════════════════════════"

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
