# check-publishing-validation.ps1
# Hook: warns when frontend publishing artifacts are modified but fidelity report is stale

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $payload.toolName
if ($toolName -notin @("replace_string_in_file", "multi_replace_string_in_file", "create_file")) {
    Write-Output '{}'
    exit 0
}

$targetFile = ""

if ($toolName -eq "replace_string_in_file" -or $toolName -eq "create_file") {
    $targetFile = $payload.toolInput.filePath
} elseif ($toolName -eq "multi_replace_string_in_file") {
    $replacements = $payload.toolInput.replacements
    $targetFile = ($replacements | ForEach-Object { $_.filePath }) -join "|"
}

$editedPath = ($targetFile -split '\|')[0]
$frontendMatch = [regex]::Match($editedPath, "_frontend-[0-9]+[\\/]")
if (-not $frontendMatch.Success) {
    Write-Output '{}'
    exit 0
}

$frontendRoot = $frontendMatch.Value.TrimEnd("/", "\\")
if (-not (Test-Path $frontendRoot)) {
    Write-Output '{}'
    exit 0
}

$relevantPattern = "_frontend-[0-9]+[\\/](publishing-contract\.prompt\.md|_quarto\.yml|content[\\/].*|scripts[\\/].*)"
if ($editedPath -notmatch $relevantPattern) {
    Write-Output '{}'
    exit 0
}

$reportPath = Join-Path $frontendRoot "FIDELITY_REPORT.md"
$message = ""

if (-not (Test-Path $reportPath)) {
    $message = "WARNING: Publishing files were updated in $frontendRoot but FIDELITY_REPORT.md is missing. Run /publishing-validate (or the publishing-fidelity-audit skill)."
} else {
    $editedModified = (Get-Item $editedPath).LastWriteTime
    $reportModified = (Get-Item $reportPath).LastWriteTime

    if ($editedModified -gt $reportModified) {
        $message = "WARNING: Publishing files in $frontendRoot are newer than FIDELITY_REPORT.md (last audit: $($reportModified.ToString('yyyy-MM-dd HH:mm'))). Run /publishing-validate."
    }
}

if ($message) {
    $output = @{ systemMessage = $message } | ConvertTo-Json -Compress
    Write-Output $output
} else {
    Write-Output '{}'
}

exit 0
