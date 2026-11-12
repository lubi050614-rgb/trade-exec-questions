-- 仅提供只读查询模板，未运行。使用ClickHouse typed query parameters传入日期。
-- start_date/end_date是候选窗口，先确认实际交易日；不预设2026-11-12已有完整收盘数据。
-- 不在这里按未来五日完整率重新选股。先冻结起点前股票池，再审计并保留质量损失。

-- 1. 日历核验：期望得到恰好五个选定交易日，而非五个自然日。
SELECT DISTINCT trade_date
FROM rq_trading_calendar_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
ORDER BY trade_date;

-- 2. 原始源逐日覆盖。股票池筛选应额外JOIN调用方冻结的manifest，不虚构库内已有manifest表。
SELECT 'quote' AS source, trade_date, uniqExact(tuple(market,security_code)) AS symbols,
       count() AS rows, min(ts) AS first_ts, max(ts) AS last_ts
FROM wind_quote_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY trade_date
UNION ALL
SELECT 'order', trade_date, uniqExact(tuple(market,security_code)), count(), min(ts), max(ts)
FROM wind_order_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY trade_date
UNION ALL
SELECT 'trade', trade_date, uniqExact(tuple(market,security_code)), count(), min(ts), max(ts)
FROM wind_trade_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY trade_date
ORDER BY trade_date,source;

-- 3. 分股票/日/通道的本地序列重复提示。不是跨源全局唯一性声明。
-- exchange_seq的重置、空值语义、分段范围仍需供应商说明，不能仅用本查询认定丢包。
SELECT market,security_code,trade_date,channel_id,count() AS rows,
       uniqExact(exchange_seq) AS distinct_seq,
       min(exchange_seq) AS seq_min,max(exchange_seq) AS seq_max
FROM wind_order_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY market,security_code,trade_date,channel_id
ORDER BY trade_date,market,security_code,channel_id;

-- 4. 直接读取已有重建质量，避免把“有逐笔字段”等同于“重建完整”。
SELECT market,security_code,trade_date,window_start,window_end,
       order_rows,trade_rows,quote_rows,ambiguous_groups,unresolved_refs,
       gap_count,reconstruction_policy,confidence
FROM wind_book_quality_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
ORDER BY trade_date,market,security_code,window_start;

-- 5. 30分钟聚合特征质量字段的实际组合分布；不预设quality_status枚举。
SELECT quality_status,semantics_confirmed,price_divisor_known,
       volume_multiplier_known,trade_semantics_ready,order_semantics_ready,
       trade_side_ready,order_side_ready,feed_completeness_checked,
       source_slice_complete,count() AS windows,
       min(quote_coverage_ratio) AS coverage_min,max(quote_age_ms) AS age_max_ms
FROM qinml_l2_features_30m_v1
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY quality_status,semantics_confirmed,price_divisor_known,
         volume_multiplier_known,trade_semantics_ready,order_semantics_ready,
         trade_side_ready,order_side_ready,feed_completeness_checked,source_slice_complete;

-- 6. 分钟线零量、缺值与异常提示。缺失整分钟需要与适用品种时段日历逐格LEFT JOIN再检测，
-- 不能用固定240行覆盖全部竞价/尾段/停牌情形；量额单位尚未核验前不输出价格基准。
SELECT market,security_code,trade_date,count() AS rows,uniqExact(bar_end) AS unique_bar_ends,
       countIf(isNull(volume)) AS null_volume_rows,
       countIf(volume=0) AS zero_volume_rows,
       countIf(high<low) AS invalid_ohlc_rows,
       sum(volume) AS volume_sum,sum(total_turnover) AS turnover_sum
FROM rq_stock_bar_1m_local
WHERE trade_date BETWEEN {start_date:Date} AND {end_date:Date}
GROUP BY market,security_code,trade_date
ORDER BY trade_date,market,security_code;
