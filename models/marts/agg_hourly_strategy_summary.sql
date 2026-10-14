with aggregated as (
    select
        symbol,
        entry_hour_utc,
        count(*)::bigint as requested_period_count,
        count(*) filter (where not is_within_source_window)::bigint as outside_source_period_count,
        count(*) filter (where is_within_source_window)::bigint as in_source_period_count,
        count(*) filter (where is_eligible_trade)::bigint as eligible_trade_count,
        count(*) filter (
            where is_within_source_window and not is_eligible_trade
        )::bigint as excluded_in_source_period_count,
        count(*) filter (
            where is_within_source_window and is_missing_entry
        )::bigint as missing_entry_period_count,
        count(*) filter (
            where is_within_source_window and is_missing_exit
        )::bigint as missing_exit_period_count,
        count(*) filter (
            where is_within_source_window and has_conflicting_entry
        )::bigint as conflicting_entry_period_count,
        count(*) filter (
            where is_within_source_window and has_conflicting_exit
        )::bigint as conflicting_exit_period_count,
        count(*) filter (
            where is_within_source_window and has_malformed_exit
        )::bigint as malformed_exit_period_count,
        count(*) filter (
            where is_within_source_window
              and entry_row_count > 1
              and entry_price_version_count = 1
        )::bigint as deduplicated_entry_period_count,
        count(*) filter (
            where is_within_source_window
              and exit_row_count > 1
              and exit_price_version_count = 1
              and not has_malformed_exit
        )::bigint as deduplicated_exit_period_count,
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
        max(trade_return::double precision) filter (where is_eligible_trade) as best_trade_return,
        (array_agg(equity order by trade_date desc) filter (where is_eligible_trade))[1]
            as final_equity,
        min(drawdown) filter (where is_eligible_trade) as maximum_drawdown,
        (array_agg(running_peak_date order by drawdown, trade_date)
            filter (where is_eligible_trade))[1] as maximum_drawdown_peak_date,
        (array_agg(trade_date order by drawdown, trade_date)
            filter (where is_eligible_trade))[1] as maximum_drawdown_trough_date
    from {{ ref('fct_hourly_strategy_candidates') }}
    group by symbol, entry_hour_utc
)
select
    symbol,
    entry_hour_utc,
    requested_period_count,
    outside_source_period_count,
    in_source_period_count,
    eligible_trade_count,
    excluded_in_source_period_count,
    eligible_trade_count::double precision / nullif(in_source_period_count, 0) as coverage_rate,
    missing_entry_period_count,
    missing_exit_period_count,
    conflicting_entry_period_count,
    conflicting_exit_period_count,
    malformed_exit_period_count,
    deduplicated_entry_period_count,
    deduplicated_exit_period_count,
    candidate_start_date,
    candidate_end_date,
    evaluated_start_date,
    evaluated_end_date,
    mean_trade_return,
    median_trade_return,
    trade_return_stddev,
    positive_trade_rate,
    worst_trade_return,
    best_trade_return,
    final_equity,
    final_equity - 1 as compounded_return,
    maximum_drawdown,
    -maximum_drawdown as maximum_drawdown_magnitude,
    maximum_drawdown_peak_date,
    maximum_drawdown_trough_date
from aggregated
