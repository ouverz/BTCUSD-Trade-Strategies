select
    'BTCUSDT'::text as symbol,
    open_time as opened_at_utc,
    close_time as closed_at_utc,
    open as open_price,
    high as high_price,
    low as low_price,
    close as close_price,
    volume as base_asset_volume,
    quote_asset_volume,
    number_of_trades,
    taker_buy_base_asset_volume,
    taker_buy_quote_asset_volume,
    ignore as ignored_value,
    loaded_at
from {{ source('raw', 'binance_btc_usdt_1s') }}

