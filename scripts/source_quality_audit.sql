with latest_load as (
    select load_id, row_count, minimum_open_time, maximum_open_time
    from raw.load_audit
    order by load_id desc
    limit 1
),
source_metrics as (
    select
        count(*)::bigint as raw_row_count,
        min(open_time) as minimum_open_time,
        max(open_time) as maximum_open_time,
        count(*) filter (
            where open <= 0
               or high <= 0
               or low <= 0
               or close <= 0
               or high < greatest(open, close, low)
               or low > least(open, close, high)
               or volume < 0
               or quote_asset_volume < 0
               or number_of_trades < 0
               or taker_buy_base_asset_volume < 0
               or taker_buy_base_asset_volume > volume
               or taker_buy_quote_asset_volume < 0
               or taker_buy_quote_asset_volume > quote_asset_volume
        )::bigint as hard_violation_row_count,
        count(*) filter (
            where close_time <> open_time + interval '999 milliseconds'
        )::bigint as malformed_close_time_row_count
    from raw.binance_btc_usdt_1s
),
audit_row as (
    select
        latest_load.load_id,
        current_timestamp as checked_at,
        source_metrics.raw_row_count,
        source_metrics.minimum_open_time,
        source_metrics.maximum_open_time,
        source_metrics.hard_violation_row_count,
        source_metrics.malformed_close_time_row_count,
        source_metrics.raw_row_count = latest_load.row_count
            and source_metrics.minimum_open_time is not distinct from latest_load.minimum_open_time
            and source_metrics.maximum_open_time is not distinct from latest_load.maximum_open_time
            as load_metadata_matches
    from latest_load
    cross join source_metrics
)
insert into raw.source_quality_audit (
    load_id,
    checked_at,
    raw_row_count,
    minimum_open_time,
    maximum_open_time,
    hard_violation_row_count,
    malformed_close_time_row_count,
    load_metadata_matches,
    quality_status
)
select
    load_id,
    checked_at,
    raw_row_count,
    minimum_open_time,
    maximum_open_time,
    hard_violation_row_count,
    malformed_close_time_row_count,
    load_metadata_matches,
    case
        when raw_row_count > 0
         and hard_violation_row_count = 0
         and load_metadata_matches then 'passed'
        else 'failed'
    end
from audit_row
on conflict (load_id) do update set
    checked_at = excluded.checked_at,
    raw_row_count = excluded.raw_row_count,
    minimum_open_time = excluded.minimum_open_time,
    maximum_open_time = excluded.maximum_open_time,
    hard_violation_row_count = excluded.hard_violation_row_count,
    malformed_close_time_row_count = excluded.malformed_close_time_row_count,
    load_metadata_matches = excluded.load_metadata_matches,
    quality_status = excluded.quality_status;

select
    load_id,
    checked_at,
    raw_row_count,
    minimum_open_time,
    maximum_open_time,
    hard_violation_row_count,
    malformed_close_time_row_count,
    load_metadata_matches,
    quality_status
from raw.source_quality_audit
order by load_id desc
limit 1;

do $$
begin
    if coalesce((
        select quality_status
        from raw.source_quality_audit
        order by load_id desc
        limit 1
    ), 'missing') <> 'passed' then
        raise exception 'Source quality audit failed; see raw.source_quality_audit for the recorded checks.';
    end if;
end $$;
