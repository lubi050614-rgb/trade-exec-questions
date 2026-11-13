param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\input-generation.json'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data\generated\execution-inputs-v1'),
    [switch]$Overwrite
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath | ConvertFrom-Json
$allowed=@('schema_version','generator_version','seed','symbol_count','dates','calendar_kind','timezone','quote_interval_minutes','minutes_per_day','market','price_tick_minor','cash_minor_per_major','volume_unit','amount_unit','output_namespace','source_class','allow_real_market_claims','export_answers')
foreach($p in $config.PSObject.Properties){if($p.Name -notin $allowed){throw "Unknown configuration field: $($p.Name)"}}
if($config.source_class -ne 'synthetic_test_only' -or $config.export_answers -ne $false -or $config.allow_real_market_claims -ne $false){throw 'Only synthetic input generation without answers is supported'}
if($config.market -ne 'SYN' -or $config.output_namespace -ne 'synthetic' -or $config.timezone -ne 'Asia/Shanghai'){throw 'Unsupported namespace/market/timezone'}
if($config.calendar_kind -ne 'test_only_explicit_dates' -or $config.schema_version -ne '1.0'){throw 'Unsupported calendar or configuration schema'}
if($config.price_tick_minor -ne 1 -or $config.cash_minor_per_major -ne 100 -or $config.volume_unit -ne 'shares' -or $config.amount_unit -ne 'CNY_major'){throw 'Unsupported or ambiguous units'}
if($config.symbol_count -lt 10 -or $config.symbol_count -gt 1000 -or $config.seed -lt 1 -or $config.minutes_per_day -ne 240){throw 'Require 10..1000 symbols, positive seed and 240 test minutes; question bindings require at least 200 symbols'}
if($config.quote_interval_minutes -lt 1 -or 120%$config.quote_interval_minutes -ne 0){throw 'Quote interval must divide each 120-minute test session'}
$dates=@($config.dates)
if($dates.Count -ne 5 -or @($dates | Select-Object -Unique).Count -ne 5){throw 'Exactly five unique explicit test dates required'}
$last=[datetime]::MinValue
foreach($d in $dates){$parsed=[datetime]::ParseExact($d,'yyyy-MM-dd',[cultureinfo]::InvariantCulture);if($parsed -le $last){throw 'Dates must be increasing'};$last=$parsed}
$out=[System.IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $out){
    if(-not $Overwrite){throw 'Output exists. Choose a new directory or use -Overwrite for an existing generated dataset.'}
    $old=Join-Path $out 'manifest.json'
    if(-not(Test-Path -LiteralPath $old)){throw 'Refusing to overwrite a directory without this generator manifest'}
    $prior=Get-Content -Raw -Encoding UTF8 -LiteralPath $old | ConvertFrom-Json
    if($prior.generator_version -ne $config.generator_version){throw 'Refusing to overwrite another generator version'}
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$utf8=New-Object System.Text.UTF8Encoding($false)
if(-not ('TradeInputs.Generator' -as [type])){
    Add-Type -Path (Join-Path $root 'src\input-fixtures\FixtureGenerator.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
}
Write-Output 'Generating synthetic market, business and auxiliary input files...'
$catalogJson=[TradeInputs.Generator]::Run($out,[int]$config.seed,[int]$config.symbol_count,[string[]]$dates,[int]$config.quote_interval_minutes)
$catalog=$catalogJson | ConvertFrom-Json
$files=New-Object System.Collections.Generic.List[object]
foreach($entry in $catalog){
    if($entry.path.StartsWith('_internal/')){continue}
    $full=Join-Path $out $entry.path
    $table=if($entry.path.StartsWith('synthetic/market/')){[System.IO.Path]::GetFileNameWithoutExtension($entry.path)}else{$null}
    $timeField='available_at';$delay=0;$availability='explicit_available_at';$dateTimeSuffix=$null;$constantAvailable=$null
    if($table){
        $delay=2
        $timeField=switch($table){
            'rq_stock_bar_1m_local' {'bar_end'}
            'rq_stock_bar_1d_local' {'trade_date'}
            'rq_instrument_versions_local' {'createtime'}
            'rq_financial_pit_local' {'info_date'}
            'rq_adjustment_local' {'effective_date'}
            'qinml_l2_features_30m_v1' {'window_end'}
            'qinml_l2_features_30m_batches_v1' {'event_time'}
            'wind_book_quality_local' {'window_end'}
            default {if('ts' -in $entry.columns){'ts'}else{'trade_date'}}
        }
        $availability='synthetic_declared_visibility_not_vendor_receive_time'
        if($timeField -in @('trade_date','info_date','effective_date')){
            $dateTimeSuffix=if($table -in @('rq_stock_bar_1d_local','rq_factor_value_local')){'T16:00:00.000+08:00'}elseif($timeField -eq 'info_date'){'T23:59:59.000+08:00'}else{'T08:00:00.000+08:00'}
        }
        if($table -eq 'rq_trading_calendar_local'){$constantAvailable=([datetime]::ParseExact($dates[0],'yyyy-MM-dd',[cultureinfo]::InvariantCulture)).AddDays(-1).ToString('yyyy-MM-dd')+'T08:00:00.000+08:00'}
    } elseif($entry.path -like 'synthetic/rules/*' -or $entry.path -in @('synthetic/protocol/capabilities.jsonl','synthetic/protocol/error-codes.jsonl','synthetic/system/build-profile.jsonl','synthetic/system/fpga-vectors.jsonl','synthetic/system/telemetry.jsonl','synthetic/business/scenarios.jsonl')){
        $availability='static_test_configuration_known_before_window'
        $constantAvailable=([datetime]::ParseExact($dates[0],'yyyy-MM-dd',[cultureinfo]::InvariantCulture)).AddDays(-1).ToString('yyyy-MM-dd')+'T08:00:00.000+08:00'
    }
    $files.Add([pscustomobject][ordered]@{path=$entry.path;namespace='synthetic';source_class='synthetic_test_only';table_schema=$table;rows=[long]$entry.rows;columns=@($entry.columns);sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $full).Length;availability=[ordered]@{field=$timeField;delay_ms=$delay;date_time_suffix=$dateTimeSuffix;constant_available_at=$constantAvailable;policy=$availability};fidelity=$(if($table -like 'wind_*'){'sampled_reset_blocks_not_complete_l3'}elseif($entry.path -like 'synthetic/system/*'){'simulated_no_hardware_evidence'}else{'synthetic_engineering_fixture'})})
}
$manifest=[ordered]@{
    schema_version='1.0';generator_version=$config.generator_version;source_class='synthetic_test_only';seed=$config.seed;config_hash=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
    source_code_hash=(Get-FileHash -LiteralPath (Join-Path $root 'src\input-fixtures\FixtureGenerator.cs') -Algorithm SHA256).Hash.ToLowerInvariant()
    actual_n_symbols=[int]$config.symbol_count;actual_n_days=$dates.Count;dates=$dates;symbols=@(1..$config.symbol_count | ForEach-Object {'SYN'+$_.ToString('D6')})
    universe_policy='frozen_before_window; synthetic IDs only';calendar_kind=$config.calendar_kind;timezone=$config.timezone
    units=[ordered]@{raw_wind_price='integer_ticks; divisor=100';checkpoint_price='integer_ticks; divisor=100';bar_price='CNY_major';raw_amount='CNY_minor';bar_total_turnover='CNY_major';volume='shares';cash='integer_CNY_minor'}
    synthetic_feature_definitions=[ordered]@{mid_price_last='last sampled quote midpoint divided by 100';quote_age_ms='window_end minus last sampled quote ts';quote_coverage_ratio='fraction of minute starts with sampled quotes, not vendor-valid-seconds coverage';semantics_confirmed='synthetic definitions only, not verification of vendor codes'}
    limitations=@('No real ClickHouse rows or own broker records supplied','Five dates are an explicit test calendar, not an exchange-calendar verification','Raw order/trade/quote feeds are sampled blocks, not complete L3; gaps and partial coverage are intentional','Vendor enum meanings are synthetic test dialects, not verified Wind codes','Telemetry and protocol fixtures are not hardware measurements or broker certification','Special assets and PCF are separate synthetic instruments, not inferred from stocks','No answers or expected-output labels are generated')
    special_asset_universe=[ordered]@{derivatives=@('FUT_A','FUT_B','OPT_C','OPT_P');overseas_crypto=@('SYNBTC_LINEAR@SYN_X','SYNBTC_LINEAR@SYN_Y');funds=@('SYN_ETF_200');restricted_share_batches=@('SYN000001/test_restricted_batch')}
    files=@($files.ToArray());real_source_status='pending';real_calibration_ready=$false;answers_generated=0
}
[System.IO.File]::WriteAllText((Join-Path $out 'manifest.json'),($manifest | ConvertTo-Json -Depth 12),$utf8)
[System.IO.File]::WriteAllText((Join-Path $out 'config.json'),($config | ConvertTo-Json -Depth 8),$utf8)
$readme=@'
# 合成题目输入数据

这是synthetic/test_only工程输入，不是真实ClickHouse抽取，不包含题目答案。
manifest.json给出实际股票数、日期、单位、文件哈希和可见时间策略。synthetic/market沿用已有表字段，但值全部由本生成器产生；不能导入生产表后伪称真实数据。
synthetic/business是自身业务夹具。observations包含重复和乱序的交付，请按available_at构建本地观测，按event_id/execution_id幂等处理；不能将文件物理行序假定为全局时间序。
synthetic/special提供独立资产的输入。missing_evidence变体有刻意缺失字段；不得静默填成真实证据。
_internal仅供生成器内部校验，不进入逐题索引、读取器或公开数据包。内部只有校验摘要，不是可直接给模型的标准答案。
读取某题请使用scripts/read-question-input.ps1及问题输入索引。真实数据接入仍待提供脱敏导出或已授权连接。
'@
[System.IO.File]::WriteAllText((Join-Path $out 'README.md'),$readme,$utf8)
Write-Output "Generated $($files.Count) public files; symbols=$($config.symbol_count), days=$($dates.Count); no answers."
