select *
from {{ ref('fct_hourly_strategy_candidates') }}
where not is_eligible_trade
  and (
      trade_factor is not null
      or trade_return is not null
      or trade_sequence is not null
      or equity is not null
      or running_peak is not null
      or cumulative_return is not null
      or drawdown is not null
  )

