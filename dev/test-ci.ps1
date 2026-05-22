$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = (Get-Item (Join-Path $scriptDir "..")).FullName

. (Join-Path $projectRoot "installers\lib\opencode-lib.ps1")

$errors = 0
$testsRun = 0

# Clean up any previous test output
$tmpDir = Join-Path $projectRoot "tmp" "windows"
if (Test-Path $tmpDir) {
    Remove-Item -Recurse -Force $tmpDir
}

# Iterate over all Windows installer scripts and run each in an isolated USERPROFILE
$installers = Get-ChildItem (Join-Path $projectRoot "installers\*\install-*-windows.ps1")
foreach ($installer in $installers) {
    $dirName = Split-Path $installer.Directory -Leaf
    $baseName = $installer.Name
    $testHome = Join-Path $tmpDir "${dirName}-test-home"
    $bundleDir = Join-Path $testHome "bundle"

    Write-Host ""
    Write-Host ("=" * 63)
    Write-Host "Testing: $dirName ($baseName)"
    Write-Host ("=" * 63)

    $bundles = Create-Bundle -Installer $installer.FullName -BundleDir $bundleDir
    $ps1Path = $bundles.Ps1Path

    $testsRun++

    # Run the bundle in an isolated user profile with a 5-minute timeout
    $oldUserProfile = $env:USERPROFILE
    $env:USERPROFILE = $testHome
    $oldHome = $env:HOME
    $env:HOME = $testHome
    $oldLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $testHome "AppData\Local"
    $oldPsModulePath = $env:PSModulePath
    $env:PSModulePath = "$testHome\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules"
    $oldCi = $env:OPENCODE_CI
    $env:OPENCODE_CI = "1"
    try {
        if ($IsWindows) {
            $process = [System.Diagnostics.Process]::Start("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File `"$ps1Path`"")
            if ($process.WaitForExit(300000)) {
                $exitCode = $process.ExitCode
            } else {
                $process.Kill()
                Write-Host "FAIL: $dirName installer timed out (300s)"
                $errors++
                continue
            }
        } else {
            & $ps1Path
            $exitCode = $LASTEXITCODE
        }
    } finally {
        $env:USERPROFILE = $oldUserProfile
        $env:HOME = $oldHome
        $env:LOCALAPPDATA = $oldLocalAppData
        $env:PSModulePath = $oldPsModulePath
        $env:OPENCODE_CI = $oldCi
    }

    if ($exitCode -ne 0) {
        Write-Host "FAIL: $dirName installer failed with exit code $exitCode"
        $errors++
        continue
    }
    Write-Host "✓ $dirName installer completed."

    # Verify the installer created an opencode.json
    $opencodeConfig = Join-Path $testHome ".config\opencode\opencode.json"
    if (!(Test-Path $opencodeConfig)) {
        Write-Host "FAIL: $dirName - opencode.json was not created"
        $errors++
        continue
    }

    # Verify the generated opencode.json is valid JSON
    try {
        $null = Get-Content $opencodeConfig -Raw | ConvertFrom-Json
        Write-Host "✓ $dirName - opencode.json is valid JSON"
    } catch {
        Write-Host "FAIL: $dirName - opencode.json contains invalid JSON"
        $errors++
        continue
    }
}

Write-Host ""
Write-Host ("=" * 63)
Write-Host "Results: $testsRun test(s) run, $errors failure(s)"
Write-Host ("=" * 63)

if ($errors -gt 0) {
    exit 1
}
