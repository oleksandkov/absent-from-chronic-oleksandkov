<#
.SYNOPSIS
    Delete expired pipeline log directories from data-private/logs/.

.DESCRIPTION
    Reads LOG_RETENTION_DAYS from the project .env file (default: 30 days).
    Removes any data-private/logs/YYYY/YYYY-MM-DD/ directory whose date is
    older than the retention threshold.

    Run from the project root, or pass -ProjectRoot to target a specific project.

.PARAMETER ProjectRoot
    Path to the project root directory. Defaults to the current working directory.

.EXAMPLE
    # From project root in PowerShell:
    powershell -ExecutionPolicy Bypass -File utility/clean-logs.ps1

    # Explicit root (useful for machine-wide maintenance):
    powershell -ExecutionPolicy Bypass -File utility/clean-logs.ps1 -ProjectRoot "C:\path\to\project"
#>
param(
    [string]$ProjectRoot = $PWD.Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- 1. Resolve project root --------------------------------------------------
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
Write-Host "Project root : $ProjectRoot" -ForegroundColor Cyan

# -- 2. Read LOG_RETENTION_DAYS from .env -------------------------------------
$retentionDays = 30  # fallback default
$envFile = Join-Path $ProjectRoot ".env"

if (Test-Path $envFile) {
    Get-Content $envFile |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
        ForEach-Object {
            $parts = $_ -split '=', 2
            if ($parts.Count -eq 2) {
                $key   = $parts[0].Trim()
                $value = $parts[1].Trim()
                if ($key -eq 'LOG_RETENTION_DAYS') {
                    $parsed = 0
                    if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 0) {
                        $retentionDays = $parsed
                    } else {
                        Write-Warning "Invalid LOG_RETENTION_DAYS '$value' in .env -- using default $retentionDays."
                    }
                }
            }
        }
    Write-Host "LOG_RETENTION_DAYS = $retentionDays (from .env)" -ForegroundColor Yellow
} else {
    Write-Host "No .env found -- using default LOG_RETENTION_DAYS = $retentionDays" -ForegroundColor Yellow
}

if ($retentionDays -eq 0) {
    Write-Host "LOG_RETENTION_DAYS is 0 -- automatic purging is disabled. Exiting." -ForegroundColor Yellow
    exit 0
}

# -- 3. Locate logs root ------------------------------------------------------
$logsRoot = Join-Path $ProjectRoot "data-private\logs"
if (-not (Test-Path $logsRoot)) {
    Write-Host "Log directory not found: $logsRoot" -ForegroundColor Yellow
    Write-Host "Nothing to clean." -ForegroundColor Green
    exit 0
}

$cutoff = (Get-Date).Date.AddDays(-$retentionDays)
Write-Host "Cutoff date  : $($cutoff.ToString('yyyy-MM-dd'))  (today minus $retentionDays days)" -ForegroundColor Yellow
Write-Host ""

# -- 4. Walk YYYY / YYYY-MM-DD directories and collect expired ones -----------
$deleted = [System.Collections.Generic.List[string]]::new()
$errors  = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -Path $logsRoot -Directory | ForEach-Object {
    $yearDir = $_
    Get-ChildItem -Path $yearDir.FullName -Directory | ForEach-Object {
        $dateDir = $_
        $dirDate = [datetime]::MinValue
        $ok = [datetime]::TryParseExact(
            $dateDir.Name,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$dirDate
        )
        if ($ok -and $dirDate.Date -lt $cutoff) {
            try {
                Remove-Item -Path $dateDir.FullName -Recurse -Force
                $deleted.Add($dateDir.FullName)
                Write-Host "  Deleted: $($dateDir.FullName)" -ForegroundColor DarkGray
            } catch {
                $errMsg = "  FAILED : $($dateDir.FullName) - $($_.Exception.Message)"
                $errors.Add($errMsg)
                Write-Host $errMsg -ForegroundColor Red
            }
        }
    }

    # Remove empty year directories after cleaning date subdirs
    $remaining = Get-ChildItem -Path $yearDir.FullName -ErrorAction SilentlyContinue
    if ($null -eq $remaining -or $remaining.Count -eq 0) {
        try {
            Remove-Item -Path $yearDir.FullName -Force
            Write-Host "  Removed empty year dir: $($yearDir.FullName)" -ForegroundColor DarkGray
        } catch {
            # Non-fatal: the year dir may still have content from other sources
        }
    }
}

# -- 5. Summary ---------------------------------------------------------------
Write-Host ""
if ($deleted.Count -gt 0) {
    $noun = if ($deleted.Count -eq 1) { "directory" } else { "directories" }
    Write-Host "Done. Deleted $($deleted.Count) expired log $noun." -ForegroundColor Green
} else {
    Write-Host "Done. No expired log directories found." -ForegroundColor Green
}

if ($errors.Count -gt 0) {
    Write-Host "$($errors.Count) error(s) encountered -- see above." -ForegroundColor Red
    exit 1
}

exit 0
