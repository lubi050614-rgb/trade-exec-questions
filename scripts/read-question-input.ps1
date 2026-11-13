param(
    [Parameter(Mandatory=$true)][string]$QuestionId,
    [string]$DataDirectory,
    [ValidateRange(1,1000)][int]$MaxRowsPerFile=3,
    [string]$AsOf,
    [string[]]$Symbols,
    [switch]$MetadataOnly,
    [string]$ExportDirectory
)
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path $PSScriptRoot -Parent
if(-not $DataDirectory){$DataDirectory=Join-Path $repositoryRoot 'data\generated\execution-inputs-v1'}
$root=[System.IO.Path]::GetFullPath($DataDirectory).TrimEnd('\','/')
$index=Join-Path $root 'question-inputs.jsonl'
if(-not(Test-Path -LiteralPath $index)){throw 'Generate and bind question inputs first'}
$binding=$null
foreach($line in [System.IO.File]::ReadLines($index,[System.Text.Encoding]::UTF8)){$r=$line | ConvertFrom-Json;if($r.question_id -eq $QuestionId){$binding=$r;break}}
if($null -eq $binding){throw 'Unknown question ID'}
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'manifest.json') | ConvertFrom-Json
$allowed=@{};foreach($entry in $manifest.files){$allowed[$entry.path]=$entry}
if($AsOf){$cutoff=[datetimeoffset]::Parse($AsOf,[cultureinfo]::InvariantCulture)}
function Resolve-SafeInput([string]$path){
    $full=[System.IO.Path]::GetFullPath((Join-Path $root $path))
    if(-not $full.StartsWith($root+[System.IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $path -match '_internal'){throw 'Input path escapes public dataset'}
    return $full
}
$caseFull=Resolve-SafeInput $binding.case_file
if((Get-FileHash -LiteralPath $caseFull -Algorithm SHA256).Hash.ToLowerInvariant() -ne $binding.case_sha256){throw 'Case file checksum mismatch'}
$case=Get-Content -Raw -Encoding UTF8 $caseFull | ConvertFrom-Json
foreach($ref in $binding.input_files){if(-not $allowed.ContainsKey($ref.path) -or $ref.sha256 -ne $allowed[$ref.path].sha256){throw 'Input is not in the public manifest'}; $null=Resolve-SafeInput $ref.path}
if($MetadataOnly){[pscustomobject]@{question=$binding;case=$case;view_mode='metadata_only';answers_generated=0} | ConvertTo-Json -Depth 20;exit 0}
$samples=New-Object System.Collections.Generic.List[object]
foreach($ref in $binding.input_files){
    if(-not $allowed.ContainsKey($ref.path) -or $ref.sha256 -ne $allowed[$ref.path].sha256){throw 'Input is not in the validated public manifest'}
    $path=Resolve-SafeInput $ref.path
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ref.sha256){throw 'Input file checksum mismatch'}
    $preview=New-Object System.Collections.Generic.List[object]
    $writer=$null;$eligible=0;$scanned=0;$stoppedEarly=$false
    if($ExportDirectory){
        $exportRoot=[System.IO.Path]::GetFullPath($ExportDirectory).TrimEnd('\','/')
        if($exportRoot -eq $root -or $exportRoot.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Export directory must not overwrite the source dataset'}
        $export=Join-Path $exportRoot $ref.path
        New-Item -ItemType Directory -Force -Path (Split-Path $export -Parent) | Out-Null
        $writer=New-Object System.IO.StreamWriter($export,$false,(New-Object System.Text.UTF8Encoding($false)));$writer.NewLine="`n"
    }
    try{
        foreach($line in [System.IO.File]::ReadLines($path,[System.Text.Encoding]::UTF8)){
            $scanned++;$row=$line | ConvertFrom-Json
            if($row.variant -and $binding.filters.special_variants -and $row.variant -notin $binding.filters.special_variants){continue}
            if($Symbols){
                $sym=if($row.security_code){$row.security_code}elseif($row.symbol){$row.symbol}elseif($row.component_code){$row.component_code}else{$null}
                if($sym -and $sym -notin $Symbols){continue}
            }
            if($AsOf){
                $policy=$ref.availability
                if($policy.constant_available_at){$visible=[datetimeoffset]::Parse($policy.constant_available_at,[cultureinfo]::InvariantCulture)}else{
                    $value=$row.($policy.field)
                    if(-not $value){throw "No visibility timestamp for $($ref.path); cannot safely perform as-of filtering"}
                    if($policy.date_time_suffix){$value=[string]$value+$policy.date_time_suffix}
                    $visible=([datetimeoffset]::Parse([string]$value,[cultureinfo]::InvariantCulture)).AddMilliseconds([int]$policy.delay_ms)
                }
                if($visible -gt $cutoff){continue}
            }
            foreach($field in $ref.exclude_fields){$row.PSObject.Properties.Remove($field)}
            $eligible++
            if($preview.Count -lt $MaxRowsPerFile){$preview.Add($row)}
            if($writer){$writer.WriteLine(($row | ConvertTo-Json -Depth 12 -Compress))}
            if(-not $writer -and $preview.Count -ge $MaxRowsPerFile){$stoppedEarly=$true;break}
        }
    }finally{if($writer){$writer.Dispose()}}
    $samples.Add([pscustomobject]@{path=$ref.path;source_class='synthetic_test_only';scanned_rows=$scanned;eligible_rows_seen=$eligible;preview_truncated=$stoppedEarly;rows=@($preview.ToArray())})
}
[pscustomobject]@{question_id=$binding.question_id;question=$binding.question;case=$case;view_mode=$(if($AsOf){'as_of_filtered'}else{'offline_sequence_preview'});as_of=$AsOf;source_class='synthetic_test_only';data=@($samples.ToArray());support_scope=$binding.input_support_scope;exact_node_fault_implemented=$false;real_dataset_ready=$false;answers_generated=0} | ConvertTo-Json -Depth 20
