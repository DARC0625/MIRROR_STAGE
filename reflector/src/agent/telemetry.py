"""Telemetry collection utilities for MIRROR STAGE REFLECTORs."""

from __future__ import annotations

import platform
import socket
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from typing import Any, Dict

import psutil


@dataclass(slots=True)
class TelemetrySnapshot:
    hostname: str
    timestamp: str
    cpu_load: float
    memory_used_percent: float
    load_average: float
    uptime_seconds: int
    net_bytes_tx: int
    net_bytes_rx: int

    def to_payload(self) -> Dict[str, Any]:
        payload = asdict(self)
        payload["agent_version"] = "0.1.0-dev"
        payload["platform"] = platform.platform()
        return payload


def collect_snapshot() -> TelemetrySnapshot:
    """Collect a minimal telemetry snapshot from the current host."""
    cpu_load = psutil.cpu_percent(interval=0.1)
    memory = psutil.virtual_memory()
    uptime_seconds = int(datetime.now(timezone.utc).timestamp() - psutil.boot_time())
    load_average = psutil.getloadavg()[0] if hasattr(psutil, "getloadavg") else 0.0
    net = psutil.net_io_counters()

    return TelemetrySnapshot(
        hostname=socket.gethostname(),
        timestamp=datetime.now(timezone.utc).isoformat(),
        cpu_load=cpu_load,
        memory_used_percent=memory.percent,
        load_average=float(load_average),
        uptime_seconds=uptime_seconds,
        net_bytes_tx=net.bytes_sent,
        net_bytes_rx=net.bytes_recv,
    )
