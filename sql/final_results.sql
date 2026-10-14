select
    question,
    entry_hour_utc,
    round(metric_pct::numeric, 6) as metric_pct,
    evaluated_start_date,
    evaluated_end_date,
    valid_trade_days,
    excluded_incomplete_periods
from analytics_marts.rpt_assignment_answers
order by answer_order;

