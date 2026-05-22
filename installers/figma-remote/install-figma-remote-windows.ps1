# Version: 1.0
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\lib\opencode-lib.ps1"

$mcpAuthPath = "$env:USERPROFILE\.local\share\opencode\mcp-auth.json"

# Step 1: Ensure OpenCode is installed
Ensure-OpenCodeInstalled

# Step 2: Ensure opencode.json exists and is valid
Ensure-OpenCodeConfig

# Step 3: Bail if figma-remote is already configured
Ensure-McpNotConfigured "figma-remote"

# Step 4: Register an OAuth client with the Figma API
Write-Host "Registering Figma OAuth MCP client..."
$body = @{
    client_name              = "Claude Code (figma)"
    redirect_uris            = @("http://127.0.0.1:19876/mcp/oauth/callback")
    grant_types              = @("authorization_code", "refresh_token")
    response_types           = @("code")
    token_endpoint_auth_method = "none"
} | ConvertTo-Json

try {
    $figmaResponse = Invoke-RestMethod -Uri "https://api.figma.com/v1/oauth/mcp/register" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body
} catch {
    Write-Error "Failed to register with Figma API: $_"
    exit 1
}

# Step 5: Extract client_id and client_secret
$clientId = $figmaResponse.client_id
$clientSecret = $figmaResponse.client_secret

if ([string]::IsNullOrEmpty($clientId) -or [string]::IsNullOrEmpty($clientSecret)) {
    Write-Error "Failed to extract client credentials from Figma response."
    exit 1
}
Write-Host "✓ Got client credentials (ID: $($clientId.Substring(0, [Math]::Min(8, $clientId.Length)))…)."

# Step 6: Add figma-remote as a remote MCP entry with OAuth config
$mcpEntry = @{
    type    = "remote"
    url     = "https://mcp.figma.com/mcp"
    enabled = $true
    oauth   = @{
        clientId     = $clientId
        clientSecret = $clientSecret
    }
} | ConvertTo-Json -Compress

Add-McpEntry "figma-remote" $mcpEntry

# Step 7: Remove stale figma entries from mcp-auth.json
if (Test-Path $mcpAuthPath) {
    $auth = Get-Content $mcpAuthPath -Raw | ConvertFrom-Json -AsHashtable
    $keysToRemove = @($auth.Keys | Where-Object { $_ -like "*figma*" })
    foreach ($k in $keysToRemove) {
        $auth.Remove($k)
    }
    if ($keysToRemove.Count -gt 0) {
        $auth | ConvertTo-Json -Depth 10 | Set-Content $mcpAuthPath
        Write-Host "✓ Cleaned figma entries ($($keysToRemove -join ', ')) from mcp-auth.json."
    }
} else {
    Write-Host "ℹ mcp-auth.json not found – skipping cleanup."
}

# Step 8: Run the OpenCode MCP OAuth auth flow (opens a browser)
Write-Host "Launching 'opencode mcp auth figma-remote' (this may open a browser)…"
opencode mcp auth figma-remote

Write-Host "✓ Figma remote MCP configuration complete."
