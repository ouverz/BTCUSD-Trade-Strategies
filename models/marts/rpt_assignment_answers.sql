with return_winner as (
    select
        *,
        row_number() over (order by compounded_return desc, entry_hour_utc) as result_rank
    from {{ ref('agg_hourly_strategy_summary') }}
),
loss_winner as (
    select
        *,
        row_number() over (
            order by maximum_drawdown_magnitude, compounded_return desc, entry_hour_utc
        ) as result_rank
    from {{ ref('agg_hourly_strategy_summary') }}
)
select
    1::integer as answer_order,
    'greatest compounded return'::text as question,
    entry_hour_utc,
    compounded_return * 100 as metric_pct,
    evaluated_start_date,
    evaluated_end_date,
    eligible_trade_count as valid_trade_days,
    excluded_in_source_period_count as excluded_incomplete_periods
from return_winner
where result_rank = 1

union all

select
    2::integer as answer_order,
    'smallest maximum-loss magnitude'::text as question,
    entry_hour_utc,
    maximum_drawdown_magnitude * 100 as metric_pct,
    evaluated_start_date,
    evaluated_end_date,
    eligible_trade_count as valid_trade_days,
    excluded_in_source_period_count as excluded_incomplete_periods
from loss_winner
where result_rank = 1
