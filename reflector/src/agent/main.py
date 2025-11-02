"""Minimal runner for the MIRROR STAGE REFLECTOR host agent."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .telemetry import collect_snapshot


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="MIRROR STAGE REFLECTOR placeholder. Collects telemetry once or on an interval.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Collect a single telemetry snapshot and print the JSON payload.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
        help="Collection interval in seconds when running continuously.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.once:
        snapshot = collect_snapshot()
        print(json.dumps(snapshot.to_payload(), indent=2))
        return 0

    try:
        import time

        while True:
            snapshot = collect_snapshot()
            print(json.dumps(snapshot.to_payload()))
            time.sleep(max(args.interval, 1.0))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
