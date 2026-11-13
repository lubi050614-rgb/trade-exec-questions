$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root 'reports\local\reproducibility'
$runA=Join-Path $work 'run-a'
$runB=Join-Path $work 'run-b'
# Dedicated output dirs: no recursive deletion and no dependence on desktop files.
foreach($dir in @($runA,$runB)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build-deliverables.ps1') -OutputDirectory $dir | Out-Null
    if($LASTEXITCODE -ne 0){throw "Build failed: $dir"}
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\validate-question-bank.ps1') -OutputDirectory $dir -SelfTest | Out-Null
    if($LASTEXITCODE -ne 0){throw "Validation failed: $dir"}
}
$filesA=@(Get-ChildItem -LiteralPath $runA -File | Sort-Object Name)
$filesB=@(Get-ChildItem -LiteralPath $runB -File | Sort-Object Name)
if(($filesA.Name -join '|') -ne ($filesB.Name -join '|')) {throw 'Output file lists differ'}
$checks=foreach($file in $filesA){
    $hashA=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $hashB=(Get-FileHash -LiteralPath (Join-Path $runB $file.Name) -Algorithm SHA256).Hash
    if($hashA -ne $hashB){throw "Non-deterministic output: $($file.Name)"}
    [pscustomobject]@{file=$file.Name;sha256=$hashA;matched=$true}
}
$result=[ordered]@{checked_at='2026-11-13';independent_builds=2;output_file_count=$filesA.Count;result='passed';files=@($checks)}
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $root 'deliverables\reproducibility.json'),($result | ConvertTo-Json -Depth 6),$utf8)
Write-Output "PASS: two independent processes produced identical hashes for $($filesA.Count) files."
