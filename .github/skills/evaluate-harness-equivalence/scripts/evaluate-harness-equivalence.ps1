<#
.SYNOPSIS
  Evaluate byte-equivalence of the project-agnostic .github harness against a reference repo.

.DESCRIPTION
  Parses the whitelist file-tree from .github/migration.md (default map:
  "Master Agnostic File Map") and compares every listed file, byte-for-byte (SHA256),
  between the local .github and a reference repo's .github. Reports identical, differing,
  and missing files. For differing files it prints a concise diff and a remediation
  suggestion so a human can decide what to implement locally.

  The whitelist is DERIVED from migration.md, so the check stays in sync with the
  documented agnostic surface. No file list is hard-coded here.

.PARAMETER ReferenceRoot
  Path to the reference (upstream / source-of-truth) repo root, or directly to its
  .github folder. Required.

.PARAMETER LocalRoot
  Path to the local repo root or its .github folder. Defaults to the repo that contains
  this script.

.PARAMETER MapName
  The migration.md map heading whose fenced code block defines the whitelist tree.
  Default: "Master Agnostic File Map".

.PARAMETER ShowDiff
  For each differing file, include up to 40 changed lines of diff (requires git; falls
  back to a line comparison when git is unavailable).

.PARAMETER IncludeIdentical
  Also list the identical files by name (default: identical files are only counted).

.PARAMETER OutFile
  Optional path to also write the plain-text report.

.OUTPUTS
  Writes a plain-text report to the host. Exit code 0 when the agnostic surface is fully
  equivalent; 1 when any difference, missing, or drift is detected.

.EXAMPLE
  pwsh -File .github/skills/evaluate-harness-equivalence/scripts/evaluate-harness-equivalence.ps1 -ReferenceRoot ../sda-ceis-impact-dev -ShowDiff
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ReferenceRoot,
  [string]$LocalRoot,
  [string]$MapName = "Master Agnostic File Map",
  [switch]$ShowDiff,
  [switch]$IncludeIdentical,
  [string]$OutFile
)

$ErrorActionPreference = "Stop"

function Resolve-GithubRoot {
  param([string]$Path)
  $rp = (Resolve-Path -LiteralPath $Path).Path
  if ((Split-Path $rp -Leaf) -ieq ".github") { return $rp }
  $candidate = Join-Path $rp ".github"
  if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
  throw "No .github directory found at or under: $Path"
}

function Get-Whitelist {
  # Parse a fenced tree under the given map heading into .github-relative file paths.
  param([string]$MarkdownPath, [string]$Map)
  if (-not (Test-Path -LiteralPath $MarkdownPath)) { throw "Whitelist file not found: $MarkdownPath" }
  $lines = Get-Content -LiteralPath $MarkdownPath

  $hIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match ("^#{2,3}\s+" + [regex]::Escape($Map) + "\s*$")) { $hIdx = $i; break }
  }
  if ($hIdx -lt 0) { throw "Map heading '$Map' not found in $MarkdownPath" }

  $start = -1
  for ($i = $hIdx + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*```') { $start = $i; break }
    if ($lines[$i] -match '^#{1,6}\s') { break }
  }
  if ($start -lt 0) { throw "No fenced code block found under '$Map'" }

  $end = -1
  for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*```') { $end = $i; break }
  }
  if ($end -lt 0) { throw "Unterminated code block under '$Map'" }

  $tree = @()
  if ($end - 1 -ge $start + 1) { $tree = $lines[($start + 1)..($end - 1)] }

  $files = New-Object System.Collections.Generic.List[string]
  $dirStack = @{}
  # Connector rows: optional indent of spaces / vertical bars, then a branch glyph.
  $rowPattern = '^(?<indent>[\s\u2502]*)[\u251C\u2514]\u2500\u2500\s+(?<name>.+?)\s*$'

  foreach ($raw in $tree) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    if ($raw -match '^\s*\.github/?\s*$') { continue }   # tree root
    $m = [regex]::Match($raw, $rowPattern)
    if (-not $m.Success) { continue }

    $indent = $m.Groups['indent'].Value
    $name = $m.Groups['name'].Value
    $depth = [int][math]::Floor($indent.Length / 4)
    $isDir = $name.EndsWith('/')
    $clean = $name.TrimEnd('/')

    $prefixParts = @()
    for ($d = 0; $d -lt $depth; $d++) { if ($dirStack.ContainsKey($d)) { $prefixParts += $dirStack[$d] } }

    if ($isDir) {
      $dirStack[$depth] = $clean
      foreach ($k in @($dirStack.Keys | Where-Object { $_ -gt $depth })) { [void]$dirStack.Remove($k) }
    }
    else {
      $rel = (($prefixParts + $clean) -join '/')
      $files.Add($rel)
    }
  }
  return $files
}

function Get-DiffText {
  param([string]$LocalFile, [string]$RefFile, [int]$MaxLines = 40)
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $stat = & git diff --no-index --stat -- $LocalFile $RefFile 2>$null | Select-Object -Last 1
    $body = & git diff --no-index -- $LocalFile $RefFile 2>$null |
      Select-String -Pattern '^[+-]' |
      Where-Object { $_.Line -notmatch '^[+-]{3}' } |
      Select-Object -First $MaxLines |
      ForEach-Object { $_.Line }
    return (@($stat) + @($body)) -join "`n"
  }
  else {
    $cmp = Compare-Object (Get-Content -LiteralPath $LocalFile) (Get-Content -LiteralPath $RefFile) |
      Select-Object -First $MaxLines |
      ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }
    return $cmp -join "`n"
  }
}

# ---- resolve roots and whitelist --------------------------------------------
$refGit = Resolve-GithubRoot -Path $ReferenceRoot
$localGit = if ($LocalRoot) { Resolve-GithubRoot -Path $LocalRoot } else { Split-Path (Split-Path (Split-Path $PSScriptRoot)) }
$whitelistFile = Join-Path $localGit "migration.md"
$whitelist = Get-Whitelist -MarkdownPath $whitelistFile -Map $MapName

# ---- compare ----------------------------------------------------------------
$identical = New-Object System.Collections.Generic.List[string]
$differing = New-Object System.Collections.Generic.List[object]
$missingLocal = New-Object System.Collections.Generic.List[string]
$missingReference = New-Object System.Collections.Generic.List[string]
$absentBoth = New-Object System.Collections.Generic.List[string]

foreach ($rel in $whitelist) {
  $lp = Join-Path $localGit $rel
  $rpth = Join-Path $refGit $rel
  $lHas = Test-Path -LiteralPath $lp
  $rHas = Test-Path -LiteralPath $rpth

  if ($lHas -and $rHas) {
    if ((Get-FileHash -LiteralPath $lp).Hash -eq (Get-FileHash -LiteralPath $rpth).Hash) {
      $identical.Add($rel)
    }
    else {
      $differing.Add([pscustomobject]@{ Rel = $rel; Local = $lp; Ref = $rpth })
    }
  }
  elseif (-not $lHas -and $rHas) { $missingLocal.Add($rel) }
  elseif ($lHas -and -not $rHas) { $missingReference.Add($rel) }
  else { $absentBoth.Add($rel) }
}

# ---- report -----------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
function Emit { param([string]$Text = "") [void]$sb.AppendLine($Text) }

Emit "Harness Equivalence Report"
Emit "=========================="
Emit "Local:     $localGit"
Emit "Reference: $refGit"
Emit "Whitelist: migration.md :: $MapName  ($($whitelist.Count) files)"
Emit ""
Emit ("SUMMARY: identical={0}  differing={1}  missing-local={2}  missing-reference={3}  absent-both={4}" -f `
    $identical.Count, $differing.Count, $missingLocal.Count, $missingReference.Count, $absentBoth.Count)
Emit ""

if ($differing.Count -gt 0) {
  Emit "[DIFFERING] ($($differing.Count)) - agnostic files that are NOT byte-identical:"
  foreach ($d in $differing) {
    Emit "  * $($d.Rel)"
    if ($ShowDiff) {
      $diff = Get-DiffText -LocalFile $d.Local -RefFile $d.Ref
      foreach ($line in ($diff -split "`n")) { Emit "      $line" }
    }
    Emit "      Suggestion: Reference is the upstream source of truth. Review the diff and adopt"
    Emit "      the reference version locally, UNLESS this is an intentional, documented deviation"
    Emit "      (e.g., a repo-specific reference the reference repo leaked into an agnostic file)."
  }
  Emit ""
}

if ($missingLocal.Count -gt 0) {
  Emit "[MISSING LOCALLY] ($($missingLocal.Count)) - agnostic files present in reference, absent locally:"
  foreach ($rel in $missingLocal) { Emit "  * $rel" }
  Emit "      Suggestion: Copy each file from the reference .github to restore harness completeness."
  Emit ""
}

if ($missingReference.Count -gt 0) {
  Emit "[MISSING IN REFERENCE] ($($missingReference.Count)) - agnostic files present locally, absent in reference:"
  foreach ($rel in $missingReference) { Emit "  * $rel" }
  Emit "      Suggestion: Local is AHEAD here. Consider contributing these files upstream to the reference."
  Emit ""
}

if ($absentBoth.Count -gt 0) {
  Emit "[WHITELIST DRIFT] ($($absentBoth.Count)) - listed in migration.md but absent in BOTH repos:"
  foreach ($rel in $absentBoth) { Emit "  * $rel" }
  Emit "      Suggestion: Remove the stale entry from migration.md, or create the missing file."
  Emit ""
}

if ($IncludeIdentical -and $identical.Count -gt 0) {
  Emit "[IDENTICAL] ($($identical.Count)):"
  foreach ($rel in $identical) { Emit "  * $rel" }
  Emit ""
}

$equivalent = ($differing.Count -eq 0 -and $missingLocal.Count -eq 0 -and $missingReference.Count -eq 0 -and $absentBoth.Count -eq 0)
if ($equivalent) {
  Emit "RESULT: EQUIVALENT - the project-agnostic harness is byte-identical across both repos."
}
else {
  Emit "RESULT: NOT EQUIVALENT - review the sections above and reconcile."
}

$report = $sb.ToString()
Write-Output $report
if ($OutFile) {
  $report | Set-Content -LiteralPath $OutFile -Encoding UTF8
  Write-Output "Report written to: $OutFile"
}

if ($equivalent) { exit 0 } else { exit 1 }
