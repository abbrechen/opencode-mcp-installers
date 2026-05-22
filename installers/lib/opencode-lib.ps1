# Path to the OpenCode config file
$global:OpenCodeConfig = "$env:USERPROFILE\.config\opencode\opencode.json"

# Check if OpenCode is installed; install it if missing
function Ensure-OpenCodeInstalled {
    if (!(Get-Command opencode -ErrorAction SilentlyContinue)) {
        Write-Host "OpenCode is not installed. Installing now..."
        $installerPath = Join-Path $env:TEMP "opencode-install.ps1"
        Invoke-WebRequest -Uri https://opencode.ai/install -UseBasicParsing -OutFile $installerPath
        . $installerPath
        $env:Path += ";$env:USERPROFILE\.opencode\bin"
        if (!(Get-Command opencode -ErrorAction SilentlyContinue)) {
            Write-Error "OpenCode installation completed but 'opencode' not found."
            exit 1
        }
        Add-ToShellConfig "opencode" ".opencode\bin" "$env:USERPROFILE\.opencode\bin"
    }
    Write-Host "✓ OpenCode is installed."
}

# Ensure opencode.json exists and contains valid JSON
function Ensure-OpenCodeConfig {
    Write-Host "Validating OpenCode setup..."
    $configDir = Split-Path $global:OpenCodeConfig -Parent
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    if (!(Test-Path $global:OpenCodeConfig)) {
        "{}" | Set-Content $global:OpenCodeConfig
        Write-Host "ℹ Created empty opencode.json."
    }
    try {
        $null = Get-Content $global:OpenCodeConfig -Raw | ConvertFrom-Json
    } catch {
        Write-Error "opencode.json contains invalid JSON."
        exit 1
    }
    Write-Host "✓ OpenCode setup is valid."
}

# Bail out if the given MCP key is already configured in opencode.json
function Ensure-McpNotConfigured {
    param($Key)
    if (Test-Path $global:OpenCodeConfig) {
        $content = Get-Content $global:OpenCodeConfig -Raw | ConvertFrom-Json
        $keys = @($content.mcp.PSObject.Properties.Name)
        if ($Key -in $keys) {
            Write-Error "'$Key' is already configured in opencode.json."
            Write-Host "Remove it manually or run a fresh install on a clean config."
            exit 1
        }
    }
}

# Add a directory to the user's PATH environment variable
function Add-ToShellConfig {
    param($ToolName, $GrepPath, $ExportPath)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$GrepPath*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$ExportPath", "User")
        Write-Host "✓ Added $ToolName to user PATH"
    }
}

# Recursively convert a PSObject to a hashtable (PS5.1-compatible)
function ConvertTo-Hashtable {
    param($InputObject)
    if ($InputObject -is [PSCustomObject]) {
        $ht = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $ht[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $ht
    } elseif ($InputObject -is [System.Collections.IList]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-Hashtable $item
        }
        return @($list)
    } elseif ($InputObject -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $InputObject.Keys) {
            $ht[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $ht
    }
    return $InputObject
}

# Add an MCP server entry to opencode.json
function Add-McpEntry {
    param($Key, $JsonPayload)
    Write-Host "Updating opencode.json..."
    $configPath = $global:OpenCodeConfig
    $config = @{}
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw
        $config = if ($raw) { ConvertTo-Hashtable ($raw | ConvertFrom-Json) } else { @{} }
    }
    if (!$config.ContainsKey('mcp') -or $null -eq $config.mcp) {
        $config.mcp = @{}
    }
    $config.mcp[$Key] = ConvertTo-Hashtable ($JsonPayload | ConvertFrom-Json)
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "✓ Added $Key to opencode.json."
}

# Extract version from an installer script's # Version: header
function Get-Version {
    param($InstallerPath)
    $line = Select-String -Path $InstallerPath -Pattern '^# Version:\s*(.+)$' | Select-Object -First 1
    if ($line) {
        return $line.Matches.Groups[1].Value.Trim()
    }
    return "0.0"
}

# Build a self-contained .ps1 bundle with a .bat wrapper from an installer script.
# The shared library (opencode-lib.ps1) is inlined so the bundle has no external dependencies.
function Create-Bundle {
    param(
        [string]$Installer,
        [string]$BundleDir
    )
    $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($Installer) -replace '-windows', '-mcp-windows'
    $libPath = Join-Path (Split-Path $Installer -Parent) "..\lib\opencode-lib.ps1"

    New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null

    $installerContent = Get-Content $Installer -Raw
    $libContent = Get-Content $libPath -Raw

    # Replace dot-source of the library with the inlined content
    $inlinedHeader = "# --- begin opencode-lib.ps1 (inlined) ---"
    $inlinedFooter = "# --- end opencode-lib.ps1 (inlined) ---"
    $bundleContent = $installerContent.Replace('. "$scriptDir\..\lib\opencode-lib.ps1"', "$inlinedHeader`r`n$libContent`r`n$inlinedFooter")

    $ps1Path = Join-Path $BundleDir "$nameNoExt.ps1"
    $bundleContent | Set-Content -Path $ps1Path -Encoding Unicode

    # Create .bat wrapper for double-click execution
    $batPath = Join-Path $BundleDir "$nameNoExt.bat"
@"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0$nameNoExt.ps1"
pause
"@ | Set-Content $batPath -Encoding ASCII

    return @{ Ps1Path = $ps1Path; BatPath = $batPath }
}
