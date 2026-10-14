with yearly_equity as (
    select
        symbol,
        trade_date,
        entry_hour_utc,
        extract(year from trade_date)::integer as trade_year,
        exp(sum(ln(trade_factor::double precision)) over (
            partition by symbol, entry_hour_utc, extract(year from trade_date)
            order by trade_date
            rows between unbounded preceding and current row
        )) as equity
    from {{ ref('fct_hourly_strategy_candidates') }}
    where is_eligible_trade
),
yearly_drawdown as (
    select
        *,
        equity / greatest(
            1.0,
            max(equity) over (
                partition by symbol, entry_hour_utc, trade_year
                order by trade_date
                rows between unbounded preceding and current row
            )
        ) - 1 as drawdown
    from yearly_equity
),
fact_metrics as (
    select
        symbol,
        trade_year,
        entry_hour_utc,
        (array_agg(equity order by trade_date desc))[1] as final_equity,
        min(drawdown) as maximum_drawdown
    from yearly_drawdown
    group by symbol, trade_year, entry_hour_utc
)
select
    summary.symbol,
    summary.trade_year,
    summary.entry_hour_utc,
    summary.final_equity as summary_final_equity,
    fact.final_equity as fact_final_equity,
    summary.maximum_drawdown as summary_maximum_drawdown,
    fact.maximum_drawdown as fact_maximum_drawdown
from {{ ref('agg_hourly_strategy_yearly') }} as summary
join fact_metrics as fact using (symbol, trade_year, entry_hour_utc)
where abs(summary.final_equity - fact.final_equity) > 1e-12
   or abs(summary.compounded_return - (fact.final_equity - 1)) > 1e-12
   or abs(summary.maximum_drawdown - fact.maximum_drawdown) > 1e-12
   or abs(summary.maximum_drawdown_magnitude + fact.maximum_drawdown) > 1e-12
