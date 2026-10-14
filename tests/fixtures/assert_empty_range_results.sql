do $$
begin
    if (select count(*) from analytics_marts.fct_hourly_strategy_candidates) <> 48 then
        raise exception 'Outside-source range should retain all 48 requested candidates';
    end if;

    if exists (
        select 1
        from analytics_marts.fct_hourly_strategy_candidates
        where is_within_source_window or is_eligible_trade
    ) then
        raise exception 'Outside-source candidates must not be marked in-source or eligible';
    end if;

    if (select count(*) from analytics_marts.agg_hourly_strategy_summary) <> 24 then
        raise exception 'Outside-source range should retain all 24 hourly summaries';
    end if;

    if exists (
        select 1
        from analytics_marts.agg_hourly_strategy_summary
        where eligible_trade_count <> 0
           or in_source_period_count <> 0
           or coverage_rate is not null
           or evaluated_start_date is not null
           or evaluated_end_date is not null
           or final_equity is not null
           or compounded_return is not null
           or maximum_drawdown_magnitude is not null
    ) then
        raise exception 'Outside-source summaries should preserve counts and leave undefined metrics null';
    end if;

    if exists (select 1 from analytics_marts.rpt_assignment_answers) then
        raise exception 'No assignment winners should be returned when no strategies have eligible trades';
    end if;
end $$;
