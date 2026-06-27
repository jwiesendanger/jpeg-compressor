# Create-Shortcut.ps1
# Run this once to install the JPEG Compressor desktop shortcut.
# The shortcut launches jpeg-compress.ps1 directly — no terminal window appears.

$scriptPath   = Join-Path $PSScriptRoot "jpeg-compress.ps1"
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "JPEG Compressor.lnk"

if (-not (Test-Path $scriptPath)) {
    Write-Error "jpeg-compress.ps1 not found at: $scriptPath"
    exit 1
}

$wsh               = New-Object -ComObject WScript.Shell
$shortcut          = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath      = "powershell.exe"
$shortcut.Arguments       = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$shortcut.Description     = "Compress a JPEG to a target file size"
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Save()

Write-Host "Shortcut created at: $shortcutPath" -ForegroundColor Green
Write-Host "Double-click 'JPEG Compressor' on your desktop to launch."
