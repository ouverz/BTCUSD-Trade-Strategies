with return_winner as (
    select
        *,
        row_number() over (
            order by compounded_return desc, entry_hour_utc
        ) as result_rank
    from {{ ref('agg_hourly_strategy_summary') }}
),
loss_winner as (
    select
        *,
        row_number() over (
            order by maximum_drawdown_magnitude, compounded_return desc, entry_hour_utc
        ) as result_rank
    from {{ ref('agg_hourly_strategy_summary') }}
),
expected as (
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
        2::integer,
        'smallest maximum-loss magnitude'::text,
        entry_hour_utc,
        maximum_drawdown_magnitude * 100,
        evaluated_start_date,
        evaluated_end_date,
        eligible_trade_count,
        excluded_in_source_period_count
    from loss_winner
    where result_rank = 1
),
actual_minus_expected as (
    select * from {{ ref('rpt_assignment_answers') }}
    except all
    select * from expected
),
expected_minus_actual as (
    select * from expected
    except all
    select * from {{ ref('rpt_assignment_answers') }}
)
select 'unexpected_answer' as failure_type, *
from actual_minus_expected
union all
select 'missing_answer' as failure_type, *
from expected_minus_actual

