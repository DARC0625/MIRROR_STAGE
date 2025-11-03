"""Command execution helpers for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import logging
import shlex
import subprocess
from dataclasses import dataclass
from typing import Any, Dict, Optional

from .transport import CommandTransport


@dataclass(slots=True)
class CommandRequest:
  command_id: str
  command: str
  timeout: float = 30.0

  @classmethod
  def from_payload(cls, payload: Dict[str, Any]) -> "CommandRequest":
    return cls(
      command_id=str(payload["id"]),
      command=str(payload["command"]),
      timeout=float(payload.get("timeout", 30)),
    )


class CommandExecutor:
  def __init__(self, hostname: str, transport: CommandTransport, logger: Optional[logging.Logger] = None) -> None:
    self.hostname = hostname
    self.transport = transport
    self.logger = logger or logging.getLogger("reflector.commands.executor")

  def poll_and_execute(self) -> None:
    try:
      payload = self.transport.fetch_pending(self.hostname)
    except Exception as error:
      self.logger.debug("Command poll failed: %s", error)
      return

    if not payload or not payload.get("items"):
      return

    for item in payload["items"]:
      try:
        request = CommandRequest.from_payload(item)
      except Exception as error:
        self.logger.warning("Invalid command payload: %s", error)
        continue
      result = self.execute(request)
      try:
        self.transport.submit_result(request.command_id, result)
      except Exception as error:
        self.logger.error("Failed to submit command result: %s", error)

  def execute(self, request: CommandRequest) -> Dict[str, Any]:
    self.logger.info("Executing command %s: %s", request.command_id, request.command)
    try:
      completed = subprocess.run(
        shlex.split(request.command),
        capture_output=True,
        text=True,
        timeout=request.timeout,
        check=False,
      )
    except subprocess.TimeoutExpired:
      self.logger.warning("Command %s timed out", request.command_id)
      return {
        "status": "timeout",
        "stdout": "",
        "stderr": "",
      }
    except Exception as error:
      self.logger.error("Command %s failed: %s", request.command_id, error)
      return {
        "status": "error",
        "stdout": "",
        "stderr": str(error),
      }

    status = "success" if completed.returncode == 0 else "failed"
    return {
      "status": status,
      "stdout": completed.stdout[-4096:],
      "stderr": completed.stderr[-4096:],
      "exitCode": completed.returncode,
    }
