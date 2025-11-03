"""HTTP transport helpers for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import logging
from typing import Any, Dict, Optional

import requests


class HttpTransport:
  def __init__(self, metrics_endpoint: str, logger: Optional[logging.Logger] = None) -> None:
    self.metrics_endpoint = metrics_endpoint
    self.logger = logger or logging.getLogger("reflector.transport")

  def send_metrics(self, payload: Dict[str, Any], timeout: float = 5.0) -> Dict[str, Any]:
    response = requests.post(self.metrics_endpoint, json=payload, timeout=timeout)
    response.raise_for_status()
    return response.json()


class CommandTransport:
  def __init__(self, command_endpoint: str, logger: Optional[logging.Logger] = None) -> None:
    self.command_endpoint = command_endpoint.rstrip("/")
    self.logger = logger or logging.getLogger("reflector.commands")

  def fetch_pending(self, hostname: str, timeout: float = 5.0) -> Dict[str, Any]:
    response = requests.get(
      f"{self.command_endpoint}/pending/{hostname}",
      timeout=timeout,
    )
    response.raise_for_status()
    return response.json()

  def submit_result(self, command_id: str, payload: Dict[str, Any], timeout: float = 5.0) -> None:
    response = requests.post(
      f"{self.command_endpoint}/result/{command_id}",
      json=payload,
      timeout=timeout,
    )
    response.raise_for_status()
