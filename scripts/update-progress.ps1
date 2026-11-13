param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'deliverables'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$entries=New-Object System.Collections.Generic.List[object]
foreach($file in (Get-ChildItem -LiteralPath (Join-Path $root 'openspec\changes') -Filter tasks.md -Recurse)) {
    $text=Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    $tasks=[regex]::Matches($text,'(?m)^- \[([ xX])\] (\d+\.\d+)\s+(.+)$')
    $done=@($tasks | Where-Object { $_.Groups[1].Value -match '[xX]' }).Count
    $archive=$file.FullName -match '[\\/]archive[\\/]'
    $name=$file.Directory.Name
    $entries.Add([pscustomobject]@{change=$name;archived=$archive;completed_tasks=$done;total_tasks=$tasks.Count;implementation_status=$(if($done -eq $tasks.Count -and $tasks.Count -gt 0){'complete'}elseif($done){'in_progress'}else{'planned'});task_file=$file.FullName.Substring($root.Length+1).Replace('\','/')})
}
$utf8=New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$md=New-Object System.Text.StringBuilder
[void]$md.AppendLine('# OpenSpec任务进度')
[void]$md.AppendLine('')
[void]$md.AppendLine('从tasks.md勾选状态生成；工件齐全不等于实现完成。无数据生成/数据库/教师调用证据时不得升档。')
[void]$md.AppendLine('')
[void]$md.AppendLine('|变更|状态|完成/总任务|是否归档|')
[void]$md.AppendLine('|---|---|---:|---|')
foreach($e in ($entries | Sort-Object archived,change)) { [void]$md.AppendLine("|$($e.change)|$($e.implementation_status)|$($e.completed_tasks)/$($e.total_tasks)|$($e.archived)|") }
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory '任务进度.md'),$md.ToString(),$utf8)
[System.IO.File]::WriteAllText((Join-Path $OutputDirectory 'task-progress.json'),(ConvertTo-Json -InputObject @($entries.ToArray()) -Depth 6),$utf8)
$entries | Select-Object change,implementation_status,completed_tasks,total_tasks,archived | Format-Table -AutoSize
