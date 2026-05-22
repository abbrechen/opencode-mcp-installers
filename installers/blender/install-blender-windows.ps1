# Version: 1.0
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\lib\opencode-lib.ps1"

# Step 1: Install uv (Python package manager) if not already present
if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "uv is not installed. Installing now..."
    $installScript = Invoke-WebRequest -Uri https://astral.sh/uv/install.ps1 -UseBasicParsing
    Invoke-Expression $installScript.Content
    $env:Path += ";$env:USERPROFILE\.local\bin"
    if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Error "uv installation failed – 'uv' not found after install."
        exit 1
    }
    Add-ToShellConfig "uv" ".local\bin" "$env:USERPROFILE\.local\bin"
}
Write-Host "✓ uv is installed."

# Step 2: Install the blender-mcp package via uv
Write-Host "Installing blender-mcp package via uv..."
uv tool install blender-mcp
Write-Host "✓ blender-mcp installed."

# Step 3: Ensure opencode.json exists and is valid
Ensure-OpenCodeConfig

# Step 4: Bail if blender is already configured
Ensure-McpNotConfigured "blender"

# Step 5: Register blender as a command-type MCP server
Add-McpEntry "blender" '{"type": "command", "command": "blender-mcp", "args": []}'

Write-Host ""
Write-Host "✓ Blender MCP configuration complete."
