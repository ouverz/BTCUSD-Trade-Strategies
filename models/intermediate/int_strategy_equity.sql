with eligible_trades as (
    select
        symbol,
        trade_date,
        entry_hour_utc,
        entry_price,
        exit_price,
        trade_factor,
        trade_return,
        row_number() over (
            partition by symbol, entry_hour_utc
            order by trade_date
        ) as trade_sequence
    from {{ ref('int_strategy_trades') }}
    where is_eligible_trade
),
compounded as (
    select
        *,
        exp(sum(ln(trade_factor::double precision)) over (
            partition by symbol, entry_hour_utc
            order by trade_date
            rows between unbounded preceding and current row
        )) as equity
    from eligible_trades
),
peaks as (
    select
        *,
        greatest(1.0, max(equity) over (
            partition by symbol, entry_hour_utc
            order by trade_date
            rows between unbounded preceding and current row
        )) as running_peak
    from compounded
),
peak_dates as (
    select
        *,
        max(case when equity = running_peak and equity >= 1.0 then trade_date end) over (
            partition by symbol, entry_hour_utc
            order by trade_date
            rows between unbounded preceding and current row
        ) as running_peak_date
    from peaks
)
select
    symbol,
    trade_date,
    entry_hour_utc,
    trade_sequence,
    entry_price,
    exit_price,
    trade_factor,
    trade_return,
    equity,
    running_peak,
    running_peak_date,
    equity - 1 as cumulative_return,
    equity / running_peak - 1 as drawdown
from peak_dates

