# jpeg-compress.ps1
# JPEG File Size Compressor
# Compresses a JPEG to a user-specified target file size using binary-search quality tuning.
# Launch via the desktop shortcut created by Create-Shortcut.ps1

#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Inline C# compression engine (avoids lock-file issues with temp files) ────
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

public class JpegCompressor {

    public static byte[] Compress(string sourcePath, int quality) {
        var codec  = GetJpegCodec();
        var ep     = new EncoderParameters(1);
        ep.Param[0] = new EncoderParameter(Encoder.Quality, (long)quality);

        using (var img = Image.FromFile(sourcePath)) {
            // Copy EXIF properties to preserve metadata
            using (var ms = new MemoryStream()) {
                img.Save(ms, codec, ep);
                return ms.ToArray();
            }
        }
    }

    private static ImageCodecInfo GetJpegCodec() {
        foreach (var c in ImageCodecInfo.GetImageEncoders())
            if (c.MimeType == "image/jpeg") return c;
        throw new Exception("JPEG codec not found on this system.");
    }
}
"@ -ReferencedAssemblies "System.Drawing" -ErrorAction Stop

# ── Helper: format byte count as human-readable string ───────────────────────
function Format-Bytes([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

# ── Helper: simple input dialog ───────────────────────────────────────────────
function Show-InputDialog([string]$prompt, [string]$title) {
    $form            = New-Object System.Windows.Forms.Form
    $form.Text       = $title
    $form.Size       = New-Object System.Drawing.Size(380, 165)
    $form.StartPosition  = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox    = $false
    $form.MinimizeBox    = $false

    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $prompt
    $lbl.Location = New-Object System.Drawing.Point(12, 18)
    $lbl.Size     = New-Object System.Drawing.Size(344, 20)

    $txt          = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(12, 46)
    $txt.Size     = New-Object System.Drawing.Size(344, 24)

    $btnOK                = New-Object System.Windows.Forms.Button
    $btnOK.Text           = "OK"
    $btnOK.Location       = New-Object System.Drawing.Point(12, 84)
    $btnOK.Size           = New-Object System.Drawing.Size(80, 28)
    $btnOK.DialogResult   = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton    = $btnOK

    $btnCancel            = New-Object System.Windows.Forms.Button
    $btnCancel.Text       = "Cancel"
    $btnCancel.Location   = New-Object System.Drawing.Point(100, 84)
    $btnCancel.Size       = New-Object System.Drawing.Size(80, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton    = $btnCancel

    $form.Controls.AddRange(@($lbl, $txt, $btnOK, $btnCancel))
    $form.ActiveControl = $txt

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text.Trim() }
    return $null
}

# ── Helper: parse "500 KB" / "1.5 MB" / "500" → bytes ───────────────────────
function Parse-TargetSize([string]$input) {
    if ($input -match '^([\d.]+)\s*(KB|MB)?$') {
        $num  = [double]$Matches[1]
        $unit = if ($Matches[2]) { $Matches[2].ToUpper() } else { 'KB' }
        if ($unit -eq 'MB') { return [long]($num * 1MB) }
        return [long]($num * 1KB)
    }
    return $null
}

# ── Step 1: File picker ───────────────────────────────────────────────────────
$picker        = New-Object System.Windows.Forms.OpenFileDialog
$picker.Title  = "Select a JPEG to compress"
$picker.Filter = "JPEG Images (*.jpg;*.jpeg)|*.jpg;*.jpeg|All Files (*.*)|*.*"

if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }

$sourcePath   = $picker.FileName
$originalSize = (Get-Item $sourcePath).Length

# ── Step 2: Target size input ─────────────────────────────────────────────────
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
        "The file is already $(Format-Bytes $originalSize) — at or below your target of $(Format-Bytes $targetBytes). No compression needed.",
        "Nothing to Do", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# ── Step 3: Check floor quality achievability ─────────────────────────────────
$MIN_QUALITY = 10
$floorData   = [JpegCompressor]::Compress($sourcePath, $MIN_QUALITY)
$floorSize   = $floorData.Length

if ($floorSize -gt $targetBytes) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot reach $(Format-Bytes $targetBytes) without dropping below minimum quality (q=$MIN_QUALITY).`n`nSmallest achievable size: $(Format-Bytes $floorSize)`n`nTry a larger target size.",
        "Target Unreachable", "OK", [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

# ── Step 4: Binary-search for best quality ≤ target ──────────────────────────
$lo          = $MIN_QUALITY
$hi          = 100
$bestData    = $null
$bestSize    = 0
$bestQuality = 0

while ($lo -le $hi) {
    $mid  = [int](($lo + $hi) / 2)
    $data = [JpegCompressor]::Compress($sourcePath, $mid)
    $size = $data.Length

    if ($size -le $targetBytes) {
        $bestData    = $data
        $bestSize    = $size
        $bestQuality = $mid
        $lo = $mid + 1      # try higher quality
    } else {
        $hi = $mid - 1      # too big, reduce quality
    }
}

if ($null -eq $bestData) {
    [System.Windows.Forms.MessageBox]::Show(
        "Compression failed unexpectedly. Please try again.",
        "Error", "OK", [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# ── Step 5: Determine output path (never overwrite source) ────────────────────
$dir      = [System.IO.Path]::GetDirectoryName($sourcePath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
$ext      = [System.IO.Path]::GetExtension($sourcePath)
$outPath  = Join-Path $dir ($baseName + "_compressed" + $ext)
$n        = 1
while (Test-Path $outPath) {
    $outPath = Join-Path $dir ($baseName + "_compressed_$n" + $ext)
    $n++
}

# ── Step 6: Write output ──────────────────────────────────────────────────────
[System.IO.File]::WriteAllBytes($outPath, $bestData)

# ── Step 7: Success notification ─────────────────────────────────────────────
[System.Windows.Forms.MessageBox]::Show(
    "Compression complete!`n`nOriginal:     $(Format-Bytes $originalSize)`nCompressed:  $(Format-Bytes $bestSize)  (quality $bestQuality/100)`n`nSaved to:`n$outPath",
    "JPEG Compressor", "OK", [System.Windows.Forms.MessageBoxIcon]::Information)
