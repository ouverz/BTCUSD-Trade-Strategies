with expected as (
    select
        *,
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
        end as expected_trade_status
    from {{ ref('int_strategy_trades') }}
)
select *
from expected
where is_missing_entry is distinct from (entry_row_count = 0)
   or has_conflicting_entry is distinct from (entry_price_version_count > 1)
   or has_nonpositive_entry is distinct from (entry_price is not null and entry_price <= 0)
   or is_missing_exit is distinct from (exit_row_count = 0)
   or has_malformed_exit is distinct from (invalid_exit_close_time_count > 0)
   or has_conflicting_exit is distinct from (exit_price_version_count > 1)
   or has_nonpositive_exit is distinct from (exit_price is not null and exit_price <= 0)
   or trade_status is distinct from expected_trade_status
   or is_eligible_trade is distinct from (expected_trade_status = 'eligible')
   or exclusion_reason is distinct from (
        case when expected_trade_status = 'eligible' then null else expected_trade_status end
   )
