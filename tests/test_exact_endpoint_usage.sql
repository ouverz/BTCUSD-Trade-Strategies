select *
from {{ ref('int_strategy_trades') }}
where is_eligible_trade is distinct from (
    is_within_source_window
    and entry_row_count > 0
    and entry_price_version_count = 1
    and entry_price > 0
    and exit_row_count > 0
    and exit_price_version_count = 1
    and exit_price > 0
    and invalid_exit_close_time_count = 0
)

