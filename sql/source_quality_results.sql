select
    sum(requested_period_count) as requested_periods,
    sum(outside_source_period_count) as outside_source_periods,
    sum(in_source_period_count) as in_source_periods,
    sum(eligible_trade_count) as eligible_trades,
    sum(excluded_in_source_period_count) as excluded_in_source_periods,
    sum(missing_entry_period_count) as missing_entry_periods,
    sum(missing_exit_period_count) as missing_exit_periods,
    sum(conflicting_entry_period_count) as conflicting_entry_periods,
    sum(conflicting_exit_period_count) as conflicting_exit_periods,
    sum(malformed_exit_period_count) as malformed_exit_periods,
    sum(deduplicated_entry_period_count) as deduplicated_entry_periods,
    sum(deduplicated_exit_period_count) as deduplicated_exit_periods
from analytics_marts.agg_hourly_strategy_summary;
