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
$catalog=Get-Content -Raw -Encoding UTF8 (Join-Path $root 'case-manifest.json') | ConvertFrom-Json
$caseAllowed=@{};foreach($entry in $catalog.files){$caseAllowed[$entry.path]=$entry.sha256}
if(-not $caseAllowed.ContainsKey($binding.case_file) -or $caseAllowed[$binding.case_file] -ne $binding.case_sha256 -or $case.question_id -ne $QuestionId -or $case.node_key -ne $binding.node_key){throw 'Question case is not registered for this question'}
$hasher=[Security.Cryptography.SHA256]::Create()
try{$questionHash=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($binding.question)))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
if($case.question_sha256 -ne $questionHash){throw 'Question text changed after case adaptation'}
$scenarioInputs=@(foreach($scenario in $case.scenario_files){
    $scenarioPath=Resolve-SafeInput $scenario.path
    if(-not $caseAllowed.ContainsKey($scenario.path) -or $caseAllowed[$scenario.path] -ne $scenario.sha256 -or (Get-FileHash -LiteralPath $scenarioPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $scenario.sha256){throw 'Scenario checksum or registration mismatch'}
    $value=Get-Content -Raw -Encoding UTF8 $scenarioPath | ConvertFrom-Json
    if($value.node_key -ne $binding.node_key -or $value.variant -ne $scenario.variant){throw 'Scenario belongs to another node or variant'}
    $value
})
$case | Add-Member -NotePropertyName scenario_inputs -NotePropertyValue @($scenarioInputs)
$case | Add-Member -NotePropertyName case_view_mode -NotePropertyValue 'offline_reasoning_timelines_not_live_feature_snapshot'
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
            if($row.variant -and $row.variant -notin $binding.filters.special_variants){continue}
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
if($ExportDirectory){
    foreach($relative in ((@($binding.case_file)+@($case.scenario_files.path)) | Where-Object {$_})){
        $destination=Join-Path $exportRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        [IO.File]::Copy((Resolve-SafeInput $relative),$destination,$true)
    }
    [IO.File]::WriteAllText((Join-Path $exportRoot 'question.json'),($binding | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
}
[pscustomobject]@{question_id=$binding.question_id;question=$binding.question;case=$case;view_mode=$(if($AsOf){'as_of_filtered_shared_rows_with_offline_reasoning_case'}else{'offline_sequence_preview'});as_of=$AsOf;source_class='synthetic_test_only';data=@($samples.ToArray());support_scope=$binding.input_support_scope;exact_node_fault_implemented=$binding.exact_node_fault_implemented;real_dataset_ready=$false;answers_generated=0} | ConvertTo-Json -Depth 30
