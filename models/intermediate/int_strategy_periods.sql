{% set requested_start_date = var('start_date', none) %}
{% set requested_end_date = var('end_date', none) %}

with source_bounds as (
    select
        min(opened_at_utc) as source_min_opened_at_utc,
        max(opened_at_utc) as source_max_opened_at_utc
    from {{ ref('stg_binance__btc_usdt_1s') }}
),
requested_bounds as (
    select
        {% if requested_start_date %}
            cast('{{ requested_start_date }}' as date)
        {% else %}
            source_min_opened_at_utc::date
        {% endif %} as requested_start_date,
        {% if requested_end_date %}
            cast('{{ requested_end_date }}' as date)
        {% else %}
            source_max_opened_at_utc::date
        {% endif %} as requested_end_date,
        source_min_opened_at_utc,
        source_max_opened_at_utc
    from source_bounds
),
periods as (
    select
        trade_date::date as trade_date,
        entry_hour_utc,
        trade_date::date + entry_hour_utc * interval '1 hour' as expected_entry_at_utc,
        trade_date::date + entry_hour_utc * interval '1 hour' + interval '59 minutes 59 seconds'
            as expected_exit_at_utc,
        source_min_opened_at_utc,
        source_max_opened_at_utc
    from requested_bounds
    cross join lateral generate_series(
        requested_start_date,
        requested_end_date,
        interval '1 day'
    ) as dates(trade_date)
    cross join generate_series(0, 23) as hours(entry_hour_utc)
)
select
    'BTCUSDT'::text as symbol,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    source_min_opened_at_utc,
    source_max_opened_at_utc,
    expected_entry_at_utc >= source_min_opened_at_utc
        and expected_exit_at_utc <= source_max_opened_at_utc as is_within_source_window
from periods
