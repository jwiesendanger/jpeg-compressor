# Create-Shortcut.ps1
# Run this once to install the JPEG Compressor desktop shortcut.
# Prefers jpeg-compress.exe if built; falls back to jpeg-compress.ps1.

$exePath    = Join-Path $PSScriptRoot "jpeg-compress.exe"
$scriptPath = Join-Path $PSScriptRoot "jpeg-compress.ps1"

if (-not (Test-Path $exePath) -and -not (Test-Path $scriptPath)) {
    Write-Error "Neither jpeg-compress.exe nor jpeg-compress.ps1 found in $PSScriptRoot"
    exit 1
}

$wsh          = New-Object -ComObject WScript.Shell
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "JPEG Compressor.lnk"
$shortcut     = $wsh.CreateShortcut($shortcutPath)

if (Test-Path $exePath) {
    $shortcut.TargetPath = $exePath
    $shortcut.Arguments  = ""
    $mode = "exe"
} else {
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments  = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $mode = "ps1"
}

$shortcut.Description      = "Compress a JPEG to a target file size"
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Save()

Write-Host "Shortcut created at: $shortcutPath ($mode)" -ForegroundColor Green
Write-Host "Double-click 'JPEG Compressor' on your desktop to launch."
