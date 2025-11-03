"""HTTP uplink loop for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import json
import time
import os
from pathlib import Path
from typing import Any, Dict

import requests

from .telemetry import collect_snapshot


def load_config() -> Dict[str, Any]:
    config_env = os.getenv("MIRROR_STAGE_REFLECTOR_CONFIG")
    if config_env:
        config_path = Path(config_env).expanduser().resolve()
    else:
        config_path = Path(__file__).resolve().parents[2] / "config.json"
    if not config_path.exists():
        raise FileNotFoundError(f"config.json not found at {config_path}")
    return json.loads(config_path.read_text())


def build_payload(config: Dict[str, Any]) -> Dict[str, Any]:
    snapshot = collect_snapshot().to_payload()
    if "hostname_override" in config:
        snapshot["hostname"] = config["hostname_override"]
    if "rack" in config:
        snapshot["rack"] = config["rack"]
    if "position" in config:
        snapshot["position"] = config["position"]
    tags = snapshot.get("tags")
    if not isinstance(tags, dict):
        tags = {}
        snapshot["tags"] = tags
    for key, value in config.get("tags", {}).items():
        tags[str(key)] = str(value)
    return {"samples": [snapshot]}


def loop_once(config: Dict[str, Any]) -> None:
    payload = build_payload(config)
    endpoint = config["endpoint"]
    response = requests.post(endpoint, json=payload, timeout=5)
    response.raise_for_status()

    data = response.json()
    accepted = data.get("accepted", 0)
    print(f"[uplink] sent {accepted} samples -> {endpoint}")


def main() -> None:
    config = load_config()
    interval = float(config.get("interval_seconds", 2.0))

    print(f"[uplink] starting loop against {config['endpoint']} every {interval}s")
    while True:
        try:
            loop_once(config)
        except Exception as exc:  # pylint: disable=broad-except
            print(f"[uplink] error: {exc}")
        time.sleep(max(interval, 1.0))


if __name__ == "__main__":
    main()
