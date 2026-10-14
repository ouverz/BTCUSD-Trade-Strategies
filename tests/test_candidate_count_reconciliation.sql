select *
from {{ ref('agg_hourly_strategy_summary') }}
where requested_period_count
        <> outside_source_period_count + eligible_trade_count + excluded_in_source_period_count
   or in_source_period_count
        <> eligible_trade_count + excluded_in_source_period_count
   or coverage_rate < 0
   or coverage_rate > 1
