"""Configuration loader for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Optional

DEFAULT_INTERVAL_SECONDS = 5.0
DEFAULT_COMMAND_POLL_SECONDS = 15.0


@dataclass(slots=True)
class LoggingConfig:
  level: str = "INFO"
  file: Optional[str] = None
  max_bytes: int = 5 * 1024 * 1024
  backup_count: int = 3


@dataclass(slots=True)
class AgentConfig:
  endpoint: str
  interval_seconds: float = DEFAULT_INTERVAL_SECONDS
  hostname_override: Optional[str] = None
  rack: Optional[str] = None
  position: Optional[Dict[str, Any]] = None
  tags: Dict[str, str] = field(default_factory=dict)
  command_endpoint: Optional[str] = None
  command_poll_seconds: float = DEFAULT_COMMAND_POLL_SECONDS
  logging: LoggingConfig = field(default_factory=LoggingConfig)

  @classmethod
  def from_dict(cls, data: Dict[str, Any]) -> "AgentConfig":
    logging_conf = data.get("logging", {})
    logging_config = LoggingConfig(
      level=logging_conf.get("level", "INFO"),
      file=logging_conf.get("file"),
      max_bytes=int(logging_conf.get("max_bytes", 5 * 1024 * 1024)),
      backup_count=int(logging_conf.get("backup_count", 3)),
    )

    return cls(
      endpoint=data["endpoint"],
      interval_seconds=float(data.get("interval_seconds", DEFAULT_INTERVAL_SECONDS)),
      hostname_override=data.get("hostname_override"),
      rack=data.get("rack"),
      position=data.get("position"),
      tags={str(key): str(value) for key, value in data.get("tags", {}).items()},
      command_endpoint=data.get("command_endpoint"),
      command_poll_seconds=float(data.get("command_poll_seconds", DEFAULT_COMMAND_POLL_SECONDS)),
      logging=logging_config,
    )


def load_config(path: Optional[str] = None) -> AgentConfig:
  config_path: Path
  if path:
    config_path = Path(path).expanduser().resolve()
  else:
    env_path = os.getenv("MIRROR_STAGE_REFLECTOR_CONFIG")
    if env_path:
      config_path = Path(env_path).expanduser().resolve()
    else:
      config_path = Path(__file__).resolve().parents[2] / "config.json"

  if not config_path.exists():
    raise FileNotFoundError(f"reflector config.json not found at {config_path}")

  raw = json.loads(config_path.read_text())
  return AgentConfig.from_dict(raw)
