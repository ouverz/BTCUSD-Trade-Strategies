# BTC/USDT Hourly Strategy Backtest

An end-to-end PostgreSQL and dbt pipeline for evaluating daily BTC/USDT hourly strategies from one-second candle data.

## Assignment context

The Bitcoin Backtesting Engine assignment frames the work around an analyst’s proposed Bitcoin strategy and asks for a repeatable evaluation using the assignment-provided Binance BTC/USDT one-second dataset from Kaggle. Its main emphasis is the transformation layer and the quality of the assumptions, verification, and testing—not elaborate data loading.

### Strategy definition

Each strategy uses the same UTC entry hour every day. For example, the 22:00 strategy enters at the exact `22:00:00` candle open and exits at the exact `22:59:59` candle close. A date contributes a trade only when both endpoint observations meet the eligibility rules. Gains and losses are fully reinvested in subsequent eligible trades. The analysis can be repeated for different hours and evaluation date ranges.

### Questions answered

The assignment asks:

1. Which hour of the day had the greatest returns?
2. Which hour of the day had the lowest maximum losses?

This implementation evaluates all 24 UTC entry hours and operationalizes the questions as greatest compounded return and smallest maximum-drawdown magnitude. PostgreSQL stores the source; dbt builds and tests auditable endpoint observations, eligibility and exclusions, equity and drawdown calculations, and final comparisons.

The findings are historical results under explicit assumptions—not investment advice or evidence of future profitability. The simulation omits trading costs and execution constraints, and choosing a winner from the same period used to evaluate it creates selection bias.

## Metric definitions

The implementation starts with a normalized account value of `1.0`; daily trade factors compound sequentially, representing full reinvestment. Each **trade strategy** represents one UTC entry hour.

| Metric | Definition |
|---|---|
| **Trade factor** | Exit price divided by entry price. A factor of `1.02` means the position is multiplied by 1.02. |
| **Trade return** | Trade factor minus 1. A factor of `1.02` is a `+2%` return; `0.98` is `−2%`. |
| **Equity** | A normalized account-value index starting at `1.0`; after each eligible trade, prior equity is multiplied by that trade’s factor. It assumes full reinvestment and excludes cash flows. |
| **Compounded return** | Ending equity minus starting equity, expressed as a percentage. For example, equity ending at `1.42519` represents a `42.519%` compounded return from `1.0`. |
| **Drawdown** | Equity’s change relative to its running peak: `equity / running peak − 1`. It is zero at a new peak and negative below a peak. |
| **Maximum drawdown magnitude** | The positive magnitude of the most negative drawdown. Smaller means a shallower worst peak-to-trough decline; it does not mean the strategy had smaller losing trades. |

Equity compounds only across eligible trades; excluded dates do not add a zero-return trade. The headline metrics use the full eligible history. The yearly summary resets equity at the start of each calendar year and is a separate diagnostic.

## Findings

The recorded full-history run covers eligible trades from **2021-02-23 through 2024-08-27**. Each of the two winning strategies has **1,282 eligible trade days**.

Eligibility is evaluated independently for each hour, so eligible counts and coverage can differ slightly across strategies. Review coverage and exclusion diagnostics alongside returns when comparing the hours.

| Assignment question | UTC entry hour | Result |
|---|---:|---:|
| Greatest compounded return | 22:00 | **42.519%** |
| Smallest maximum-drawdown magnitude | 10:00 | **9.034%** |

These are recorded reference results, not a guarantee that a fresh run will match a different input file. The winning hour was selected from 24 candidates on the same historical period, so the comparison is exposed to selection and multiple-comparison bias. The simulation excludes fees, spread, slippage, latency, market impact, taxes, leverage constraints, and execution failures.

## Data model and lineage

The graph below shows the current dbt model lineage and its connected tests and exposure. It makes the transformation path and model dependencies visible from the raw source through the analyst-facing marts.

![Current dbt model lineage, tests, and exposure](Lineage%20Graph.png)

Key analyst-facing relations in `analytics_marts`:

| Model | Grain and purpose |
|---|---|
| [`fct_hourly_strategy_trades`](models/marts/fct_hourly_strategy_trades.sql) | One row per requested date and UTC hour, including eligibility, exclusion reasons, endpoint diagnostics, and eligible-trade metrics. |
| [`agg_hourly_strategy_summary`](models/marts/agg_hourly_strategy_summary.sql) | One row per hour with coverage, return distribution, compounded return, and maximum drawdown across the full period. |
| [`agg_hourly_strategy_yearly`](models/marts/agg_hourly_strategy_yearly.sql) | One row per year and hour, with year-local equity and performance diagnostics. |
| [`rpt_assignment_answers`](models/marts/rpt_assignment_answers.sql) | The two deterministic assignment winners selected from the hourly summary. |

### Data and eligibility policy

Raw and staging preserve physical source rows; they do not globally deduplicate candles. Resolution happens only at the two strategy endpoints.

| Condition | Treatment | Effect |
|---|---|---|
| Repeated endpoint rows with the same relevant price | Accept the shared price; retain row counts for diagnostics. | Candidate may remain eligible. |
| Conflicting entry opens or valid exit closes | Do not choose a preferred version; leave the price unresolved. | Candidate is excluded and classified. |
| Any malformed close-time row at the exact exit timestamp | Retain as an audit finding; do not use the exit price. | Candidate is excluded. |
| Missing exact endpoint or nonpositive endpoint price | Do not substitute a nearby timestamp or price. | Candidate is excluded. |
| Requested endpoint outside the overall source timestamp window | Keep the candidate visible as `outside_source_window`. | Excluded from the in-source coverage denominator. |
| In-window candidate with unusable endpoint data | Keep it visible with diagnostics and an exclusion reason. | Included in the in-source denominator, not in eligible trades. |

The source audit also rejects impossible prices, OHLC relationships, volume relationships, and load-metadata mismatches. Malformed close timestamps are recorded as diagnostics rather than failing ingestion, so the affected strategy candidates can be explicitly excluded downstream.

## Reproduce the project

### Requirements and input

- Git, to clone the repository (or download the source archive).
- Docker with Docker Compose v2.
- The assignment CSV. Place exactly one `.csv` file in the project root, or set `DATA_FILE` to its path.
- The CSV must have this exact, case-sensitive header:

```text
Open Time,Open,High,Low,Close,Volume,Close Time,Quote Asset Volume,Number of Trades,Taker Buy Base Asset Volume,Taker Buy Quote Asset Volume,Ignore
```

The CSV is runtime input and is excluded from version control and the Docker build context. Host-installed Python dependencies are not required for the end-to-end Docker workflow.

### End-to-end steps

1. **Clone the project and provide the source CSV.** Use the assignment-provided file; do not commit it.

   ```bash
   git clone https://github.com/ouverz/BTCUSD-Trade-Strategies.git
   cd BTCUSD-Trade-Strategies
   ```

2. **Configure local credentials.** Optionally copy `.env.example` to `.env` and set a local `POSTGRES_PASSWORD`. The example values are for local development only. PostgreSQL is bound to localhost; do not expose this Compose configuration as a production database.
3. **Run the complete workflow:**

   ```bash
   ./run.sh
   ```

   The script starts PostgreSQL and waits for it to become healthy, creates the raw/audit tables, loads or reuses the CSV, runs the source-quality audit, installs dbt packages, executes `dbt build`, generates dbt documentation, checks governance rules, and prints the assignment answers and endpoint-quality summary.

4. **Review the output.** Confirm the result rows, evaluated dates, eligible counts, and exclusion totals printed at the end. The run also writes dbt artifacts under `target/` and logs under `logs/`.

PostgreSQL data persists in the local `postgres_data/` directory. `docker compose down` stops the services but preserves that data.

### Optional local controls

These options tailor a run without changing the default full-history workflow:

```bash
# Restrict the evaluated date range; bounds are inclusive.
./run.sh --start-date 2024-01-01 --end-date 2024-01-31

# Select an explicit input file instead of the single root-level CSV.
DATA_FILE=/absolute/path/to/candles.csv ./run.sh

# Filter the displayed winner report to a UTC hour (does not limit model calculations).
./run.sh --hour 22

# Replace the currently loaded raw data and rerun the source audit.
./run.sh --reload
```

Use `--reload` deliberately: it replaces the raw table’s current contents and can take substantial time, disk space, and database I/O for the full source. Without `--reload`, the existing load is reused only when the selected filename and file size match the latest load audit. Same-size content changes are not detected because checksums are deferred.

### Focused dbt development

After PostgreSQL is running and raw data has been loaded, iterate on dbt independently:

```bash
docker compose run --rm dbt deps
docker compose run --rm dbt build
```

`dbt build` runs selected models and their configured tests. To rerun tests without rebuilding models:

```bash
docker compose run --rm dbt test
```

These commands assume the Compose database and loaded raw relation already exist. Python dependencies are declared in [`requirements.txt`](requirements.txt) and installed with pip in the Docker image and CI. The direct dbt adapter version is pinned; transitive Python dependency versions are not fully locked.

### Troubleshooting a PostgreSQL port conflict

If Compose reports that port `5432` is already allocated, another local PostgreSQL service or Compose project is using it. Identify the listener before stopping anything:

```bash
lsof -nP -iTCP:5432 -sTCP:LISTEN
```

To keep the other service running, set `POSTGRES_PORT=5433` in `.env` and rerun the desired workflow. For a one-off Compose command without changing `.env`, prefix it with the alternate port:

```bash
POSTGRES_PORT=5433 docker compose run --rm dbt docs generate
```

The dbt container still connects to PostgreSQL on the Compose network’s internal port `5432`; `POSTGRES_PORT` changes only the port exposed on the host.

## Validation and governance

Controls are applied at several distinct stages. A passing test suite validates defined data and transformation rules; it does not establish that a strategy is profitable or statistically robust.

| Area | How it is governed | Where to inspect |
|---|---|---|
| Ingestion and source integrity | SQL audit checks physical row counts, timestamp bounds, price/OHLC/volume constraints, and load metadata. Malformed close-time rows are counted and retained as diagnostics. A failed hard check stops the run. | [`scripts/source_quality_audit.sql`](scripts/source_quality_audit.sql), [`scripts/load_data.sql`](scripts/load_data.sql), `raw.source_quality_audit` |
| Endpoint and eligibility logic | dbt unit tests exercise exact timestamps, identical duplicates, conflicting prices, malformed exits, eligibility, and compounding with deterministic examples. | [`models/intermediate/intermediate.yml`](models/intermediate/intermediate.yml) (`unit_tests`) |
| Transformation and metric invariants | Singular SQL tests check exact endpoint use, status/eligibility consistency, candidate-count reconciliation, exclusions, equity compounding, drawdown, yearly reconciliation, and answer cardinality. | [`tests/`](tests/) |
| Keys, accepted values, and model contracts | dbt generic tests enforce nullability, uniqueness, ranges, and composite grain. Public marts enforce declared column contracts and data types. | [`models/staging/`](models/staging/), [`models/intermediate/intermediate.yml`](models/intermediate/intermediate.yml), [`models/marts/marts.yml`](models/marts/marts.yml) |
| Documentation and architecture rules | A manifest-based check requires model/column descriptions, prevents non-staging models from reading sources directly, requires mart contracts/data types, and checks the analyst exposure. | [`scripts/governance_check.py`](scripts/governance_check.py) |
| Continuous integration | GitHub Actions generates a deterministic two-day synthetic CSV and runs `run.sh` end-to-end, including ingestion, source audit, dbt build/tests, docs, governance, and result assertions. It does not download the full assignment dataset or validate the recorded full-history winners. | [`.github/workflows/dbt-quality.yml`](.github/workflows/dbt-quality.yml), [`scripts/create_ci_fixture.py`](scripts/create_ci_fixture.py), [`tests/fixtures/assert_ci_results.sql`](tests/fixtures/assert_ci_results.sql) |

Load provenance is stored in `raw.load_audit`; per-load source-quality results are stored in `raw.source_quality_audit`. Use [`sql/source_quality_results.sql`](sql/source_quality_results.sql) to review the latest source audit. The end-to-end script also saves the dbt build result as `target/build_run_results.json` before generating docs.

## Limitations and interpretation

- The first and last dates in the source may be partial. Such boundary candidates are visible but excluded from the in-source coverage denominator.
- Duplicate/conflict handling is limited to the exact endpoint timestamps and prices used by this strategy. The project does not create a canonicalized full-source candle table or row-level quarantine system.
- Source identity is checked by filename and file size, not a content checksum.
- The 24 hours are compared on the same historical sample. Selecting the apparent winner on that sample introduces selection bias; yearly summaries are diagnostics, not out-of-sample validation.
- Trading costs and execution constraints are not available in the assignment input and are not modeled. Credible profitability assessment would require pre-defined selection rules, an untouched evaluation period, and realistic cost and execution assumptions.
