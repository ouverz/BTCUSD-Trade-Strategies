SELECT
entry_hour_utc,
in_source_period_count,
eligible_trade_count,
excluded_in_source_period_count,
round(coverage_rate::numeric * 100, 4) as coverage_pct,
evaluated_start_date,
evaluated_end_date
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;


--// let us investigate why candidate records were excluded
select
    entry_hour_utc,
    trade_status,
    count(*) as excluded_candidates,
    min(trade_date) as first_excluded_date,
    max(trade_date) as last_excluded_date
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
group by entry_hour_utc, trade_status
order by entry_hour_utc, trade_status;

-- // Let’s see the exact excluded date/hour rows next. Run:
select
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    trade_status,
    entry_row_count,
    exit_row_count,
    invalid_exit_close_time_count
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
order by trade_date, entry_hour_utc;

---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--
with ranked as (
	select
    trade_date,
    entry_hour_utc,
    trade_return * 100 as trade_return_pct,
    equity,
    drawdown,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank,
    row_number() over (
    	PARTITION BY entry_hour_utc
    	order by trade_return, trade_date
    ) as worst_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	'best' as group_type,
	best_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where best_rank <=5

union all

SELECT
	entry_hour_utc,
	'worst' as group_type,
	worst_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where worst_rank <=5

order by entry_hour_utc, group_type, rank_in_group;


---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--- Showing how removing the top 5 trades would significantly 
--- effect the total compounded return for hours 21 and 22.
--- Further showing that those trade had a significant factor in driving the return up.
with ranked as (
	select
    entry_hour_utc,
    trade_date,
    trade_factor::double precision as trade_factor,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	round((
		exp(sum(ln(trade_factor))) -1)::numeric * 100, 4) as full_compounded_return_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 1)) - 1)::numeric * 100, 4) as return_without_best_trade_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 5)) - 1)::numeric * 100, 4) as return_without_best_five_pct
FROM ranked
group by entry_hour_utc
order by entry_hour_utc;

/*
To look beyond just the best and worst trades, let’s compare the 5th, 25th, 50th, 75th, 
and 95th percentiles for hours 21 and 22. Those give us a better feel for the spread of ordinary outcomes

results:
entry-hour p05 p25 p50 pc75 p95
21	-0.9160	-0.2033	0.0331	0.2706	1.0281
22	-0.8523	-0.2310	0.0113	0.2577	1.0197

*/
select
    entry_hour_utc,
    round((percentile_cont(0.05) within group (order by trade_return))::numeric * 100, 4) as p05_pct,
    round((percentile_cont(0.25) within group (order by trade_return))::numeric * 100, 4) as p25_pct,
    round((percentile_cont(0.50) within group (order by trade_return))::numeric * 100, 4) as p50_pct,
    round((percentile_cont(0.75) within group (order by trade_return))::numeric * 100, 4) as p75_pct,
    round((percentile_cont(0.95) within group (order by trade_return))::numeric * 100, 4) as p95_pct
from analytics_marts.fct_hourly_strategy_trades
where is_eligible_trade
  and entry_hour_utc in (21, 22)
group by entry_hour_utc
order by entry_hour_utc;


/*
Let’s compare the all-history return winner (hour 22), its close contender (hour 21), and the smallest-drawdown winner (hour 10). The rank columns show where each placed among all 24 hours in that year:
*/
with yearly_ranks as (
    select
        trade_year,
        entry_hour_utc,
        rank() over (
            partition by trade_year
            order by compounded_return desc
        ) as return_rank,
        rank() over (
            partition by trade_year
            order by maximum_drawdown_magnitude
        ) as drawdown_rank
    from analytics_marts.agg_hourly_strategy_yearly
)
select
    y.trade_year,
    y.entry_hour_utc,
    y.eligible_trade_count,
    round(y.coverage_rate::numeric * 100, 3) as coverage_pct,
    y.evaluated_start_date,
    y.evaluated_end_date,
    round(y.compounded_return::numeric * 100, 3) as yearly_return_pct,
    r.return_rank,
    round(y.maximum_drawdown_magnitude::numeric * 100, 3) as yearly_max_drawdown_pct,
    r.drawdown_rank
from analytics_marts.agg_hourly_strategy_yearly y
join yearly_ranks r using (trade_year, entry_hour_utc)
where y.entry_hour_utc in (10, 21, 22)
order by y.trade_year, y.entry_hour_utc;


/*
Point 6 is about checking that the models use the same prices as the raw candles. Let’s trace three hour-22 trades: the best, the worst, and one closest to the median return. This query identifies those candidates; next we’ll look up their exact raw entry and exit candles.
*/
with hour_trades as (
    select
        trade_date,
        entry_hour_utc,
        expected_entry_at_utc,
        expected_exit_at_utc,
        entry_price,
        exit_price,
        trade_return,
        equity,
        drawdown
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
      and entry_hour_utc = 22
),
median_return as (
    select percentile_cont(0.5) within group (order by trade_return) as value
    from hour_trades
),
ranked as (
    select
        t.*,
        row_number() over (order by trade_return desc, trade_date) as best_rank,
        row_number() over (order by trade_return, trade_date) as worst_rank,
        row_number() over (
            order by abs(trade_return - m.value), trade_date
        ) as typical_rank
    from hour_trades t
    cross join median_return m
)
select
    'best' as sample_type,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4) as trade_return_pct,
    round(equity::numeric, 4) as equity,
    round(drawdown::numeric * 100, 4) as drawdown_pct
from ranked
where best_rank = 1

union all

select
    'worst',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where worst_rank = 1

union all

select
    'closest to median',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where typical_rank = 1

order by sample_type;


/*
Yes. We’ve traced the best, worst, and typical hour-22 trades to the fact model and confirmed how their returns are calculated. The remaining step for point 6 is to check that each trade’s entry open and exit close prices match the raw candles at the exact timestamps—and that the raw row counts and candle close times satisfy the duplicate policy.

*/
with samples as (
    select *
    from (values
        ('best',             date '2023-10-23', 22),
        ('closest to median',date '2021-11-19', 22),
        ('worst',            date '2021-05-12', 22)
    ) as s(sample_type, trade_date, entry_hour_utc)
)
select
    s.sample_type,
    f.trade_date,
    f.entry_hour_utc,
    f.expected_entry_at_utc,
    f.entry_price as fact_entry_price,
    entry_rows.row_count as raw_entry_rows,
    entry_rows.distinct_open_count as raw_distinct_open_prices,
    entry_rows.raw_open_price,
    f.expected_exit_at_utc,
    f.exit_price as fact_exit_price,
    exit_rows.row_count as raw_exit_rows,
    exit_rows.distinct_valid_close_count as raw_distinct_valid_close_prices,
    exit_rows.raw_close_price,
    exit_rows.malformed_close_rows
from samples s
join analytics_marts.fct_hourly_strategy_trades f
  on f.trade_date = s.trade_date
 and f.entry_hour_utc = s.entry_hour_utc
left join lateral (
    select
        count(*) as row_count,
        count(distinct open) as distinct_open_count,
        min(open) as raw_open_price
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_entry_at_utc
) entry_rows on true
left join lateral (
    select
        count(*) as row_count,
        count(distinct close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as distinct_valid_close_count,
        min(close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as raw_close_price,
        count(*) filter (
            where close_time <> open_time + interval '999 milliseconds'
        ) as malformed_close_rows
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_exit_at_utc
) exit_rows on true
order by s.trade_date;


SELECT
entry_hour_utc,
in_source_period_count,
eligible_trade_count,
excluded_in_source_period_count,
round(coverage_rate::numeric * 100, 4) as coverage_pct,
evaluated_start_date,
evaluated_end_date
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;


--// let us investigate why candidate records were excluded
select
    entry_hour_utc,
    trade_status,
    count(*) as excluded_candidates,
    min(trade_date) as first_excluded_date,
    max(trade_date) as last_excluded_date
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
group by entry_hour_utc, trade_status
order by entry_hour_utc, trade_status;

-- // Let’s see the exact excluded date/hour rows next. Run:
select
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    trade_status,
    entry_row_count,
    exit_row_count,
    invalid_exit_close_time_count
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
order by trade_date, entry_hour_utc;

---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--
with ranked as (
	select
    trade_date,
    entry_hour_utc,
    trade_return * 100 as trade_return_pct,
    equity,
    drawdown,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank,
    row_number() over (
    	PARTITION BY entry_hour_utc
    	order by trade_return, trade_date
    ) as worst_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	'best' as group_type,
	best_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where best_rank <=5

union all

SELECT
	entry_hour_utc,
	'worst' as group_type,
	worst_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where worst_rank <=5

order by entry_hour_utc, group_type, rank_in_group;


---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--- Showing how removing the top 5 trades would significantly 
--- effect the total compounded return for hours 21 and 22.
--- Further showing that those trade had a significant factor in driving the return up.
with ranked as (
	select
    entry_hour_utc,
    trade_date,
    trade_factor::double precision as trade_factor,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	round((
		exp(sum(ln(trade_factor))) -1)::numeric * 100, 4) as full_compounded_return_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 1)) - 1)::numeric * 100, 4) as return_without_best_trade_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 5)) - 1)::numeric * 100, 4) as return_without_best_five_pct
FROM ranked
group by entry_hour_utc
order by entry_hour_utc;

/*
To look beyond just the best and worst trades, let’s compare the 5th, 25th, 50th, 75th, 
and 95th percentiles for hours 21 and 22. Those give us a better feel for the spread of ordinary outcomes

results:
entry-hour p05 p25 p50 pc75 p95
21	-0.9160	-0.2033	0.0331	0.2706	1.0281
22	-0.8523	-0.2310	0.0113	0.2577	1.0197

*/
select
    entry_hour_utc,
    round((percentile_cont(0.05) within group (order by trade_return))::numeric * 100, 4) as p05_pct,
    round((percentile_cont(0.25) within group (order by trade_return))::numeric * 100, 4) as p25_pct,
    round((percentile_cont(0.50) within group (order by trade_return))::numeric * 100, 4) as p50_pct,
    round((percentile_cont(0.75) within group (order by trade_return))::numeric * 100, 4) as p75_pct,
    round((percentile_cont(0.95) within group (order by trade_return))::numeric * 100, 4) as p95_pct
from analytics_marts.fct_hourly_strategy_trades
where is_eligible_trade
  and entry_hour_utc in (21, 22)
group by entry_hour_utc
order by entry_hour_utc;


/*
Let’s compare the all-history return winner (hour 22), its close contender (hour 21), and the smallest-drawdown winner (hour 10). The rank columns show where each placed among all 24 hours in that year:
*/
with yearly_ranks as (
    select
        trade_year,
        entry_hour_utc,
        rank() over (
            partition by trade_year
            order by compounded_return desc
        ) as return_rank,
        rank() over (
            partition by trade_year
            order by maximum_drawdown_magnitude
        ) as drawdown_rank
    from analytics_marts.agg_hourly_strategy_yearly
)
select
    y.trade_year,
    y.entry_hour_utc,
    y.eligible_trade_count,
    round(y.coverage_rate::numeric * 100, 3) as coverage_pct,
    y.evaluated_start_date,
    y.evaluated_end_date,
    round(y.compounded_return::numeric * 100, 3) as yearly_return_pct,
    r.return_rank,
    round(y.maximum_drawdown_magnitude::numeric * 100, 3) as yearly_max_drawdown_pct,
    r.drawdown_rank
from analytics_marts.agg_hourly_strategy_yearly y
join yearly_ranks r using (trade_year, entry_hour_utc)
where y.entry_hour_utc in (10, 21, 22)
order by y.trade_year, y.entry_hour_utc;


/*
Point 6 is about checking that the models use the same prices as the raw candles. Let’s trace three hour-22 trades: the best, the worst, and one closest to the median return. This query identifies those candidates; next we’ll look up their exact raw entry and exit candles.
*/
with hour_trades as (
    select
        trade_date,
        entry_hour_utc,
        expected_entry_at_utc,
        expected_exit_at_utc,
        entry_price,
        exit_price,
        trade_return,
        equity,
        drawdown
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
      and entry_hour_utc = 22
),
median_return as (
    select percentile_cont(0.5) within group (order by trade_return) as value
    from hour_trades
),
ranked as (
    select
        t.*,
        row_number() over (order by trade_return desc, trade_date) as best_rank,
        row_number() over (order by trade_return, trade_date) as worst_rank,
        row_number() over (
            order by abs(trade_return - m.value), trade_date
        ) as typical_rank
    from hour_trades t
    cross join median_return m
)
select
    'best' as sample_type,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4) as trade_return_pct,
    round(equity::numeric, 4) as equity,
    round(drawdown::numeric * 100, 4) as drawdown_pct
from ranked
where best_rank = 1

union all

select
    'worst',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where worst_rank = 1

union all

select
    'closest to median',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where typical_rank = 1

order by sample_type;


/*
Yes. We’ve traced the best, worst, and typical hour-22 trades to the fact model and confirmed how their returns are calculated. The remaining step for point 6 is to check that each trade’s entry open and exit close prices match the raw candles at the exact timestamps—and that the raw row counts and candle close times satisfy the duplicate policy.

*/
with samples as (
    select *
    from (values
        ('best',             date '2023-10-23', 22),
        ('closest to median',date '2021-11-19', 22),
        ('worst',            date '2021-05-12', 22)
    ) as s(sample_type, trade_date, entry_hour_utc)
)
select
    s.sample_type,
    f.trade_date,
    f.entry_hour_utc,
    f.expected_entry_at_utc,
    f.entry_price as fact_entry_price,
    entry_rows.row_count as raw_entry_rows,
    entry_rows.distinct_open_count as raw_distinct_open_prices,
    entry_rows.raw_open_price,
    f.expected_exit_at_utc,
    f.exit_price as fact_exit_price,
    exit_rows.row_count as raw_exit_rows,
    exit_rows.distinct_valid_close_count as raw_distinct_valid_close_prices,
    exit_rows.raw_close_price,
    exit_rows.malformed_close_rows
from samples s
join analytics_marts.fct_hourly_strategy_trades f
  on f.trade_date = s.trade_date
 and f.entry_hour_utc = s.entry_hour_utc
left join lateral (
    select
        count(*) as row_count,
        count(distinct open) as distinct_open_count,
        min(open) as raw_open_price
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_entry_at_utc
) entry_rows on true
left join lateral (
    select
        count(*) as row_count,
        count(distinct close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as distinct_valid_close_count,
        min(close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as raw_close_price,
        count(*) filter (
            where close_time <> open_time + interval '999 milliseconds'
        ) as malformed_close_rows
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_exit_at_utc
) exit_rows on true
order by s.trade_date;

SELECT
entry_hour_utc,
in_source_period_count,
eligible_trade_count,
excluded_in_source_period_count,
round(coverage_rate::numeric * 100, 4) as coverage_pct,
evaluated_start_date,
evaluated_end_date
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;


--// let us investigate why candidate records were excluded
select
    entry_hour_utc,
    trade_status,
    count(*) as excluded_candidates,
    min(trade_date) as first_excluded_date,
    max(trade_date) as last_excluded_date
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
group by entry_hour_utc, trade_status
order by entry_hour_utc, trade_status;

-- // Let’s see the exact excluded date/hour rows next. Run:
select
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    trade_status,
    entry_row_count,
    exit_row_count,
    invalid_exit_close_time_count
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
order by trade_date, entry_hour_utc;

---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--
with ranked as (
	select
    trade_date,
    entry_hour_utc,
    trade_return * 100 as trade_return_pct,
    equity,
    drawdown,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank,
    row_number() over (
    	PARTITION BY entry_hour_utc
    	order by trade_return, trade_date
    ) as worst_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	'best' as group_type,
	best_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where best_rank <=5

union all

SELECT
	entry_hour_utc,
	'worst' as group_type,
	worst_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where worst_rank <=5

order by entry_hour_utc, group_type, rank_in_group;


---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--- Showing how removing the top 5 trades would significantly 
--- effect the total compounded return for hours 21 and 22.
--- Further showing that those trade had a significant factor in driving the return up.
with ranked as (
	select
    entry_hour_utc,
    trade_date,
    trade_factor::double precision as trade_factor,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	round((
		exp(sum(ln(trade_factor))) -1)::numeric * 100, 4) as full_compounded_return_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 1)) - 1)::numeric * 100, 4) as return_without_best_trade_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 5)) - 1)::numeric * 100, 4) as return_without_best_five_pct
FROM ranked
group by entry_hour_utc
order by entry_hour_utc;

/*
To look beyond just the best and worst trades, let’s compare the 5th, 25th, 50th, 75th, 
and 95th percentiles for hours 21 and 22. Those give us a better feel for the spread of ordinary outcomes

results:
entry-hour p05 p25 p50 pc75 p95
21	-0.9160	-0.2033	0.0331	0.2706	1.0281
22	-0.8523	-0.2310	0.0113	0.2577	1.0197

*/
select
    entry_hour_utc,
    round((percentile_cont(0.05) within group (order by trade_return))::numeric * 100, 4) as p05_pct,
    round((percentile_cont(0.25) within group (order by trade_return))::numeric * 100, 4) as p25_pct,
    round((percentile_cont(0.50) within group (order by trade_return))::numeric * 100, 4) as p50_pct,
    round((percentile_cont(0.75) within group (order by trade_return))::numeric * 100, 4) as p75_pct,
    round((percentile_cont(0.95) within group (order by trade_return))::numeric * 100, 4) as p95_pct
from analytics_marts.fct_hourly_strategy_trades
where is_eligible_trade
  and entry_hour_utc in (21, 22)
group by entry_hour_utc
order by entry_hour_utc;


/*
Let’s compare the all-history return winner (hour 22), its close contender (hour 21), and the smallest-drawdown winner (hour 10). The rank columns show where each placed among all 24 hours in that year:
*/
with yearly_ranks as (
    select
        trade_year,
        entry_hour_utc,
        rank() over (
            partition by trade_year
            order by compounded_return desc
        ) as return_rank,
        rank() over (
            partition by trade_year
            order by maximum_drawdown_magnitude
        ) as drawdown_rank
    from analytics_marts.agg_hourly_strategy_yearly
)
select
    y.trade_year,
    y.entry_hour_utc,
    y.eligible_trade_count,
    round(y.coverage_rate::numeric * 100, 3) as coverage_pct,
    y.evaluated_start_date,
    y.evaluated_end_date,
    round(y.compounded_return::numeric * 100, 3) as yearly_return_pct,
    r.return_rank,
    round(y.maximum_drawdown_magnitude::numeric * 100, 3) as yearly_max_drawdown_pct,
    r.drawdown_rank
from analytics_marts.agg_hourly_strategy_yearly y
join yearly_ranks r using (trade_year, entry_hour_utc)
where y.entry_hour_utc in (10, 21, 22)
order by y.trade_year, y.entry_hour_utc;


/*
Point 6 is about checking that the models use the same prices as the raw candles. Let’s trace three hour-22 trades: the best, the worst, and one closest to the median return. This query identifies those candidates; next we’ll look up their exact raw entry and exit candles.
*/
with hour_trades as (
    select
        trade_date,
        entry_hour_utc,
        expected_entry_at_utc,
        expected_exit_at_utc,
        entry_price,
        exit_price,
        trade_return,
        equity,
        drawdown
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
      and entry_hour_utc = 22
),
median_return as (
    select percentile_cont(0.5) within group (order by trade_return) as value
    from hour_trades
),
ranked as (
    select
        t.*,
        row_number() over (order by trade_return desc, trade_date) as best_rank,
        row_number() over (order by trade_return, trade_date) as worst_rank,
        row_number() over (
            order by abs(trade_return - m.value), trade_date
        ) as typical_rank
    from hour_trades t
    cross join median_return m
)
select
    'best' as sample_type,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4) as trade_return_pct,
    round(equity::numeric, 4) as equity,
    round(drawdown::numeric * 100, 4) as drawdown_pct
from ranked
where best_rank = 1

union all

select
    'worst',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where worst_rank = 1

union all

select
    'closest to median',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where typical_rank = 1

order by sample_type;


/*
Yes. We’ve traced the best, worst, and typical hour-22 trades to the fact model and confirmed how their returns are calculated. The remaining step for point 6 is to check that each trade’s entry open and exit close prices match the raw candles at the exact timestamps—and that the raw row counts and candle close times satisfy the duplicate policy.

*/
with samples as (
    select *
    from (values
        ('best',             date '2023-10-23', 22),
        ('closest to median',date '2021-11-19', 22),
        ('worst',            date '2021-05-12', 22)
    ) as s(sample_type, trade_date, entry_hour_utc)
)
select
    s.sample_type,
    f.trade_date,
    f.entry_hour_utc,
    f.expected_entry_at_utc,
    f.entry_price as fact_entry_price,
    entry_rows.row_count as raw_entry_rows,
    entry_rows.distinct_open_count as raw_distinct_open_prices,
    entry_rows.raw_open_price,
    f.expected_exit_at_utc,
    f.exit_price as fact_exit_price,
    exit_rows.row_count as raw_exit_rows,
    exit_rows.distinct_valid_close_count as raw_distinct_valid_close_prices,
    exit_rows.raw_close_price,
    exit_rows.malformed_close_rows
from samples s
join analytics_marts.fct_hourly_strategy_trades f
  on f.trade_date = s.trade_date
 and f.entry_hour_utc = s.entry_hour_utc
left join lateral (
    select
        count(*) as row_count,
        count(distinct open) as distinct_open_count,
        min(open) as raw_open_price
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_entry_at_utc
) entry_rows on true
left join lateral (
    select
        count(*) as row_count,
        count(distinct close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as distinct_valid_close_count,
        min(close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as raw_close_price,
        count(*) filter (
            where close_time <> open_time + interval '999 milliseconds'
        ) as malformed_close_rows
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_exit_at_utc
) exit_rows on true
order by s.trade_date;


SELECT
entry_hour_utc,
in_source_period_count,
eligible_trade_count,
excluded_in_source_period_count,
round(coverage_rate::numeric * 100, 4) as coverage_pct,
evaluated_start_date,
evaluated_end_date
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;


--// let us investigate why candidate records were excluded
select
    entry_hour_utc,
    trade_status,
    count(*) as excluded_candidates,
    min(trade_date) as first_excluded_date,
    max(trade_date) as last_excluded_date
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
group by entry_hour_utc, trade_status
order by entry_hour_utc, trade_status;

-- // Let’s see the exact excluded date/hour rows next. Run:
select
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    trade_status,
    entry_row_count,
    exit_row_count,
    invalid_exit_close_time_count
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window
  and not is_eligible_trade
order by trade_date, entry_hour_utc;

---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--
with ranked as (
	select
    trade_date,
    entry_hour_utc,
    trade_return * 100 as trade_return_pct,
    equity,
    drawdown,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank,
    row_number() over (
    	PARTITION BY entry_hour_utc
    	order by trade_return, trade_date
    ) as worst_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	'best' as group_type,
	best_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where best_rank <=5

union all

SELECT
	entry_hour_utc,
	'worst' as group_type,
	worst_rank as rank_in_group,
	trade_date,
	round(trade_return_pct::numeric, 4) as trade_return_pct,
	round(equity::numeric, 4) as equity,
	round(drawdown::numeric * 100, 4) as drawdown_pct
FROM ranked
where worst_rank <=5

order by entry_hour_utc, group_type, rank_in_group;


---- check hour 22,21 
---- to see the best / worst top / bottom five individual trades
SELECT
entry_hour_utc,
eligible_trade_count,
round(mean_trade_return::numeric * 100,4) as mean_trade_pct,
round(median_trade_return::numeric * 100,4) as median_trade_pct,
round(trade_return_stddev::numeric * 100,4) as trade_return_stddev_pct,
round(best_trade_return::numeric * 100,4) as best_trade_return_pct,
round(worst_trade_return::numeric * 100,4) as worst_trade_return_pct,
round(positive_trade_rate::numeric * 100,4) as positive_trade_rate_pct,
round(compounded_return::numeric * 100,4) as compounded_return_pct
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

--- Showing how removing the top 5 trades would significantly 
--- effect the total compounded return for hours 21 and 22.
--- Further showing that those trade had a significant factor in driving the return up.
with ranked as (
	select
    entry_hour_utc,
    trade_date,
    trade_factor::double precision as trade_factor,
    row_number() over (
		partition by entry_hour_utc
		order by trade_return desc, trade_date    
    ) as best_rank
	from analytics_marts.fct_hourly_strategy_trades
	where is_eligible_trade
	and entry_hour_utc in (21,22)
)
SELECT
	entry_hour_utc,
	round((
		exp(sum(ln(trade_factor))) -1)::numeric * 100, 4) as full_compounded_return_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 1)) - 1)::numeric * 100, 4) as return_without_best_trade_pct,
	round((
		exp(sum(ln(trade_factor)) filter (where best_rank > 5)) - 1)::numeric * 100, 4) as return_without_best_five_pct
FROM ranked
group by entry_hour_utc
order by entry_hour_utc;

/*
To look beyond just the best and worst trades, let’s compare the 5th, 25th, 50th, 75th, 
and 95th percentiles for hours 21 and 22. Those give us a better feel for the spread of ordinary outcomes

results:
entry-hour p05 p25 p50 pc75 p95
21	-0.9160	-0.2033	0.0331	0.2706	1.0281
22	-0.8523	-0.2310	0.0113	0.2577	1.0197

*/
select
    entry_hour_utc,
    round((percentile_cont(0.05) within group (order by trade_return))::numeric * 100, 4) as p05_pct,
    round((percentile_cont(0.25) within group (order by trade_return))::numeric * 100, 4) as p25_pct,
    round((percentile_cont(0.50) within group (order by trade_return))::numeric * 100, 4) as p50_pct,
    round((percentile_cont(0.75) within group (order by trade_return))::numeric * 100, 4) as p75_pct,
    round((percentile_cont(0.95) within group (order by trade_return))::numeric * 100, 4) as p95_pct
from analytics_marts.fct_hourly_strategy_trades
where is_eligible_trade
  and entry_hour_utc in (21, 22)
group by entry_hour_utc
order by entry_hour_utc;


/*
Let’s compare the all-history return winner (hour 22), its close contender (hour 21), and the smallest-drawdown winner (hour 10). The rank columns show where each placed among all 24 hours in that year:
*/
with yearly_ranks as (
    select
        trade_year,
        entry_hour_utc,
        rank() over (
            partition by trade_year
            order by compounded_return desc
        ) as return_rank,
        rank() over (
            partition by trade_year
            order by maximum_drawdown_magnitude
        ) as drawdown_rank
    from analytics_marts.agg_hourly_strategy_yearly
)
select
    y.trade_year,
    y.entry_hour_utc,
    y.eligible_trade_count,
    round(y.coverage_rate::numeric * 100, 3) as coverage_pct,
    y.evaluated_start_date,
    y.evaluated_end_date,
    round(y.compounded_return::numeric * 100, 3) as yearly_return_pct,
    r.return_rank,
    round(y.maximum_drawdown_magnitude::numeric * 100, 3) as yearly_max_drawdown_pct,
    r.drawdown_rank
from analytics_marts.agg_hourly_strategy_yearly y
join yearly_ranks r using (trade_year, entry_hour_utc)
where y.entry_hour_utc in (10, 21, 22)
order by y.trade_year, y.entry_hour_utc;


/*
Point 6 is about checking that the models use the same prices as the raw candles. Let’s trace three hour-22 trades: the best, the worst, and one closest to the median return. This query identifies those candidates; next we’ll look up their exact raw entry and exit candles.
*/
with hour_trades as (
    select
        trade_date,
        entry_hour_utc,
        expected_entry_at_utc,
        expected_exit_at_utc,
        entry_price,
        exit_price,
        trade_return,
        equity,
        drawdown
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
      and entry_hour_utc = 22
),
median_return as (
    select percentile_cont(0.5) within group (order by trade_return) as value
    from hour_trades
),
ranked as (
    select
        t.*,
        row_number() over (order by trade_return desc, trade_date) as best_rank,
        row_number() over (order by trade_return, trade_date) as worst_rank,
        row_number() over (
            order by abs(trade_return - m.value), trade_date
        ) as typical_rank
    from hour_trades t
    cross join median_return m
)
select
    'best' as sample_type,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4) as trade_return_pct,
    round(equity::numeric, 4) as equity,
    round(drawdown::numeric * 100, 4) as drawdown_pct
from ranked
where best_rank = 1

union all

select
    'worst',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where worst_rank = 1

union all

select
    'closest to median',
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    entry_price,
    exit_price,
    round(trade_return::numeric * 100, 4),
    round(equity::numeric, 4),
    round(drawdown::numeric * 100, 4)
from ranked
where typical_rank = 1

order by sample_type;


/*
Yes. We’ve traced the best, worst, and typical hour-22 trades to the fact model and confirmed how their returns are calculated. The remaining step for point 6 is to check that each trade’s entry open and exit close prices match the raw candles at the exact timestamps—and that the raw row counts and candle close times satisfy the duplicate policy.

*/
with samples as (
    select *
    from (values
        ('best',             date '2023-10-23', 22),
        ('closest to median',date '2021-11-19', 22),
        ('worst',            date '2021-05-12', 22)
    ) as s(sample_type, trade_date, entry_hour_utc)
)
select
    s.sample_type,
    f.trade_date,
    f.entry_hour_utc,
    f.expected_entry_at_utc,
    f.entry_price as fact_entry_price,
    entry_rows.row_count as raw_entry_rows,
    entry_rows.distinct_open_count as raw_distinct_open_prices,
    entry_rows.raw_open_price,
    f.expected_exit_at_utc,
    f.exit_price as fact_exit_price,
    exit_rows.row_count as raw_exit_rows,
    exit_rows.distinct_valid_close_count as raw_distinct_valid_close_prices,
    exit_rows.raw_close_price,
    exit_rows.malformed_close_rows
from samples s
join analytics_marts.fct_hourly_strategy_trades f
  on f.trade_date = s.trade_date
 and f.entry_hour_utc = s.entry_hour_utc
left join lateral (
    select
        count(*) as row_count,
        count(distinct open) as distinct_open_count,
        min(open) as raw_open_price
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_entry_at_utc
) entry_rows on true
left join lateral (
    select
        count(*) as row_count,
        count(distinct close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as distinct_valid_close_count,
        min(close) filter (
            where close_time = open_time + interval '999 milliseconds'
        ) as raw_close_price,
        count(*) filter (
            where close_time <> open_time + interval '999 milliseconds'
        ) as malformed_close_rows
    from raw.binance_btc_usdt_1s
    where open_time = f.expected_exit_at_utc
) exit_rows on true
order by s.trade_date;

/*
For point 8, we’ve already tried removing the five best trades for hours 21 and 22; that reversed their ranking. That was a one-sided check. Let’s see whether the overall top hours change if we remove both the five best and five worst trades from every hour. This is only a sensitivity test—not a claim that those trades should be discarded.
*/
with ranked_trades as (
    select
        entry_hour_utc,
        trade_date,
        trade_factor::double precision as trade_factor,
        row_number() over (
            partition by entry_hour_utc
            order by trade_return desc, trade_date
        ) as best_rank,
        row_number() over (
            partition by entry_hour_utc
            order by trade_return, trade_date
        ) as worst_rank
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
),
scenarios(scenario, trim_both_tails) as (
    values
        ('full sample', false),
        ('exclude five best and worst', true)
),
scenario_returns as (
    select
        s.scenario,
        t.entry_hour_utc,
        count(*) as retained_trades,
        exp(sum(ln(t.trade_factor))) - 1 as compounded_return
    from ranked_trades t
    cross join scenarios s
    where not s.trim_both_tails
       or (t.best_rank > 5 and t.worst_rank > 5)
    group by s.scenario, t.entry_hour_utc
),
ranked_scenarios as (
    select
        *,
        rank() over (
            partition by scenario
            order by compounded_return desc
        ) as return_rank
    from scenario_returns
)
select
    scenario,
    return_rank,
    entry_hour_utc,
    retained_trades,
    round(compounded_return::numeric * 100, 3) as compounded_return_pct
from ranked_scenarios
where return_rank <= 3
order by scenario, return_rank, entry_hour_utc;
/* RESULT ABOVE ANALYSIS:
This is a strong sign that the full-history ranking is sensitive to extreme trades:

- In the full sample, hour 22 leads hour 21: 42.519% vs. 40.492%.
- After trimming five trades from each tail, hour 21 leads: 45.053% vs. 33.463%.
- The trimmed return rises for hour 21 because its worst five trades hurt more than its best five helped. For hour 22, the reverse is true: removing its strongest five trades reduces the compounded result substantially.

Those changes are percentage-point differences in the ending compounded return—not a direct additive attribution of each trade’s contribution. And trimming is an artificial sensitivity test, not a better estimate: we should not discard valid trades just because they hurt or help the result.

So point 8’s takeaway is: hour 22 is the full-sample return winner, but that ranking is not robust to reasonable changes in how extreme valid trades are treated. It’s better described as a historical winner whose lead is tail-sensitive, not as a reliably superior hour.
*/
