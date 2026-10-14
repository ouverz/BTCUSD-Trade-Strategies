with summary_checks as (
    select
        'all_history'::text as summary_type,
        symbol,
        entry_hour_utc,
        in_source_period_count,
        coverage_rate,
        candidate_start_date,
        candidate_end_date,
        eligible_trade_count,
        evaluated_start_date,
        evaluated_end_date,
        mean_trade_return,
        median_trade_return,
        trade_return_stddev,
        positive_trade_rate,
        worst_trade_return,
        best_trade_return,
        final_equity,
        compounded_return,
        maximum_drawdown,
        maximum_drawdown_magnitude,
        maximum_drawdown_trough_date
    from {{ ref('agg_hourly_strategy_summary') }}

    union all

    select
        'yearly'::text,
        symbol,
        entry_hour_utc,
        in_source_period_count,
        coverage_rate,
        candidate_start_date,
        candidate_end_date,
        eligible_trade_count,
        evaluated_start_date,
        evaluated_end_date,
        mean_trade_return,
        median_trade_return,
        trade_return_stddev,
        positive_trade_rate,
        worst_trade_return,
        best_trade_return,
        final_equity,
        compounded_return,
        maximum_drawdown,
        maximum_drawdown_magnitude,
        null::date as maximum_drawdown_trough_date
    from {{ ref('agg_hourly_strategy_yearly') }}
), invalid_empty_rows as (
    select *
    from summary_checks
    where eligible_trade_count = 0
      and (
          (in_source_period_count = 0 and coverage_rate is not null)
          or (in_source_period_count > 0 and coverage_rate is distinct from 0::double precision)
          or (in_source_period_count = 0 and (candidate_start_date is not null or candidate_end_date is not null))
          or evaluated_start_date is not null
          or evaluated_end_date is not null
          or mean_trade_return is not null
          or median_trade_return is not null
          or trade_return_stddev is not null
          or positive_trade_rate is not null
          or worst_trade_return is not null
          or best_trade_return is not null
          or final_equity is not null
          or compounded_return is not null
          or maximum_drawdown is not null
          or maximum_drawdown_magnitude is not null
          or maximum_drawdown_trough_date is not null
      )
)
select * from invalid_empty_rows
