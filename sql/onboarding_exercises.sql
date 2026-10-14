-- Onboarding lab. Run against PostgreSQL after a successful dbt build.
-- Example: docker compose exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/onboarding_exercises.sql

\echo '1. Final assignment answers (percentages are percentage points)'
select * from analytics_marts.rpt_assignment_answers order by answer_order;

\echo '2. Compare all 24 UTC-hour alternatives and data coverage'
select entry_hour_utc, requested_period_count, in_source_period_count,
       eligible_trade_count, excluded_in_source_period_count,
       round(coverage_rate::numeric * 100, 3) as coverage_pct,
       evaluated_start_date, evaluated_end_date,
       round(compounded_return::numeric * 100, 3) as compounded_return_pct,
       round(maximum_drawdown_magnitude::numeric * 100, 3) as max_drawdown_pct,
       maximum_drawdown_peak_date, maximum_drawdown_trough_date
from analytics_marts.agg_hourly_strategy_summary
order by entry_hour_utc;

\echo '3. Yearly return, drawdown, coverage, and trade counts by hour'
select trade_year, entry_hour_utc, eligible_trade_count,
       excluded_in_source_period_count,
       round(coverage_rate::numeric * 100, 3) as coverage_pct,
       round(compounded_return::numeric * 100, 3) as compounded_return_pct,
       round(maximum_drawdown_magnitude::numeric * 100, 3) as max_drawdown_pct
from analytics_marts.agg_hourly_strategy_yearly
order by entry_hour_utc, trade_year;

\echo '4. Trace candidates for baseline-winning hours in a short sample'
select trade_date, entry_hour_utc, expected_entry_at_utc, expected_exit_at_utc,
       entry_row_count, entry_price_version_count, exit_row_count,
       exit_price_version_count, invalid_exit_close_time_count,
       entry_price, exit_price, trade_status, exclusion_reason,
       trade_return, equity, running_peak, drawdown
from analytics_marts.fct_hourly_strategy_trades
where entry_hour_utc in (10, 22)
  and trade_date between date '2024-01-01' and date '2024-01-10'
order by entry_hour_utc, trade_date;

\echo '5. Explain why in-source candidates were excluded'
select entry_hour_utc, trade_status, count(*) as candidate_count
from analytics_marts.fct_hourly_strategy_trades
where is_within_source_window and not is_eligible_trade
group by entry_hour_utc, trade_status
order by entry_hour_utc, candidate_count desc, trade_status;

\echo '6. Inspect exact raw endpoints for a chosen date/hour (edit the date/hour)'
select open_time, close_time, open, close, volume
from raw.binance_btc_usdt_1s
where open_time in (timestamp '2024-01-01 22:00:00', timestamp '2024-01-01 22:59:59')
order by open_time, close;

\echo '7. Check compounding and drawdown invariants for eligible candidates'
with recomputed as (
    select symbol, trade_date, entry_hour_utc, trade_factor, equity,
           running_peak, drawdown,
           lag(equity, 1, 1.0) over (
               partition by symbol, entry_hour_utc order by trade_date
           ) as prior_equity
    from analytics_marts.fct_hourly_strategy_trades
    where is_eligible_trade
)
select count(*) filter (
           where abs(equity - prior_equity * trade_factor) > 1e-10
       ) as equity_transition_mismatches,
       count(*) filter (
           where abs(drawdown - (equity / running_peak - 1)) > 1e-10
       ) as drawdown_mismatches
from recomputed;
