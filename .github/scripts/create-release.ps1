param(
    [string]$Tag,
    [string]$Repo,
    [string]$Token
)

$auth = "Bearer $Token"
$base = "https://api.github.com/repos/$Repo"
$hdrs = @{ Authorization = $auth; Accept = "application/json" }

# Delete existing release if present (404 = none exists, which is fine)
$existing = $null
try {
    $existing = Invoke-RestMethod "$base/releases/tags/$Tag" -Headers $hdrs -ErrorAction Stop
} catch {
    Write-Host "No existing release found for $Tag (will create fresh)"
}
if ($existing) {
    Invoke-RestMethod "$base/releases/$($existing.id)" -Method Delete -Headers $hdrs | Out-Null
    Write-Host "Deleted existing release $($existing.id)"
}

# Create release
$body    = @{ tag_name = $Tag; name = "JPEG Compressor $Tag"; body = "Download jpeg-compress.exe below. Requires Windows 10 or 11." } | ConvertTo-Json
$release = Invoke-RestMethod "$base/releases" -Method Post -Headers $hdrs -Body $body -ContentType "application/json"
Write-Host "Created release: $($release.html_url)"

# Upload exe
$exePath  = Join-Path $PSScriptRoot "..\..\jpeg-compress.exe"
$exeBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $exePath))
$url      = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=jpeg-compress.exe"
$asset    = Invoke-RestMethod $url -Method Post -Headers @{ Authorization = $auth } -Body $exeBytes -ContentType "application/octet-stream"
Write-Host "Asset ready: $($asset.browser_download_url)"
