OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

ensure_opencode_installed() {
    if ! command -v opencode &>/dev/null; then
        echo "OpenCode is not installed. Installing now…"
        curl -fsSL https://opencode.ai/install | bash
        export PATH="$HOME/.opencode/bin:$PATH"
        if ! command -v opencode &>/dev/null; then
            echo "Error: OpenCode installation completed but 'opencode' not found." >&2
            exit 1
        fi
        add_to_shell_config "opencode" ".opencode/bin" '$HOME/.opencode/bin:$PATH'
    fi
    echo "✓ OpenCode is installed."
}

ensure_opencode_config() {
    echo "Validating OpenCode setup…"
    local config_dir
    config_dir="$(dirname "$OPENCODE_CONFIG")"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
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
}

ensure_mcp_not_configured() {
    local key="$1"
    if [ -f "$OPENCODE_CONFIG" ]; then
        if python3 -c "
import json, sys
with open('$OPENCODE_CONFIG') as f:
    config = json.load(f)
if 'mcp' in config and '$key' in config['mcp']:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
            echo "Error: '$key' is already configured in opencode.json." >&2
            echo "Remove it manually or run a fresh install on a clean config." >&2
            exit 1
        fi
    fi
}

add_to_shell_config() {
    local tool_name="$1"
    local grep_path="$2"
    local export_path="$3"

    local shell_config=""
    if [ -n "${ZDOTDIR:-}" ] && [ -f "$ZDOTDIR/.zshrc" ]; then
        shell_config="$ZDOTDIR/.zshrc"
    elif [ -f "$HOME/.zshrc" ]; then
        shell_config="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_config="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_config="$HOME/.bash_profile"
    fi

    if [ -z "$shell_config" ]; then
        shell_config="$HOME/.zshrc"
    fi

    if ! grep -qF "$grep_path" "$shell_config" 2>/dev/null; then
        {
            echo ""
            echo "# $tool_name"
            echo "export PATH=\"$export_path\""
        } >> "$shell_config"
        echo "✓ Added $tool_name to \$PATH in $shell_config"
    fi
}

add_mcp_entry() {
    local key="$1"
    local json_payload="$2"

    echo "Updating opencode.json…"
    KEY="$key" JSON_PAYLOAD="$json_payload" python3 << 'PYEOF'
import json, os

key = os.environ['KEY']
json_payload = os.environ['JSON_PAYLOAD']
config_path = os.environ['HOME'] + '/.config/opencode/opencode.json'

config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

if 'mcp' not in config or config['mcp'] is None:
    config['mcp'] = {}

config['mcp'][key] = json.loads(json_payload)

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print(f"✓ Added {key} to opencode.json.")
PYEOF
}

create_bundle() {
    local installer="$1"
    local bundle_dir="$2"
    local dir_name
    dir_name="$(basename "$(dirname "$installer")")"
    local base_name
    base_name="$(basename "$installer")"
    local name_no_ext="${base_name%.*}"

    mkdir -p "$bundle_dir/$dir_name"
    cp "$installer" "$bundle_dir/$dir_name/${name_no_ext}.command"
    chmod +x "$bundle_dir/$dir_name/${name_no_ext}.command"

    local lib_dir
    lib_dir="$(dirname "$(dirname "$installer")")/lib"
    [ -d "$lib_dir" ] && cp -r "$lib_dir" "$bundle_dir/"

    echo "$bundle_dir/$dir_name/${name_no_ext}.command"
}
