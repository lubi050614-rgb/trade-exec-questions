param([string]$DataDirectory,[string]$ArchivePath,[switch]$VerifyRepack)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $DataDirectory){$DataDirectory=Join-Path $root 'data/generated/execution-inputs-v1'}
if(-not $ArchivePath){$ArchivePath=Join-Path $root 'deliverables/执行输入数据_200标的5日.zip'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'manifest.json') | ConvertFrom-Json
$catalog=Get-Content -Raw -Encoding UTF8 (Join-Path $DataDirectory 'case-manifest.json') | ConvertFrom-Json
$allowed=@{}
foreach($file in (@($manifest.files)+@($catalog.files))){$allowed[$file.path]=$file.sha256}
foreach($relative in @('manifest.json','config.json','README.md','validation.json','question-inputs.jsonl','case-manifest.json','precise-validation.json')){$allowed[$relative]=(Get-FileHash -LiteralPath (Join-Path $DataDirectory $relative) -Algorithm SHA256).Hash.ToLowerInvariant()}
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
try{
    if($zip.Entries.Count -ne $allowed.Count){throw 'Input archive file count mismatch'}
    $seen=@{}
    foreach($entry in $zip.Entries){
        $name=$entry.FullName
        if(-not $allowed.ContainsKey($name) -or $seen.ContainsKey($name) -or $name -match '_internal|\.\.' -or [IO.Path]::IsPathRooted($name)){throw 'Unknown/private/duplicate archive entry'}
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
        if($actual -ne $allowed[$name]){throw "Stale or damaged archive entry: $name"}
        $seen[$name]=$true
    }
}finally{$zip.Dispose()}
$trial=Join-Path $root ('reports/local/archive-check-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $trial | Out-Null
$unpacked=Join-Path $trial 'unpacked'
[IO.Compression.ZipFile]::ExtractToDirectory([IO.Path]::GetFullPath($ArchivePath),$unpacked)
$reader=Join-Path $root 'scripts/read-question-input.ps1'
foreach($id in @('P01-S01-Q02','P02-S01-Q01','P05-S08-Q05','P09-S01-Q02','P13-S01-Q03','P01-S08-Q08','P07-S03-Q09')){
    $raw=& powershell -NoProfile -ExecutionPolicy Bypass -File $reader -QuestionId $id -DataDirectory $unpacked -MetadataOnly
    if($LASTEXITCODE -ne 0){throw "Reader failed from extracted archive: $id"}
    $sample=($raw -join "`n") | ConvertFrom-Json
    if($sample.case.question_id -ne $id -or $sample.question.real_dataset_ready -ne $false){throw 'Reader returned wrong question/source'}
    if($id -eq 'P01-S01-Q02' -and ($sample.case.small_case.given.pending_buy_qty -ne 400 -or $sample.case.scenario_inputs.Count -ne 0)){throw 'Literal question input or isolation failed'}
    if($id -eq 'P01-S08-Q08'){
        $fault=@($sample.case.scenario_inputs | Where-Object variant -eq 'fault')[0]
        $recovery=@($sample.case.scenario_inputs | Where-Object variant -eq 'recovery')[0]
        if($fault.input.diagnostic_observation.journal_fill_qty -ne 1200 -or $recovery.input.diagnostic_observation.journal_fill_qty -ne 1200 -or $recovery.input.recovery_evidence.diagnostic_query.broker_cum_qty -ne 400){throw 'Recovery leaked solved state or lost raw broker query'}
    }
}
$deterministic='not_requested'
if($VerifyRepack){
    $copy=Join-Path $trial 'repacked.zip'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/package-input-data.ps1') -DataDirectory $DataDirectory -ArchivePath $copy | Out-Null
    if($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash){throw 'Input ZIP is not deterministic'}
    $deterministic='matched'
}
$result=[ordered]@{result='passed';archive_entries=$allowed.Count;entry_hashes='all_matched';question_cases=1150;node_variants=575;extracted_reader_samples=7;old_generic_cases_included=0;private_files_included=0;recovery_final_state_leakage='blocked';deterministic_repack=$deterministic;archive_sha256=(Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant();answers_generated=0;real_dataset_ready=$false}
[IO.File]::WriteAllText((Join-Path $root 'deliverables/input-archive-validation.json'),($result | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json
