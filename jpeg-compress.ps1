# jpeg-compress.ps1
# JPEG File Size Compressor
# Compresses a JPEG to a user-specified target file size.
# Phase 1: binary-search quality at full resolution.
# Phase 2 (if needed): binary-search dimensions, then maximize quality at that scale.
# Launch via the desktop shortcut created by Create-Shortcut.ps1

#Requires -Version 5.1

# Top-level error handler: any unhandled exception shows a MessageBox instead of crashing silently
trap {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "Unexpected error:`n`n$($_.Exception.Message)`n`nAt: $($_.InvocationInfo.PositionMessage)",
            "JPEG Compressor Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch {
        $log = Join-Path ([Environment]::GetFolderPath("Desktop")) "jpeg-compressor-error.txt"
        $_.Exception.Message | Out-File $log -Encoding UTF8
    }
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Find the JPEG codec once; reuse for every compression call
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' } |
    Select-Object -First 1

if (-not $jpegCodec) {
    [System.Windows.Forms.MessageBox]::Show(
        "JPEG codec not found on this system.",
        "JPEG Compressor", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# Compress and optionally scale an image; returns byte array
# scale: 1.0 = original size, 0.5 = half dimensions
function Compress-Jpeg([string]$path, [int]$quality, [double]$scale = 1.0) {
    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality, [long]$quality)

    $src = [System.Drawing.Image]::FromFile($path)
    $ms  = New-Object System.IO.MemoryStream
    try {
        if ($scale -lt 1.0) {
            $newW = [Math]::Max(1, [int]($src.Width  * $scale))
            $newH = [Math]::Max(1, [int]($src.Height * $scale))
            $bmp  = New-Object System.Drawing.Bitmap($newW, $newH)
            $g    = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($src, 0, 0, $newW, $newH)
            $g.Dispose()
            $bmp.Save($ms, $jpegCodec, $ep)
            $bmp.Dispose()
        } else {
            $src.Save($ms, $jpegCodec, $ep)
        }
        return , $ms.ToArray()
    } finally {
        $src.Dispose()
        $ms.Dispose()
    }
}

# Format byte count as human-readable string
function Format-Bytes([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:N3} MB ({1:N0} KB)" -f ($bytes / 1MB), ($bytes / 1KB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

# Input dialog with auto-sizing label
function Show-InputDialog([string]$prompt, [string]$title) {
    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = $title
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false

    $lbl             = New-Object System.Windows.Forms.Label
    $lbl.Text        = $prompt
    $lbl.AutoSize    = $false
    $lbl.MaximumSize = New-Object System.Drawing.Size(344, 0)
    $lbl.AutoSize    = $true
    $lbl.Location    = New-Object System.Drawing.Point(12, 18)

    $form.Controls.Add($lbl)
    $form.PerformLayout()

    $txtTop = $lbl.Bottom + 8
    $txt          = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(12, $txtTop)
    $txt.Size     = New-Object System.Drawing.Size(344, 24)

    $btnTop = $txt.Bottom + 10

    $btnOK              = New-Object System.Windows.Forms.Button
    $btnOK.Text         = "OK"
    $btnOK.Location     = New-Object System.Drawing.Point(12, $btnTop)
    $btnOK.Size         = New-Object System.Drawing.Size(80, 28)
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton  = $btnOK

    $btnCancel              = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = "Cancel"
    $btnCancel.Location     = New-Object System.Drawing.Point(100, $btnTop)
    $btnCancel.Size         = New-Object System.Drawing.Size(80, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton      = $btnCancel

    $form.Controls.AddRange(@($txt, $btnOK, $btnCancel))
    $form.ClientSize    = New-Object System.Drawing.Size(368, ($btnTop + 28 + 16))
    $form.ActiveControl = $txt

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text.Trim() }
    return $null
}

# Parse "500 KB" / "1.5 MB" / "500" into bytes
function Parse-TargetSize([string]$raw) {
    if ($raw -match '^([\d.]+)\s*(KB|MB)?$') {
        $num  = [double]$Matches[1]
        $unit = if ($Matches[2]) { $Matches[2].ToUpper() } else { 'KB' }
        if ($unit -eq 'MB') { return [long]($num * 1MB) }
        return [long]($num * 1KB)
    }
    return $null
}

# Binary-search quality within [minQ, maxQ] at a given scale; returns hashtable with Data, Size, Quality
function Find-BestQuality([string]$path, [double]$scale, [long]$targetBytes, [int]$minQ = 1, [int]$maxQ = 100) {
    $lo = $minQ; $hi = $maxQ
    $bestData = $null; $bestSize = 0; $bestQuality = 0
    while ($lo -le $hi) {
        $mid  = [int](($lo + $hi) / 2)
        $data = Compress-Jpeg $path $mid $scale
        $size = $data.Length
        if ($size -le $targetBytes) {
            $bestData = $data; $bestSize = $size; $bestQuality = $mid
            $lo = $mid + 1
        } else {
            $hi = $mid - 1
        }
    }
    return @{ Data = $bestData; Size = $bestSize; Quality = $bestQuality }
}

# --- Step 1: File picker ---
$picker        = New-Object System.Windows.Forms.OpenFileDialog
$picker.Title  = "Select a JPEG to compress"
$picker.Filter = "JPEG Images (*.jpg;*.jpeg)|*.jpg;*.jpeg|All Files (*.*)|*.*"

if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }

$sourcePath   = $picker.FileName
$originalSize = (Get-Item $sourcePath).Length

# Grab original dimensions for reporting
$srcImg       = [System.Drawing.Image]::FromFile($sourcePath)
$origW        = $srcImg.Width
$origH        = $srcImg.Height
$srcImg.Dispose()

# --- Step 2: Target size input ---
$raw = Show-InputDialog `
    "Target file size for '$([System.IO.Path]::GetFileName($sourcePath))' (e.g. 500 KB, 1.5 MB):" `
    "JPEG Compressor"

if ($null -eq $raw) { exit }

$targetBytes = Parse-TargetSize $raw
if ($null -eq $targetBytes) {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not parse '$raw'. Enter a number followed by KB or MB (e.g. 500 KB, 1.5 MB).",
        "Invalid Input", "OK", [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

if ($targetBytes -le 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "Target size must be greater than zero.",
        "Invalid Input", "OK", [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

if ($targetBytes -ge $originalSize) {
    [System.Windows.Forms.MessageBox]::Show(
        "The file is already $(Format-Bytes $originalSize) - at or below your target of $(Format-Bytes $targetBytes). No compression needed.",
        "Nothing to Do", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# --- Phase 1: Quality 35-100 at full resolution (looks good, no color damage) ---
$result     = Find-BestQuality $sourcePath 1.0 $targetBytes -minQ 35 -maxQ 100
$finalScale = 1.0

# --- Phase 2: Quality would need to go below 35 - scale dimensions instead ---
#     Binary-search for the largest scale where quality=75 hits the target.
#     A smaller sharp image always looks better than a full-size degraded one.
if ($null -eq $result.Data) {

    $scLo = 0.05; $scHi = 1.0
    $workingScale = $null

    while (($scHi - $scLo) -gt 0.005) {
        $scMid    = [Math]::Round(($scLo + $scHi) / 2, 4)
        $testData = Compress-Jpeg $sourcePath 75 $scMid
        if ($testData.Length -le $targetBytes) {
            $workingScale = $scMid
            $scLo = $scMid
        } else {
            $scHi = $scMid
        }
    }

    if ($null -ne $workingScale) {
        # Found a good scale — now maximize quality at that scale
        $result     = Find-BestQuality $sourcePath $workingScale $targetBytes -minQ 1 -maxQ 100
        $finalScale = $workingScale
    } else {
        # --- Phase 3: Last resort — quality 1-75 at minimum scale (5%) ---
        $result     = Find-BestQuality $sourcePath 0.05 $targetBytes -minQ 1 -maxQ 75
        $finalScale = 0.05

        if ($null -eq $result.Data) {
            $floorData = Compress-Jpeg $sourcePath 1 0.05
            $minKB     = [Math]::Ceiling($floorData.Length / 1KB)
            $targetKB  = [Math]::Ceiling($targetBytes / 1KB)
            [System.Windows.Forms.MessageBox]::Show(
                "Cannot reach ${targetKB} KB even at the smallest size and lowest quality.`n`nSmallest achievable: ${minKB} KB",
                "Target Unreachable", "OK", [System.Windows.Forms.MessageBoxIcon]::Warning)
            exit
        }
    }
}

# --- Step 3: Determine output path (never overwrite source) ---
$dir      = [System.IO.Path]::GetDirectoryName($sourcePath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
$ext      = [System.IO.Path]::GetExtension($sourcePath)
$outPath  = Join-Path $dir ($baseName + "_compressed" + $ext)
$n        = 1
while (Test-Path $outPath) {
    $outPath = Join-Path $dir ($baseName + "_compressed_$n" + $ext)
    $n++
}

# --- Step 4: Write output ---
[System.IO.File]::WriteAllBytes($outPath, $result.Data)

# --- Step 5: Success notification ---
$dimLine = if ($finalScale -lt 1.0) {
    $newW = [Math]::Max(1, [int]($origW * $finalScale))
    $newH = [Math]::Max(1, [int]($origH * $finalScale))
    "`nDimensions: ${origW}x${origH} -> ${newW}x${newH} ($([int]($finalScale*100))% scale)"
} else { "" }

[System.Windows.Forms.MessageBox]::Show(
    "Compression complete!`n`nOriginal:    $(Format-Bytes $originalSize)`nCompressed: $(Format-Bytes $result.Size)  (quality $($result.Quality)/100)${dimLine}`n`nSaved to:`n$outPath",
    "JPEG Compressor", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
