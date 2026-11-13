param([string]$DataDirectory,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $DataDirectory){$DataDirectory=Join-Path $root 'data/generated/execution-inputs-v1'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'deliverables'}
Add-Type -Path (Join-Path $root 'src/input-fixtures/PreciseCases.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
[TradeInputs.PreciseCases]::Build($root,$DataDirectory,(Join-Path $OutputDirectory '交易执行_教师输入.jsonl'),(Join-Path $OutputDirectory '节点数据契约.json'))
