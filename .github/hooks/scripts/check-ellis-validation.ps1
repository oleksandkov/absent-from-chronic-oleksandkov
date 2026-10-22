# check-ellis-validation.ps1
# Hook: warns when a numbered Ellis lane is edited but validation is stale

$input = [Console]::In.ReadToEnd() | ConvertFrom-Json

$toolName = $input.toolName
if ($toolName -notin @("replace_string_in_file", "multi_replace_string_in_file", "create_file")) {
    Write-Output '{}'
    exit 0
}

$targetFile = ""

if ($toolName -eq "replace_string_in_file" -or $toolName -eq "create_file") {
    $targetFile = $input.toolInput.filePath
} elseif ($toolName -eq "multi_replace_string_in_file") {
    $replacements = $input.toolInput.replacements
    $targetFile = ($replacements | ForEach-Object { $_.filePath }) -join "|"
}

$ellisPattern = "manipulation[\\/][0-9]+-ellis-.*\.(R|sql)$"
if ($targetFile -notmatch $ellisPattern) {
    Write-Output '{}'
    exit 0
}

$configPath = Join-Path $PWD "manipulation/pipeline-validation.dcf"
$reportPath = Join-Path $PWD "data-private/derived/manifest-validation/validation-report.md"

if (Test-Path $configPath) {
    $reportField = Get-Content $configPath | Where-Object { $_ -match '^report_path\s*[:=]' } | Select-Object -First 1
    if ($reportField) {
        $reportValue = ($reportField -split '[:=]', 2)[1].Trim()
        if ($reportValue) {
            $reportPath = Join-Path $PWD $reportValue
        }
    }
}

$message = ""

if (-not (Test-Path $reportPath)) {
    $message = "WARNING: A numbered Ellis lane was modified but no validation report exists. Run the validate-cache-manifest skill to verify CACHE-manifest.md against the configured target."
} else {
    $editedPath = ($targetFile -split '\|')[0]
    if (Test-Path $editedPath) {
        $ellisModified = (Get-Item $editedPath).LastWriteTime
        $reportModified = (Get-Item $reportPath).LastWriteTime

        if ($ellisModified -gt $reportModified) {
            $message = "WARNING: A numbered Ellis lane is newer than the validation report (last validated: $($reportModified.ToString('yyyy-MM-dd'))). Run the validate-cache-manifest skill to verify CACHE-manifest.md is still in sync."
        }
    }
}

if ($message) {
    $output = @{ systemMessage = $message } | ConvertTo-Json -Compress
    Write-Output $output
} else {
    Write-Output '{}'
}

exit 0
