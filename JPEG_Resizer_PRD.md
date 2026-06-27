# PRD: JPEG File Size Compressor

**Version:** 1.0  
**Date:** 2026-06-27  
**Status:** Draft

---

## Overview

A lightweight Windows utility — launched via a desktop shortcut — that lets a user select one or more JPEG files and specify a target file size. The program compresses each JPEG to at or below the stated size and saves the result.

---

## Problem Statement

Users frequently need to reduce JPEG file sizes to meet upload limits (email attachments, web forms, storage quotas) but lack simple, no-install tooling to do so. Existing solutions are either bloated desktop apps, online services requiring uploads, or manual trial-and-error in photo editors.

---

## Goals

- Zero-install: runs entirely in PowerShell, no third-party software required beyond Windows built-ins.
- One-click launch from a desktop shortcut.
- User specifies the *exact target size* (in KB or MB), not just a quality slider.
- Output file is saved alongside the original (or in a configurable location) without overwriting the source.

---

## Non-Goals

- Batch resizing by dimension (width/height).
- Support for image formats other than JPEG.
- A persistent GUI application or system tray icon.
- Cloud sync or sharing features.

---

## User Stories

1. **As a user**, I want to double-click a desktop shortcut so the tool opens without navigating menus or installing software.
2. **As a user**, I want to browse and select a JPEG from a file picker so I don't need to type a path.
3. **As a user**, I want to enter a target file size (e.g., `500 KB` or `1.5 MB`) so the output meets a specific limit.
4. **As a user**, I want the compressed file saved automatically (e.g., `photo_compressed.jpg`) so my original is preserved.
5. **As a user**, I want a clear success or error message so I know whether the operation worked.

---

## Functional Requirements

### FR-1: Launch via Desktop Shortcut
- A `.lnk` desktop shortcut executes a PowerShell script (`.ps1`) directly.
- The shortcut must bypass the default PowerShell execution policy (`-ExecutionPolicy Bypass`) or the script must be signed.
- No terminal window should remain open after completion (use `-WindowStyle Hidden` or show a brief summary dialog, TBD).

### FR-2: File Selection Dialog
- On launch, open a Windows file-picker dialog filtered to `*.jpg` and `*.jpeg`.
- Support single-file selection in v1.0; multi-file is a future enhancement.
- If the user cancels the dialog, the program exits cleanly with no error.

### FR-3: Target Size Input
- After file selection, prompt the user to enter a target size.
- Accept input in KB (e.g., `250`, `500 KB`) or MB (e.g., `1.5 MB`, `2 MB`).
- Validate input: reject non-numeric values and sizes ≤ 0 or larger than the original file.
- If the original file is already at or below the target size, notify the user and exit without rewriting the file.

### FR-4: Compression Engine
- Use the .NET `System.Drawing` namespace (available on all Windows machines with .NET Framework) to re-encode the JPEG with a reduced quality parameter.
- Implement a binary-search loop over JPEG quality (1–100) to converge on the largest quality value whose output is ≤ the target size.
- Convergence tolerance: within 5% of target size or within 2 KB, whichever is larger.
- Minimum quality floor: 10 (below this, output is visually unacceptable; surface a warning instead of proceeding).

### FR-5: Output File
- Save the compressed file in the same directory as the source, with the suffix `_compressed` appended before the extension (e.g., `photo.jpg` → `photo_compressed.jpg`).
- If a file with that name already exists, append an incrementing counter (`_compressed_1.jpg`, `_compressed_2.jpg`, …).
- Preserve EXIF metadata where possible.

### FR-6: Result Notification
- On success: display a Windows toast or `[System.Windows.Forms.MessageBox]` dialog showing original size, compressed size, and output path.
- On failure (e.g., cannot reach target size above quality floor): display an error message explaining the limitation and the smallest achievable size.

---

## Technical Requirements

| Requirement | Detail |
|---|---|
| Runtime | Windows PowerShell 5.1 or PowerShell 7+ |
| Dependencies | .NET Framework 4.x (built into Windows 10/11) — `System.Drawing`, `System.Windows.Forms` |
| Distribution | Single `.ps1` file + one `.lnk` shortcut |
| Execution policy | Shortcut invokes `powershell.exe -ExecutionPolicy Bypass -File "%USERPROFILE%\Desktop\jpeg-compress.ps1"` |
| No admin required | Script must run under standard user account |
| Target OS | Windows 10 and Windows 11 |

---

## UX Flow

```
[User double-clicks shortcut]
        ↓
[File picker opens → user selects JPEG]
        ↓
[Input prompt: "Target file size (e.g. 500 KB, 1.5 MB):"]
        ↓
[Validation: numeric, correct unit, below original size]
        ↓
[Binary-search compression loop]
        ↓
[Output file saved as photo_compressed.jpg]
        ↓
[MessageBox: "Done. 3.2 MB → 498 KB saved to C:\Users\…\photo_compressed.jpg"]
```

---

## Edge Cases & Error Handling

| Scenario | Behavior |
|---|---|
| User cancels file picker | Silent exit |
| Non-JPEG file somehow selected | Error dialog: "File is not a valid JPEG." |
| Target size > original size | Notify user; offer to copy original unchanged |
| Target size unreachable above quality floor | Error dialog with minimum achievable size |
| File is locked / read-only | Error dialog with OS error message |
| Output directory is not writable | Fallback: offer to save to `%TEMP%` |

---

## Out of Scope (Future Enhancements)

- Multi-file / batch processing
- Drag-and-drop onto the shortcut
- Dimension-based resizing (width × height)
- Support for PNG, WebP, HEIC
- Progress bar for large files
- Settings persistence (e.g., default output folder)

---

## Acceptance Criteria

1. Double-clicking the shortcut opens a file picker within 2 seconds on a standard Windows 10/11 machine.
2. A 5 MB JPEG compressed to a 500 KB target produces an output file ≤ 500 KB.
3. The original file is never modified.
4. The script runs without errors under a standard (non-admin) user account.
5. Canceling at any prompt exits without error dialogs or orphaned processes.
