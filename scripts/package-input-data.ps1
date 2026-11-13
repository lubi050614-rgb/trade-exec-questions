param(
    [string]$DataDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'data\generated\execution-inputs-v1'),
    [string]$ArchivePath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'deliverables\执行输入数据_200标的5日.zip')
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$dataRoot=[System.IO.Path]::GetFullPath($DataDirectory).TrimEnd('\','/')
$manifest=Get-Content -Raw -Encoding UTF8 (Join-Path $dataRoot 'manifest.json') | ConvertFrom-Json
$validation=Get-Content -Raw -Encoding UTF8 (Join-Path $dataRoot 'validation.json') | ConvertFrom-Json
if($validation.result -ne 'passed'){throw 'Input dataset must pass validation before packaging'}
$catalog=Get-Content -Raw -Encoding UTF8 (Join-Path $dataRoot 'case-manifest.json') | ConvertFrom-Json
$precise=Get-Content -Raw -Encoding UTF8 (Join-Path $dataRoot 'precise-validation.json') | ConvertFrom-Json
if($precise.result -ne 'passed' -or $precise.case_manifest_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $dataRoot 'case-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()){throw 'Precise cases must pass validation before packaging'}
foreach($file in $catalog.files){if($file.path -notmatch '^cases/(nodes/P\d{2}-S\d{2}/[a-z_]+|questions/P\d{2}-S\d{2}-Q\d{2})\.json$' -or (Get-FileHash -LiteralPath (Join-Path $dataRoot $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'Invalid or stale precise case catalog'}}
$paths=@($manifest.files.path)+@('manifest.json','config.json','README.md','validation.json','question-inputs.jsonl','case-manifest.json','precise-validation.json')+@($catalog.files.path)
$stream=New-Object System.IO.FileStream([System.IO.Path]::GetFullPath($ArchivePath),[System.IO.FileMode]::Create)
$zip=New-Object System.IO.Compression.ZipArchive($stream,[System.IO.Compression.ZipArchiveMode]::Create)
try{
    foreach($path in ($paths | Sort-Object -Unique)){
        if($path -match '_internal|\.\.' -or [System.IO.Path]::IsPathRooted($path)){throw 'Unsafe or internal file in archive'}
        $entry=$zip.CreateEntry($path.Replace('\','/'),[System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[datetimeoffset]'2026-11-01T00:00:00+00:00'
        $inputStream=[System.IO.File]::OpenRead((Join-Path $dataRoot $path))
        $entryStream=$entry.Open()
        try{$inputStream.CopyTo($entryStream)}finally{$entryStream.Dispose();$inputStream.Dispose()}
    }
}finally{$zip.Dispose();$stream.Dispose()}
Write-Output "Input archive contains $($paths.Count) public entries; internal validator data excluded."
