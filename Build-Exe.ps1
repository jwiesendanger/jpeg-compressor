# Build-Exe.ps1
# Compiles jpeg-compress.ps1 into a standalone Windows executable using PS2EXE.
# Run this once after cloning, or whenever jpeg-compress.ps1 changes.

# Self-relaunch with ExecutionPolicy Bypass if needed
if ($ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage' -or
    (Get-ExecutionPolicy) -notin @('Bypass','Unrestricted','RemoteSigned')) {
    Write-Host "Relaunching with ExecutionPolicy Bypass..." -ForegroundColor Cyan
    $args = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -ArgumentList $args -Wait -NoNewWindow
    exit
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe -Force

$inputFile  = Join-Path $PSScriptRoot "jpeg-compress.ps1"
$outputFile = Join-Path $PSScriptRoot "jpeg-compress.exe"

Invoke-ps2exe `
    -inputFile   $inputFile `
    -outputFile  $outputFile `
    -noConsole `
    -title       "JPEG Compressor" `
    -description "Compress a JPEG to a target file size" `
    -company     "jwiesendanger" `
    -version     "1.0.0"

if (Test-Path $outputFile) {
    Write-Host "Built successfully: $outputFile" -ForegroundColor Green
    Write-Host "Run .\Create-Shortcut.ps1 to update your desktop shortcut to use the exe."
} else {
    Write-Error "Build failed - exe not found at expected path."
}
