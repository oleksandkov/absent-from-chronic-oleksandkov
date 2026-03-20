#
# run-interactive-flow.ps1
# Interactive pipeline runner for the absent-from-chronic project.
#
# Q1 - Ellis mode: run-as-is / default flags / strict (all TRUE)
# Q2 - EDA selection: scans analysis/ dynamically
# Q3 - Run mode: apply selections and run, or run as-is
#
# Also scans manipulation/ for new numbered lanes not yet in flow.R.
# No backups - changes are applied directly before launch.
#

# Ensure we run from the project root
Set-Location (Join-Path $PSScriptRoot "..\..")

# ---------------------------------------------------------------------------
function Write-Box {
    param([string[]]$Lines)
    $maxLen = ($Lines | Measure-Object -Property Length -Maximum).Maximum
    $border = "-" * ($maxLen + 4)
    Write-Host "+$border+" -ForegroundColor Cyan
    foreach ($line in $Lines) {
        $pad = " " * ($maxLen - $line.Length)
        Write-Host "|  $line$pad  |" -ForegroundColor Cyan
    }
    Write-Host "+$border+" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
function Get-EdaCandidates {
    $results = [System.Collections.Generic.List[PSObject]]::new()
    if (-not (Test-Path "analysis")) { return $results }
    foreach ($dir in (Get-ChildItem "analysis" -Directory | Sort-Object Name)) {
        $rFiles   = @(Get-ChildItem $dir.FullName -Filter "*.R"   -File)
        $qmdFiles = @(Get-ChildItem $dir.FullName -Filter "*.qmd" -File)
        if ($rFiles.Count -gt 0 -and $qmdFiles.Count -gt 0) {
            $results.Add([PSCustomObject]@{
                RelativePath = "analysis/$($dir.Name)"
                RFile        = $rFiles[0].Name
                QmdFile      = $qmdFiles[0].Name
            })
        }
    }
    return $results
}

# ---------------------------------------------------------------------------
function Get-NewManipulationLanes {
    $flowContent = Get-Content "flow.R" -Raw -Encoding UTF8
    $results     = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem "manipulation" -Filter "*.R" -File |
        Where-Object { $_.Name -match "^\d+-" } |
        Sort-Object Name |
        ForEach-Object {
            if ($flowContent -notmatch [regex]::Escape($_.Name)) {
                $results.Add("manipulation/$($_.Name)")
            }
        }
    return $results
}

# ---------------------------------------------------------------------------
function Set-EllisFlags {
    param([string]$Mode)
    $path    = "manipulation/2-ellis.R"
    $content = Get-Content $path -Raw -Encoding UTF8
    if ($Mode -eq "strict") {
        $sci = "TRUE" ; $ase = "TRUE" ; $ace = "TRUE"
        Write-Host "  [OK] Ellis flags -> STRICT" -ForegroundColor Green
    } else {
        $sci = "FALSE" ; $ase = "TRUE" ; $ace = "FALSE"
        Write-Host "  [OK] Ellis flags -> DEFAULT" -ForegroundColor Green
    }
    $content = $content -replace '(?m)^(strict_cycle_integrity\s*<-).*$',       ('$1 ' + $sci)
    $content = $content -replace '(?m)^(apply_sample_exclusions\s*<-).*$',      ('$1 ' + $ase)
    $content = $content -replace '(?m)^(apply_completeness_exclusion\s*<-).*$', ('$1 ' + $ace)
    [System.IO.File]::WriteAllText((Resolve-Path $path).ProviderPath, $content)
}

# ---------------------------------------------------------------------------
function Disable-EdaLines {
    $path    = "flow.R"
    $content = Get-Content $path -Raw -Encoding UTF8
    # Match active (uncommented) EDA lines pointing to analysis/ in ds_rail
    $pattern  = '(?m)^(\s*)("run_[^"]*"\s*,\s*"analysis/[^\r\n]*)'
    $modified = $content -replace $pattern, '$1# $2'
    if ($modified -ne $content) {
        [System.IO.File]::WriteAllText((Resolve-Path $path).ProviderPath, $modified)
        Write-Host "  [OK] Commented out all active EDA lines in flow.R" -ForegroundColor Green
    } else {
        Write-Host "  (No active EDA lines found in flow.R -- nothing to disable)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
function Enable-EdaLines {
    param([string[]]$EdaPaths)
    $path    = "flow.R"
    $content = Get-Content $path -Raw -Encoding UTF8
    foreach ($edaPath in $EdaPaths) {
        $escaped  = [regex]::Escape($edaPath)
        $pattern  = '(?m)^(\s*)# ("run_[^"]*"\s*,\s*"' + $escaped + '/[^"]*"[^\r\n]*)'
        $modified = $content -replace $pattern, '$1$2'

        if ($modified -ne $content) {
            # Lines existed as comments -- uncomment them
            $content = $modified
            Write-Host "  [OK] Uncommented EDA: $edaPath" -ForegroundColor Green
        } else {
            # No lines at all -- INSERT new active rows into ds_rail
            $dirName = Split-Path $edaPath -Leaf
            $rLine   = '  "run_r_soft"  , "' + $edaPath + '/' + $dirName + '.R",'
            $qmdLine = '  "run_qmd_soft", "' + $edaPath + '/' + $dirName + '.qmd",'

            # Anchor: find the last active line containing "analysis/" in ds_rail
            $anchorPattern = '(?m)(\s*"run_[^"]*"\s*,\s*"analysis/[^"]*"[^\r\n]*)'
            $matches = [regex]::Matches($content, $anchorPattern)
            if ($matches.Count -gt 0) {
                $last = $matches[$matches.Count - 1]
                $insertPos = $last.Index + $last.Length
                $content = $content.Insert($insertPos, "`r`n$rLine`r`n$qmdLine")
                Write-Host "  [OK] Inserted EDA rows: $edaPath" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Could not auto-insert $edaPath -- add rows manually in flow.R ds_rail" -ForegroundColor Yellow
            }
        }
    }
    [System.IO.File]::WriteAllText((Resolve-Path $path).ProviderPath, $content)
}

# ---------------------------------------------------------------------------
function Add-LaneToFlow {
    param([string]$LanePath)
    $path    = "flow.R"
    $content = Get-Content $path -Raw -Encoding UTF8
    if ($content -match '(?m)^\s*"run_r"\s+,\s+"manipulation/2-ellis\.R"[^\r\n]*') {
        $anchor  = $Matches[0]
        $newLine = '  "run_r"     , "' + $LanePath + '",'
        $content = $content.Replace($anchor, "$anchor`n$newLine")
        [System.IO.File]::WriteAllText((Resolve-Path $path).ProviderPath, $content)
        Write-Host "  [OK] Added to flow.R: $LanePath" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not auto-insert $LanePath -- add it manually in flow.R ds_rail" -ForegroundColor Yellow
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

Write-Host ""
Write-Host "+----------------------------------------------------------+" -ForegroundColor Magenta
Write-Host "|  Interactive Pipeline Runner  *  flow.R                 |" -ForegroundColor Magenta
Write-Host "|  Project root: $($PWD.Path)"
Write-Host "+----------------------------------------------------------+" -ForegroundColor Magenta
Write-Host ""

# --- Q1: Ellis Mode ----------------------------------------------------------

Write-Box @(
    "Q1  Select Ellis mode:",
    "[1]  Run as-is    no changes -- execute flow.R exactly as it stands",
    "[2]  Default      strict_cycle_integrity=FALSE  apply_sample_exclusions=TRUE  apply_completeness_exclusion=FALSE",
    "[3]  Strict       all three pipeline flags = TRUE"
)

do {
    $q1 = (Read-Host "  Choice [1-3]").Trim()
} while ($q1 -notin @("1","2","3"))

if ($q1 -eq "1") {
    Write-Host ""
    Write-Host "  >> Running flow.R as-is (no file changes) ..." -ForegroundColor Yellow
    Write-Host ""
    Rscript flow.R
    exit $LASTEXITCODE
}

# --- Scan for new numbered lane files ----------------------------------------

Write-Host ""
Write-Host "  Scanning manipulation/ for new numbered lane files ..." -ForegroundColor DarkGray
$newLanes = Get-NewManipulationLanes

if ($newLanes.Count -gt 0) {
    Write-Host "  Found lane file(s) not referenced in flow.R:" -ForegroundColor Yellow
    foreach ($lane in $newLanes) {
        Write-Host "    $lane" -ForegroundColor White
        do {
            $yn = (Read-Host "    Add '$lane' to flow.R after 2-ellis.R? [y/n]").Trim()
        } while ($yn -notin @("y","Y","n","N"))
        if ($yn -in @("y","Y")) {
            Add-LaneToFlow -LanePath $lane
        }
    }
} else {
    Write-Host "  (No unlisted lane files found)" -ForegroundColor DarkGray
}

# --- Q2: EDA Selection -------------------------------------------------------

Write-Host ""
$edaCandidates = Get-EdaCandidates
$selectedEdas  = @()

if ($edaCandidates.Count -eq 0) {
    Write-Host "  (No EDA candidates found in analysis/ -- skipping)" -ForegroundColor DarkGray
} else {
    $menuLines = @("Q2  Select EDAs to enable in flow.R (comma-separated):","[0]  None")
    for ($i = 0; $i -lt $edaCandidates.Count; $i++) {
        $e = $edaCandidates[$i]
        $menuLines += "[$($i + 1)]  $($e.RelativePath)   ($($e.RFile) + $($e.QmdFile))"
    }
    $allNum = $edaCandidates.Count + 1
    $menuLines += "[$allNum]  All EDAs"
    Write-Box $menuLines

    $valid = @("0") + @(1..$edaCandidates.Count | ForEach-Object { "$_" }) + @("$allNum")
    do {
        $raw     = Read-Host "  Choice(s)  e.g. 1   or   1,2   or   $allNum"
        $parts   = $raw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $badOnes = @($parts | Where-Object { $_ -notin $valid })
        if ($badOnes.Count -gt 0) {
            Write-Host "  [!] Invalid choice(s): $($badOnes -join ', ')  -- valid values are: $($valid -join ', ')" -ForegroundColor Red
        }
    } while ($badOnes.Count -gt 0)

    if ($parts -contains "0") {
        $selectedEdas = @()
    } elseif ($parts -contains "$allNum") {
        $selectedEdas = @($edaCandidates | ForEach-Object { $_.RelativePath })
    } else {
        $selectedEdas = @($parts | ForEach-Object { $edaCandidates[[int]$_ - 1].RelativePath })
    }
}

# --- Q3: Run Mode ------------------------------------------------------------

Write-Host ""
Write-Box @(
    "Q3  How do you want to run?",
    "[1]  Apply all selections above and run",
    "[2]  Run flow.R as-is   (skip all file changes)"
)

do {
    $q3 = (Read-Host "  Choice [1-2]").Trim()
} while ($q3 -notin @("1","2"))

if ($q3 -eq "2") {
    Write-Host ""
    Write-Host "  >> Running flow.R as-is (no file changes) ..." -ForegroundColor Yellow
    Write-Host ""
    Rscript flow.R
    exit $LASTEXITCODE
}

# --- Apply Changes -----------------------------------------------------------

Write-Host ""
Write-Host "  Applying changes ..." -ForegroundColor Cyan

Set-EllisFlags -Mode $(if ($q1 -eq "3") { "strict" } else { "default" })

if ($selectedEdas.Count -gt 0) {
    Enable-EdaLines -EdaPaths $selectedEdas
} else {
    Disable-EdaLines
}

# --- Run Pipeline ------------------------------------------------------------

Write-Host ""
Write-Host "  >> Running flow.R ..." -ForegroundColor Yellow
Write-Host ""
Rscript flow.R
exit $LASTEXITCODE