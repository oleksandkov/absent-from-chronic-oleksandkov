# Helper for running model-3 from an agent terminal that mangles long
# interactive command lines. Not part of the pipeline; safe to delete.
$ErrorActionPreference = "Continue"
$rscript = "C:\Users\andriy.koval\AppData\Local\Programs\R\R-4.6.0\bin\Rscript.exe"
$log = "analysis/model-3/run-log.txt"

& $rscript "analysis/model-3/model-3.R" 2>&1 | Tee-Object -FilePath $log | Out-Null

Write-Output "EXIT CODE: $LASTEXITCODE"
Write-Output "----- LAST 60 LINES -----"
Get-Content $log -Tail 60
