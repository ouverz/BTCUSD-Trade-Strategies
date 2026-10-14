select *
from {{ ref('fct_hourly_strategy_candidates') }}
where is_eligible_trade
  and (
      abs(drawdown - (equity / running_peak - 1)) > 1e-12
      or drawdown > 0
  )

