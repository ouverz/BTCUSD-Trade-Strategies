#!/usr/bin/env python3
"""Write a small, deterministic Binance-shaped CSV for the CI pipeline smoke test."""

import csv
import sys
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path


HEADER = [
    "Open Time",
    "Open",
    "High",
    "Low",
    "Close",
    "Volume",
    "Close Time",
    "Quote Asset Volume",
    "Number of Trades",
    "Taker Buy Base Asset Volume",
    "Taker Buy Quote Asset Volume",
    "Ignore",
]


def candle_row(opened_at: datetime, price: Decimal) -> list[str]:
    high = price + Decimal("0.1")
    low = price - Decimal("0.1")
    closed_at = opened_at + timedelta(milliseconds=999)
    return [
        opened_at.strftime("%Y-%m-%d %H:%M:%S"),
        f"{price:.8f}",
        f"{high:.8f}",
        f"{low:.8f}",
        f"{price:.8f}",
        "1.00000000",
        closed_at.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
        "100.00000000",
        "1",
        "0.40000000",
        "40.00000000",
        "0",
    ]


def main(output_path: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.writer(output_file, lineterminator="\n")
        writer.writerow(HEADER)
        for day_offset in range(2):
            trade_day = date(2024, 1, 1) + timedelta(days=day_offset)
            for hour in range(24):
                entry_price = Decimal(100 + hour) + Decimal(day_offset) / 4
                entry_at = datetime.combine(trade_day, time(hour=hour))
                exit_at = entry_at + timedelta(minutes=59, seconds=59)
                daily_move = Decimal((hour % 5) - 2) / 1000 + Decimal(day_offset) / 10000
                exit_price = entry_price * (Decimal(1) + daily_move)
                writer.writerow(candle_row(entry_at, entry_price))
                writer.writerow(candle_row(exit_at, exit_price))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: create_ci_fixture.py OUTPUT_CSV")
    main(sys.argv[1])
