{{ config(materialized='table') }}

with entry_observations as (
    select
        periods.symbol,
        periods.trade_date,
        periods.entry_hour_utc,
        periods.expected_entry_at_utc,
        periods.expected_exit_at_utc,
        periods.source_min_opened_at_utc,
        periods.source_max_opened_at_utc,
        periods.is_within_source_window,
        count(candles.opened_at_utc)::bigint as entry_row_count,
        count(distinct candles.open_price)::bigint as entry_price_version_count,
        case
            when count(distinct candles.open_price) = 1
                then max(candles.open_price)
        end as entry_price
    from {{ ref('int_strategy_periods') }} as periods
    left join {{ ref('stg_binance__btc_usdt_1s') }} as candles
        on candles.opened_at_utc = periods.expected_entry_at_utc
    group by
        periods.symbol,
        periods.trade_date,
        periods.entry_hour_utc,
        periods.expected_entry_at_utc,
        periods.expected_exit_at_utc,
        periods.source_min_opened_at_utc,
        periods.source_max_opened_at_utc,
        periods.is_within_source_window
),
exit_observations as (
    select
        periods.symbol,
        periods.trade_date,
        periods.entry_hour_utc,
        count(candles.opened_at_utc)::bigint as exit_row_count,
        count(distinct candles.close_price) filter (
            where candles.closed_at_utc = candles.opened_at_utc + interval '999 milliseconds'
        )::bigint as exit_price_version_count,
        case
            when count(distinct candles.close_price) filter (
                where candles.closed_at_utc = candles.opened_at_utc + interval '999 milliseconds'
            ) = 1
             and count(*) filter (
                where candles.opened_at_utc is not null
                  and candles.closed_at_utc <> candles.opened_at_utc + interval '999 milliseconds'
             ) = 0
                then max(candles.close_price) filter (
                    where candles.closed_at_utc = candles.opened_at_utc + interval '999 milliseconds'
                )
        end as exit_price,
        count(*) filter (
            where candles.opened_at_utc is not null
              and candles.closed_at_utc <> candles.opened_at_utc + interval '999 milliseconds'
        )::bigint as invalid_exit_close_time_count
    from {{ ref('int_strategy_periods') }} as periods
    left join {{ ref('stg_binance__btc_usdt_1s') }} as candles
        on candles.opened_at_utc = periods.expected_exit_at_utc
    group by
        periods.symbol,
        periods.trade_date,
        periods.entry_hour_utc
)
select
    entries.symbol,
    entries.trade_date,
    entries.entry_hour_utc,
    entries.expected_entry_at_utc,
    entries.expected_exit_at_utc,
    entries.source_min_opened_at_utc,
    entries.source_max_opened_at_utc,
    entries.is_within_source_window,
    entries.entry_price,
    exits.exit_price,
    entries.entry_row_count,
    entries.entry_price_version_count,
    exits.exit_row_count,
    exits.exit_price_version_count,
    exits.invalid_exit_close_time_count
from entry_observations as entries
join exit_observations as exits
    using (symbol, trade_date, entry_hour_utc)
