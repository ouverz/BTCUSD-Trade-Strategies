\i scripts/load_data.sql

insert into raw.binance_btc_usdt_1s (
    open_time,
    open,
    high,
    low,
    close,
    volume,
    close_time,
    quote_asset_volume,
    number_of_trades,
    taker_buy_base_asset_volume,
    taker_buy_quote_asset_volume,
    ignore
)
select
    candle_time,
    100,
    100.1,
    99.9,
    100.1,
    1,
    candle_time + interval '999 milliseconds',
    100,
    1,
    0.5,
    50,
    0
from generate_series(
    timestamp '2024-01-01 00:00:00',
    timestamp '2024-01-02 23:59:59',
    interval '1 second'
) as timestamps(candle_time);

insert into raw.load_audit (
    source_file,
    source_file_size_bytes,
    loaded_at,
    row_count,
    minimum_open_time,
    maximum_open_time
)
select
    'ci-generated-fixture',
    null,
    current_timestamp,
    count(*),
    min(open_time),
    max(open_time)
from raw.binance_btc_usdt_1s;

create index binance_btc_usdt_1s_open_time_idx
    on raw.binance_btc_usdt_1s (open_time);

analyze raw.binance_btc_usdt_1s;
