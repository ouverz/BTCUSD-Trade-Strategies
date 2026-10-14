with fact_drawdown as (
    select
        symbol,
        entry_hour_utc,
        min(drawdown) as maximum_drawdown,
        (array_agg(trade_date order by drawdown, trade_date))[1]
            as maximum_drawdown_trough_date,
        (array_agg(running_peak_date order by drawdown, trade_date))[1]
            as maximum_drawdown_peak_date
    from {{ ref('fct_hourly_strategy_trades') }}
    where is_eligible_trade
    group by symbol, entry_hour_utc
)
select
    summary.symbol,
    summary.entry_hour_utc,
    summary.maximum_drawdown as summary_maximum_drawdown,
    fact.maximum_drawdown as fact_maximum_drawdown,
    summary.maximum_drawdown_peak_date as summary_peak_date,
    fact.maximum_drawdown_peak_date as fact_peak_date,
    summary.maximum_drawdown_trough_date as summary_trough_date,
    fact.maximum_drawdown_trough_date as fact_trough_date
from {{ ref('agg_hourly_strategy_summary') }} as summary
join fact_drawdown as fact using (symbol, entry_hour_utc)
where abs(summary.maximum_drawdown - fact.maximum_drawdown) > 1e-12
   or summary.maximum_drawdown_peak_date is distinct from fact.maximum_drawdown_peak_date
   or summary.maximum_drawdown_trough_date is distinct from fact.maximum_drawdown_trough_date
   or abs(summary.maximum_drawdown_magnitude + fact.maximum_drawdown) > 1e-12
