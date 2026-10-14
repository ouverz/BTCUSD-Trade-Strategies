#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

expected_header='Open Time,Open,High,Low,Close,Volume,Close Time,Quote Asset Volume,Number of Trades,Taker Buy Base Asset Volume,Taker Buy Quote Asset Volume,Ignore'
start_date=''
end_date=''
hour='all'
reload='false'

usage() {
    echo "Usage: ./run.sh [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD] [--hour 0-23|all] [--reload]" >&2
}

while (($#)); do
    case "$1" in
        --start-date|--end-date|--hour)
            (($# >= 2)) || { usage; exit 2; }
            value="$2"
            case "$1" in
                --start-date) start_date="$value" ;;
                --end-date) end_date="$value" ;;
                --hour) hour="$value" ;;
            esac
            shift 2
            ;;
        --reload) reload='true'; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

date_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
[[ -z "$start_date" || "$start_date" =~ $date_pattern ]] || { echo "Invalid --start-date: $start_date" >&2; exit 2; }
[[ -z "$end_date" || "$end_date" =~ $date_pattern ]] || { echo "Invalid --end-date: $end_date" >&2; exit 2; }
[[ "$hour" == all || "$hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || { echo "--hour must be 0-23 or all" >&2; exit 2; }
[[ -z "$start_date" || -z "$end_date" || "$start_date" < "$end_date" || "$start_date" == "$end_date" ]] || { echo "--start-date must not be after --end-date" >&2; exit 2; }

if [[ -n "${DATA_FILE:-}" ]]; then
    data_file="$DATA_FILE"
else
    shopt -s nullglob
    csv_files=(./*.csv)
    ((${#csv_files[@]} == 1)) || { echo "Expected exactly one root-level CSV; found ${#csv_files[@]}. Set DATA_FILE explicitly." >&2; exit 1; }
    data_file="${csv_files[0]}"
fi
[[ -f "$data_file" ]] || { echo "CSV not found: $data_file" >&2; exit 1; }
data_file="$(cd "$(dirname "$data_file")" && pwd)/$(basename "$data_file")"
case "$(uname -s)" in
    Darwin) data_file_size_bytes="$(stat -f%z "$data_file")" ;;
    *) data_file_size_bytes="$(stat -c%s "$data_file")" ;;
esac
actual_header="$(LC_ALL=C head -n 1 "$data_file" | tr -d '\r')"
[[ "$actual_header" == "$expected_header" ]] || { echo "Unexpected CSV header." >&2; echo "Expected: $expected_header" >&2; echo "Actual:   $actual_header" >&2; exit 1; }
export DATA_FILE="$data_file"

compose=(docker compose)
psql_cmd=("${compose[@]}" exec -T postgres psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-bitcoin}" -d "${POSTGRES_DB:-bitcoin}")

reload_raw_data() {
    "${psql_cmd[@]}" \
        -v source_file="$(basename "$data_file")" \
        -v source_file_size_bytes="$data_file_size_bytes" \
        -f /dev/stdin <<'SQL'
begin;

drop index if exists raw.binance_btc_usdt_1s_open_time_idx;
truncate table raw.binance_btc_usdt_1s;

\copy raw.binance_btc_usdt_1s (open_time, open, high, low, close, volume, close_time, quote_asset_volume, number_of_trades, taker_buy_base_asset_volume, taker_buy_quote_asset_volume, ignore) from '/data/input.csv' with (format csv, header true)

insert into raw.load_audit (
    source_file,
    source_file_size_bytes,
    loaded_at,
    row_count,
    minimum_open_time,
    maximum_open_time
)
select
    :'source_file',
    :'source_file_size_bytes'::bigint,
    current_timestamp,
    count(*),
    min(open_time),
    max(open_time)
from raw.binance_btc_usdt_1s
;

create index binance_btc_usdt_1s_open_time_idx
    on raw.binance_btc_usdt_1s (open_time);

analyze raw.binance_btc_usdt_1s;
commit;
SQL
}

"${compose[@]}" up -d --build --wait postgres
"${psql_cmd[@]}" -f /dev/stdin < scripts/load_data.sql

# A forced reload must not read the existing raw relation: it may be the
# damaged relation that the reload is intended to replace.
if [[ "$reload" == true ]]; then
    has_rows='t'
else
    has_rows="$("${psql_cmd[@]}" -Atc 'select exists (select 1 from raw.binance_btc_usdt_1s limit 1)')"
fi
loaded_source="$("${psql_cmd[@]}" -Atc 'select source_file from raw.load_audit order by load_id desc limit 1')"
audited_row_count="$("${psql_cmd[@]}" -Atc 'select row_count from raw.load_audit order by load_id desc limit 1')"
audited_file_size="$("${psql_cmd[@]}" -Atc 'select source_file_size_bytes from raw.load_audit order by load_id desc limit 1')"
if [[ "$reload" != true && "$has_rows" == t && -n "$loaded_source" && "$loaded_source" != "$(basename "$data_file")" ]]; then
    echo "Raw data contains $loaded_source, but the selected input is $(basename "$data_file"). Use --reload to replace it." >&2
    exit 1
fi
if [[ "$reload" != true && "$has_rows" == t && "$audited_file_size" != "$data_file_size_bytes" ]]; then
    echo "The selected CSV size does not match the most recent audited load (or its legacy audit has no size). Use --reload to replace and re-audit the raw data." >&2
    exit 1
fi
loaded_new_data='false'
if [[ "$reload" == true || "$has_rows" != t ]]; then
    echo "Loading $(basename "$data_file") with PostgreSQL COPY..."
    reload_raw_data
    loaded_new_data='true'
else
    echo "Reusing ${audited_row_count:-an existing set of} previously loaded raw rows (use --reload to replace them)."
fi
"${psql_cmd[@]}" -c 'create index if not exists binance_btc_usdt_1s_open_time_idx on raw.binance_btc_usdt_1s (open_time)'
if [[ "$loaded_new_data" == true ]]; then
    echo "Running consolidated source-quality audit..."
    "${psql_cmd[@]}" -f /dev/stdin < scripts/source_quality_audit.sql
else
    audited_quality_status="$("${psql_cmd[@]}" -Atc "select coalesce((select quality_status from raw.source_quality_audit order by load_id desc limit 1), 'missing')")"
    if [[ "$audited_quality_status" != passed ]]; then
        echo "The current raw load has no passing source-quality audit; running it now..."
        "${psql_cmd[@]}" -f /dev/stdin < scripts/source_quality_audit.sql
    fi
fi

dbt_vars="{start_date: ${start_date:-null}, end_date: ${end_date:-null}}"
"${compose[@]}" run --rm dbt deps
"${compose[@]}" run --rm dbt build --vars "$dbt_vars"
[[ ! -f target/run_results.json ]] || cp target/run_results.json target/build_run_results.json
"${compose[@]}" run --rm dbt docs generate --vars "$dbt_vars"
"${compose[@]}" run --rm --entrypoint python dbt scripts/governance_check.py

hour_predicate='true'
[[ "$hour" == all ]] || hour_predicate="entry_hour_utc = $hour"
"${psql_cmd[@]}" -P pager=off -c "select question, entry_hour_utc, round(metric_pct::numeric, 6) as metric_pct, evaluated_start_date, evaluated_end_date, valid_trade_days, excluded_incomplete_periods from analytics_marts.rpt_assignment_answers where $hour_predicate order by answer_order"
"${psql_cmd[@]}" -P pager=off -c "select sum(requested_period_count) as requested_periods, sum(outside_source_period_count) as outside_source_periods, sum(in_source_period_count) as in_source_periods, sum(eligible_trade_count) as eligible_trades, sum(excluded_in_source_period_count) as excluded_in_source_periods, sum(missing_entry_period_count) as missing_entry_periods, sum(missing_exit_period_count) as missing_exit_periods, sum(conflicting_entry_period_count) as conflicting_entry_periods, sum(conflicting_exit_period_count) as conflicting_exit_periods, sum(malformed_exit_period_count) as malformed_exit_periods, sum(deduplicated_entry_period_count) as deduplicated_entry_periods, sum(deduplicated_exit_period_count) as deduplicated_exit_periods from analytics_marts.agg_hourly_strategy_summary"

