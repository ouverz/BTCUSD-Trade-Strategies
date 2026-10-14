# Bitcoin Hourly Strategy Backtest

Reproducible PostgreSQL + dbt implementation of the BTC/USDT hourly strategy assignment. The data pipeline runs in Docker; UV manages the pinned Python/dbt dependency for both the container and CI.

## Prerequisites and input

- Docker with Compose v2
- UV (for local Python dependency setup and dbt development; `./run.sh` runs dbt in Docker)
- Exactly one root-level `.csv`, or set `DATA_FILE=/absolute/path/to/file.csv`
- Expected header (case-sensitive): `Open Time,Open,High,Low,Close,Volume,Close Time,Quote Asset Volume,Number of Trades,Taker Buy Base Asset Volume,Taker Buy Quote Asset Volume,Ignore`

The assignment CSV is runtime input and must be placed in the project root; it is intentionally excluded from version control and from the Docker build context. Copy `.env.example` to `.env` before running. The default credentials are for local development only. PostgreSQL is published on localhost only; do not expose this Compose configuration as a production database.

Python dependencies are declared in `pyproject.toml` and installed with UV. To prepare a local Python environment for dbt commands outside Docker, run:

```bash
uv sync
```

## Run

```bash
./run.sh
./run.sh --start-date 2024-01-01 --end-date 2024-01-31 --hour 9
./run.sh --reload
```

Dates are inclusive and default to the full source range. `--hour` controls displayed output only; all 24 hours are always compared. Existing raw data is reused unless `--reload` is supplied. Reuse requires the selected filename and file size to match the latest load record; a same-size content change is not detected because checksum work is deferred. If upgrading a database created before load sizes were recorded, run `./run.sh --reload` once to establish the new provenance fields and audit the source. Reloading is transactional: the old raw table remains usable if `COPY` or index creation fails. A successful reload appends load provenance, recreates the non-unique timestamp index, refreshes PostgreSQL statistics, and runs a consolidated source-quality audit before dbt.

Useful development commands:

```bash
docker compose up -d postgres
docker compose run --rm dbt build
docker compose run --rm dbt test
docker compose down
```

The standalone dbt commands assume the raw source has already been loaded and dbt packages have been installed. `./run.sh` handles dependency installation, model build, tests, documentation, governance checks, and final SQL output end to end. `docker compose down` stops services but preserves the local PostgreSQL bind-mounted data.

Generated dbt documentation is written to `target/`. `target/build_run_results.json` preserves the build results before documentation generation replaces dbt's ordinary `run_results.json` artifact.

PostgreSQL is stored in the ignored `postgres_data/` bind-mounted directory and persists between runs. Because this is a bind mount, `docker compose down -v` does not delete it; use `./run.sh --reload` to replace its raw dataset.

`run.sh` prints both the assignment answers and an aggregate endpoint-quality summary. The same quality summary can be run independently with `sql/source_quality_results.sql`. Load history is stored in `raw.load_audit`; source-level quality results are retained per load in `raw.source_quality_audit`. Known malformed close timestamps are reported but do not fail the load; impossible price, OHLC, or volume relationships and load-metadata mismatches do.

## Interpretation

For each UTC date and entry hour, the strategy buys at the exact first-second `open` and sells at the exact final-second `close`. Repeated physical rows are accepted only when the strategy-relevant endpoint prices agree: entry `open` at exactly `HH:00:00`, and valid exit `close` at exactly `HH:59:59`. Conflicting prices are not resolved by choosing a maximum or latest row; the resolved price is null and the candidate is excluded. Any malformed physical copy at the exit timestamp also excludes the candidate. Nearby timestamps do not substitute for exact endpoints. Missing endpoints, conflicts, nonpositive prices, and malformed exit candles remain visible as diagnostics. Trade factor is `exit_price / entry_price`; compounded equity is the cumulative product of factors. Drawdown is `equity / running_peak - 1`, and maximum loss is the positive magnitude of the minimum drawdown.

## Data model

The transformation path makes every grain change explicit:

```text
raw physical rows
  -> staging physical candles
  -> requested strategy periods
  -> resolved endpoint observations
  -> classified candidate trades
  -> eligible-trade equity
  -> public trade, hourly, yearly, and answer marts
```

Public relations in `analytics_marts`:

- `fct_hourly_strategy_trades`: every requested date-hour, including exclusions and their reasons.
- `agg_hourly_strategy_summary`: the 24 all-history strategies with coverage, distribution, return, and risk metrics.
- `agg_hourly_strategy_yearly`: the same comparison by UTC calendar year with annual equity resets.
- `rpt_assignment_answers`: the deterministic two-row assignment result.

The first and last source dates may be partial. Candidates whose two endpoints cannot fit inside the overall source timestamp range are labeled `outside_source_window`; they are not treated as internal data failures and are excluded from the coverage denominator.

Pull requests run a small deterministic two-day Postgres/dbt build in GitHub Actions. It validates transformations and governance without downloading or committing the full market-data CSV.

Duplicate and conflict checks are intentionally limited to the two timestamps and price fields used by the strategy. No full-source canonical candle table, file checksum, or row-level quarantine process is part of the default dbt build; those would require a demonstrated need and matching ingestion support.

## Recorded reference results

The previously validated full-history run selected:

| Assignment question | Selected UTC hour | Result | Eligible trade days |
|---|---:|---:|---:|
| Greatest compounded return | 22 | 42.519% | 1,282 |
| Smallest maximum-drawdown magnitude | 10 | 9.034% | 1,282 |

Both results cover eligible trades from 2021-02-23 through 2024-08-27.

These are historical, assumption-bound backtest results, not a claim of future profitability. The best of 24 hours was selected after comparing them on the same historical data, so the winning return is subject to multiple-comparison / selection bias. The calculation excludes fees, spread, slippage, latency, market impact, and execution constraints. Re-run `./run.sh` against the supplied CSV to reproduce the answers; verify the current run output before quoting these figures as the result of a fresh build.


