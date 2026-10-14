with checks as (
    select
        *,
        lag(equity, 1, 1.0) over (
            partition by symbol, entry_hour_utc
            order by trade_date
        ) * trade_factor as expected_equity
    from {{ ref('fct_hourly_strategy_candidates') }}
    where is_eligible_trade
)
select *
from checks
where abs(equity - expected_equity) > 1e-10

