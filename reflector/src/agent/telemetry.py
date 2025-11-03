"""Telemetry collection utilities for MIRROR STAGE REFLECTORs."""

from __future__ import annotations

import platform
import socket
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple, Optional

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
    extras: Dict[str, Any] = field(default_factory=dict)

    def to_payload(self) -> Dict[str, Any]:
        payload = asdict(self)
        extras = payload.pop("extras", {})
        payload["agent_version"] = "0.1.0-dev"
        payload["platform"] = platform.platform()
        payload.update(extras)
        return payload


def collect_snapshot() -> TelemetrySnapshot:
    """Collect a minimal telemetry snapshot from the current host."""
    cpu_load = psutil.cpu_percent(interval=0.1)
    memory = psutil.virtual_memory()
    uptime_seconds = int(datetime.now(timezone.utc).timestamp() - psutil.boot_time())
    load_average = psutil.getloadavg()[0] if hasattr(psutil, "getloadavg") else 0.0
    net = psutil.net_io_counters()
    extras = _collect_extras()

    return TelemetrySnapshot(
        hostname=socket.gethostname(),
        timestamp=datetime.now(timezone.utc).isoformat(),
        cpu_load=cpu_load,
        memory_used_percent=memory.percent,
        load_average=float(load_average),
        uptime_seconds=uptime_seconds,
        net_bytes_tx=net.bytes_sent,
        net_bytes_rx=net.bytes_recv,
        extras=extras,
    )


def _collect_extras() -> Dict[str, Any]:
    extras: Dict[str, Any] = {}

  try:
    per_cpu = psutil.cpu_percent(percpu=True)
    extras["cpu_per_core"] = per_cpu
  except Exception:
    extras["cpu_per_core"] = []

  extras["cpu_physical_cores"] = psutil.cpu_count(logical=False) or psutil.cpu_count() or 0
  extras["cpu_logical_cores"] = psutil.cpu_count() or 0
  extras["cpu_model"] = platform.processor() or platform.machine()

  try:
    memory = psutil.virtual_memory()
    extras["memory_total_bytes"] = memory.total
    extras["memory_available_bytes"] = memory.available
    except Exception:
        extras.setdefault("memory_total_bytes", 0)
        extras.setdefault("memory_available_bytes", 0)

    try:
        swap = psutil.swap_memory()
        extras["swap_used_percent"] = swap.percent
    except Exception:
        extras["swap_used_percent"] = None

  disks = _collect_disk_usage()
  interfaces = _collect_interface_stats()
  extras["disks"] = disks
  extras["interfaces"] = interfaces
  extras["temperatures"] = _collect_temperatures()
  temps = extras["temperatures"]
  cpu_temp = _extract_temperature(temps, ("cpu", "package", "core"))
  if cpu_temp is not None:
    extras["cpu_temperature"] = cpu_temp
  gpu_temp = _extract_temperature(temps, ("gpu", "graphics", "video"))
  if gpu_temp is not None:
    extras["gpu_temperature"] = gpu_temp
  extras["top_processes"] = _collect_top_processes()

  uname = platform.uname()
  extras["os_distro"] = uname.system
  extras["os_release"] = uname.release
  extras["os_kernel"] = uname.version
  extras["system_model"] = uname.machine
  extras["system_manufacturer"] = getattr(uname, "node", None) or uname.system

  tags: Dict[str, str] = {}
  primary_interface = next((iface for iface in interfaces if iface.get("is_up")), None) or (interfaces[0] if interfaces else None)
  if primary_interface:
    tags["primary_interface"] = primary_interface["name"]
    speed_mbps = primary_interface.get("speed_mbps")
    if speed_mbps:
      tags["primary_interface_speed_mbps"] = str(speed_mbps)
      extras["primary_interface_speed_mbps"] = speed_mbps
    if disks:
        tags["primary_disk"] = disks[0]["device"]
    if tags:
        extras["tags"] = tags

    return extras


def _collect_disk_usage() -> List[Dict[str, Any]]:
    disks: List[Dict[str, Any]] = []
    try:
        for part in psutil.disk_partitions(all=False):
            try:
                usage = psutil.disk_usage(part.mountpoint)
            except PermissionError:
                continue
            disks.append(
                {
                    "device": part.device,
                    "mountpoint": part.mountpoint,
                    "fstype": part.fstype,
                    "total_bytes": usage.total,
                    "used_bytes": usage.used,
                    "used_percent": usage.percent,
                }
            )
    except Exception:
        return []
    return disks


def _collect_interface_stats() -> List[Dict[str, Any]]:
    interfaces: List[Dict[str, Any]] = []
    try:
        io_counters = psutil.net_io_counters(pernic=True)
        stats = psutil.net_if_stats()
        for name, counters in io_counters.items():
            iface_stats = stats.get(name)
            interfaces.append(
                {
                    "name": name,
                    "bytes_sent": counters.bytes_sent,
                    "bytes_recv": counters.bytes_recv,
                    "packets_sent": counters.packets_sent,
                    "packets_recv": counters.packets_recv,
                    "errin": counters.errin,
                    "errout": counters.errout,
                    "dropin": counters.dropin,
                    "dropout": counters.dropout,
                    "speed_mbps": iface_stats.speed if iface_stats and iface_stats.speed else None,
                    "is_up": iface_stats.isup if iface_stats else None,
                }
            )
    except Exception:
        return []
    return interfaces


def _collect_temperatures() -> Dict[str, float]:
  temps: Dict[str, float] = {}
  if not hasattr(psutil, "sensors_temperatures"):
    return temps
  try:
        sensors = psutil.sensors_temperatures()
        for label, entries in sensors.items():
            if not entries:
                continue
            # take the hottest reading per sensor bank
            hottest = max(entries, key=lambda entry: entry.current if entry.current is not None else float("-inf"))
            if hottest.current is None:
                continue
            key = f"{label}:{hottest.label or hottest.sensor or 'temp'}"
            temps[key] = float(hottest.current)
    except Exception:
        return {}
  return temps


def _extract_temperature(temps: Dict[str, float], keywords: Tuple[str, ...]) -> Optional[float]:
  if not temps:
    return None
  matches = [value for key, value in temps.items() if any(keyword in key.lower() for keyword in keywords)]
  if matches:
    return float(max(matches))
  return None


def _collect_top_processes(limit: int = 5) -> List[Dict[str, Any]]:
    processes: List[Tuple[float, psutil.Process]] = []
    try:
        for proc in psutil.process_iter(attrs=["pid", "name"]):
            try:
                cpu = proc.cpu_percent(interval=None)
                processes.append((cpu, proc))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
    except Exception:
        return []

    top = sorted(processes, key=lambda item: item[0], reverse=True)[:limit]
    result: List[Dict[str, Any]] = []
    for cpu, proc in top:
        try:
            info = proc.as_dict(attrs=["pid", "name", "username"])
            info["cpu_percent"] = cpu
            info["memory_percent"] = proc.memory_percent()
            result.append(info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return result
