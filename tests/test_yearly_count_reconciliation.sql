select *
from {{ ref('agg_hourly_strategy_yearly') }}
where requested_period_count
        <> outside_source_period_count + eligible_trade_count + excluded_in_source_period_count
   or in_source_period_count
        <> eligible_trade_count + excluded_in_source_period_count
   or coverage_rate < 0
   or coverage_rate > 1
   or candidate_start_date > candidate_end_date
   or evaluated_start_date > evaluated_end_date
   or extract(year from candidate_start_date)::integer <> trade_year
   or extract(year from candidate_end_date)::integer <> trade_year
