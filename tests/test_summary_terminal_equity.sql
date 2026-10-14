with terminal_equity as (
    select distinct on (symbol, entry_hour_utc)
        symbol,
        entry_hour_utc,
        equity
    from {{ ref('fct_hourly_strategy_candidates') }}
    where is_eligible_trade
    order by symbol, entry_hour_utc, trade_date desc
)
select summary.*
from {{ ref('agg_hourly_strategy_summary') }} as summary
join terminal_equity using (symbol, entry_hour_utc)
where abs(summary.final_equity - terminal_equity.equity) > 1e-12
   or abs(summary.compounded_return - (terminal_equity.equity - 1)) > 1e-12
