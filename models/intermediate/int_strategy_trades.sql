with classified as (
    select
        *,
        entry_row_count = 0 as is_missing_entry,
        entry_price_version_count > 1 as has_conflicting_entry,
        entry_price is not null and entry_price <= 0 as has_nonpositive_entry,
        exit_row_count = 0 as is_missing_exit,
        invalid_exit_close_time_count > 0 as has_malformed_exit,
        exit_price_version_count > 1 as has_conflicting_exit,
        exit_price is not null and exit_price <= 0 as has_nonpositive_exit,
        case
            when not is_within_source_window then 'outside_source_window'
            when entry_row_count = 0 then 'missing_entry'
            when entry_price_version_count > 1 then 'conflicting_entry'
            when entry_price <= 0 then 'nonpositive_entry'
            when exit_row_count = 0 then 'missing_exit'
            when invalid_exit_close_time_count > 0 then 'malformed_exit_close_time'
            when exit_price_version_count > 1 then 'conflicting_exit'
            when exit_price <= 0 then 'nonpositive_exit'
            else 'eligible'
        end as trade_status
    from {{ ref('int_strategy_endpoint_observations') }}
),
trades as (
    select
        *,
        trade_status = 'eligible' as is_eligible_trade,
        case when trade_status <> 'eligible' then trade_status end as exclusion_reason
    from classified
)
select
    symbol,
    trade_date,
    entry_hour_utc,
    expected_entry_at_utc,
    expected_exit_at_utc,
    source_min_opened_at_utc,
    source_max_opened_at_utc,
    is_within_source_window,
    entry_price,
    exit_price,
    entry_row_count,
    entry_price_version_count,
    exit_row_count,
    exit_price_version_count,
    invalid_exit_close_time_count,
    is_missing_entry,
    has_conflicting_entry,
    has_nonpositive_entry,
    is_missing_exit,
    has_malformed_exit,
    has_conflicting_exit,
    has_nonpositive_exit,
    trade_status,
    exclusion_reason,
    is_eligible_trade,
    case when is_eligible_trade then exit_price / entry_price end as trade_factor,
    case when is_eligible_trade then exit_price / entry_price - 1 end as trade_return
from trades
