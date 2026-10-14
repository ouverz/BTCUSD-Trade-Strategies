do $$
begin
    if (
        select quality_status
        from raw.source_quality_audit
        order by load_id desc
        limit 1
    ) is distinct from 'passed' then
        raise exception 'Latest source-quality audit should pass for the CI fixture';
    end if;

    if (select count(*) from raw.binance_btc_usdt_1s) <> 96 then
        raise exception 'CI fixture should ingest 96 physical candle rows';
    end if;

    if (select count(*) from analytics_marts.fct_hourly_strategy_candidates) <> 48 then
        raise exception 'CI fixture should create 48 date-hour candidates';
    end if;

    if (
        select count(*)
        from analytics_marts.fct_hourly_strategy_candidates
        where is_eligible_trade
    ) <> 48 then
        raise exception 'All 48 synthetic date-hour candidates should be eligible';
    end if;

    if (select count(*) from analytics_marts.agg_hourly_strategy_summary) <> 24 then
        raise exception 'CI fixture should produce 24 hourly strategy summaries';
    end if;

    if (select count(*) from analytics_marts.rpt_assignment_answers) <> 2 then
        raise exception 'Assignment report should contain exactly two answers';
    end if;
end $$;
