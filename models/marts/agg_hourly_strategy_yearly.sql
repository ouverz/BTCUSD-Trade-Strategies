with eligible as (
    select
        *,
        extract(year from trade_date)::integer as trade_year,
        exp(sum(ln(trade_factor::double precision)) over (
            partition by symbol, entry_hour_utc, extract(year from trade_date)
            order by trade_date
            rows between unbounded preceding and current row
        )) as yearly_equity
    from {{ ref('fct_hourly_strategy_candidates') }}
    where is_eligible_trade
),
yearly_peaks as (
    select
        *,
        greatest(1.0, max(yearly_equity) over (
            partition by symbol, entry_hour_utc, trade_year
            order by trade_date
            rows between unbounded preceding and current row
        )) as yearly_running_peak
    from eligible
),
yearly_performance as (
    select
        *,
        yearly_equity / yearly_running_peak - 1 as yearly_drawdown
    from yearly_peaks
),
candidate_aggregates as (
    select
        symbol,
        extract(year from trade_date)::integer as trade_year,
        entry_hour_utc,
        count(*)::bigint as requested_period_count,
        count(*) filter (where not is_within_source_window)::bigint as outside_source_period_count,
        count(*) filter (where is_within_source_window)::bigint as in_source_period_count,
        count(*) filter (where is_eligible_trade)::bigint as eligible_trade_count,
        count(*) filter (
            where is_within_source_window and not is_eligible_trade
        )::bigint as excluded_in_source_period_count,
        min(trade_date) filter (where is_within_source_window) as candidate_start_date,
        max(trade_date) filter (where is_within_source_window) as candidate_end_date,
        min(trade_date) filter (where is_eligible_trade) as evaluated_start_date,
        max(trade_date) filter (where is_eligible_trade) as evaluated_end_date,
        avg(trade_return::double precision) filter (where is_eligible_trade) as mean_trade_return,
        percentile_cont(0.5) within group (order by trade_return::double precision)
            filter (where is_eligible_trade) as median_trade_return,
        stddev_samp(trade_return::double precision) filter (where is_eligible_trade)
            as trade_return_stddev,
        count(*) filter (where is_eligible_trade and trade_return > 0)::double precision
            / nullif(count(*) filter (where is_eligible_trade), 0) as positive_trade_rate,
        min(trade_return::double precision) filter (where is_eligible_trade) as worst_trade_return,
        max(trade_return::double precision) filter (where is_eligible_trade) as best_trade_return
    from {{ ref('fct_hourly_strategy_candidates') }}
    group by symbol, extract(year from trade_date), entry_hour_utc
),
performance_aggregates as (
    select
        symbol,
        trade_year,
        entry_hour_utc,
        (array_agg(yearly_equity order by trade_date desc))[1] as final_equity,
        min(yearly_drawdown) as maximum_drawdown
    from yearly_performance
    group by symbol, trade_year, entry_hour_utc
)
select
    candidates.symbol,
    candidates.trade_year,
    candidates.entry_hour_utc,
    candidates.requested_period_count,
    candidates.outside_source_period_count,
    candidates.in_source_period_count,
    candidates.eligible_trade_count,
    candidates.excluded_in_source_period_count,
    candidates.eligible_trade_count::double precision
        / nullif(candidates.in_source_period_count, 0) as coverage_rate,
    candidates.candidate_start_date,
    candidates.candidate_end_date,
    candidates.evaluated_start_date,
    candidates.evaluated_end_date,
    candidates.mean_trade_return,
    candidates.median_trade_return,
    candidates.trade_return_stddev,
    candidates.positive_trade_rate,
    candidates.worst_trade_return,
    candidates.best_trade_return,
    performance.final_equity,
    performance.final_equity - 1 as compounded_return,
    performance.maximum_drawdown,
    -performance.maximum_drawdown as maximum_drawdown_magnitude
from candidate_aggregates as candidates
left join performance_aggregates as performance
    using (symbol, trade_year, entry_hour_utc)
