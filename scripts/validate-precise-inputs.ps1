param([string]$DataDirectory,[string]$OutputDirectory,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $DataDirectory){$DataDirectory=Join-Path $root 'data/generated/execution-inputs-v1'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'deliverables'}
Add-Type -Path (Join-Path $root 'src/input-fixtures/PreciseInputValidator.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
[TradeInputs.PreciseInputValidator]::Validate($root,$DataDirectory,$OutputDirectory,[bool]$SelfTest)
