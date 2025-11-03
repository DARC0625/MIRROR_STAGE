"""Entry point for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import argparse
import sys
import asyncio

from .runtime import run_agent
from .telemetry import collect_snapshot


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run MIRROR STAGE REFLECTOR agent (telemetry + command loops).",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Collect a single telemetry snapshot and print the JSON payload.",
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to config.json (defaults to MIRROR_STAGE_REFLECTOR_CONFIG or bundled config).",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=None,
        help="Override telemetry interval (seconds).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.once:
        snapshot = collect_snapshot()
        import json

        print(json.dumps(snapshot.to_payload(), indent=2))
        return 0

    try:
        asyncio.run(run_agent(config_path=args.config, interval_override=args.interval))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
