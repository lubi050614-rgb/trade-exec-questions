param([switch]$Overwrite)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Run-Stage([string]$script,[string[]]$stageArgs){
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $script) @stageArgs
    if($LASTEXITCODE -ne 0){throw "Stage failed: $script"}
}
Run-Stage 'build-deliverables.ps1' @()
$genArgs=if($Overwrite){@('-Overwrite')}else{@()}
Run-Stage 'scripts/generate-input-data.ps1' $genArgs
Run-Stage 'scripts/validate-input-data.ps1' @('-SelfTest','-PublishReport')
Run-Stage 'scripts/bind-question-inputs.ps1' @()
# Refresh the original CSV/contracts from validated input evidence, then bind the refreshed question source.
Run-Stage 'build-deliverables.ps1' @()
Run-Stage 'scripts/bind-question-inputs.ps1' @()
Run-Stage 'scripts/validate-question-bank.ps1' @('-SelfTest')
Run-Stage 'scripts/test-question-inputs.ps1' @()
Run-Stage 'scripts/write-precise-input-report.ps1' @()
Run-Stage 'scripts/package-input-data.ps1' @()
Run-Stage 'scripts/test-input-archive.ps1' @('-VerifyRepack')
Write-Output 'Question/input package built. No teacher calls, answers, or real-market claims.'
