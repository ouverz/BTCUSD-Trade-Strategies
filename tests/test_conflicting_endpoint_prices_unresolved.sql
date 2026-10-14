select *
from {{ ref('int_strategy_trades') }}
where (has_conflicting_entry and entry_price is not null)
   or (has_conflicting_exit and exit_price is not null)
   or (has_malformed_exit and exit_price is not null)
