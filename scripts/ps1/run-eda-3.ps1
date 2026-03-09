# run-eda-3.ps1
# EDA-3 Pipeline: runs the R analysis script then renders the Quarto report.
# Run from the project root: powershell -File "scripts/ps1/run-eda-3.ps1"

$ErrorActionPreference = "Stop"

Write-Host "EDA-3 PIPELINE" -ForegroundColor Cyan
Write-Host "==============" -ForegroundColor Cyan
Write-Host ""

# Step 1: Run the R analysis script
Write-Host "Step 1/2 - Running R analysis script: analysis/eda-3/eda-3.R" -ForegroundColor Yellow

try {
    Rscript "analysis/eda-3/eda-3.R"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "R script failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    Write-Host "R script completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "R script failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Render the Quarto report
Write-Host "Step 2/2 - Rendering Quarto report: analysis/eda-3/eda-3.qmd" -ForegroundColor Yellow

try {
    quarto render "analysis/eda-3/eda-3.qmd"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Quarto render failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    Write-Host "Quarto report rendered successfully." -ForegroundColor Green
}
catch {
    Write-Host "Quarto render failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "EDA-3 pipeline finished at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
