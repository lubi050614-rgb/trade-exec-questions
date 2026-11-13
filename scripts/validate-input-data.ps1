param(
    [string]$DataDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data\generated\execution-inputs-v1'),
    [switch]$SelfTest,
    [switch]$PublishReport
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not ('TradeInputs.InputValidation' -as [type])){Add-Type -Path (Join-Path $root 'src\input-fixtures\InputValidator.cs') -ReferencedAssemblies System.Web.Extensions,System.Core}
$schema=[ordered]@{}
foreach($g in ((Import-Csv -Encoding UTF8 (Join-Path $root 'data\schema\columns.csv')) | Group-Object table_name)){
    $fields=[ordered]@{};foreach($c in $g.Group){$fields[$c.column_name]=$c.type};$schema[$g.Name]=$fields
}
$result=[TradeInputs.InputValidation]::Validate([System.IO.Path]::GetFullPath($DataDirectory),($schema | ConvertTo-Json -Depth 8 -Compress),[bool]$SelfTest)
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $DataDirectory 'validation.json'),$result,$utf8)
if($PublishReport){[System.IO.File]::WriteAllText((Join-Path $root 'deliverables\input-validation.json'),$result,$utf8)}
$result | ConvertFrom-Json | ConvertTo-Json -Depth 8
