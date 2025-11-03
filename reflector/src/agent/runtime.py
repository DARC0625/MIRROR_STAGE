"""Async runtime for the MIRROR STAGE REFLECTOR agent."""

from __future__ import annotations

import asyncio
import socket
import time
from pathlib import Path
from typing import Optional

from .config import AgentConfig, load_config
from .logger import configure_logging
from .telemetry import collect_snapshot
from .transport import CommandTransport, HttpTransport
from .commands import CommandExecutor


async def telemetry_loop(config: AgentConfig, transport: HttpTransport, logger) -> None:
  interval = max(config.interval_seconds, 1.0)
  failure_count = 0
  hostname = config.hostname_override or socket.gethostname()

  while True:
    started = time.perf_counter()
    try:
      snapshot = collect_snapshot()
      payload = snapshot.to_payload()
      payload["hostname"] = hostname
      if config.rack:
        payload["rack"] = config.rack
      if config.position:
        payload["position"] = config.position

      tags = payload.get("tags") or {}
      tags.update(config.tags)
      payload["tags"] = tags

      response = transport.send_metrics({"samples": [payload]})
      accepted = response.get("accepted")
      logger.debug("Telemetry sent (%s samples accepted)", accepted)
      failure_count = 0
    except Exception as error:
      failure_count += 1
      logger.error("Telemetry send failed (attempt %s): %s", failure_count, error)

    elapsed = time.perf_counter() - started
    backoff = min(30.0, interval * max(1, failure_count)) if failure_count else interval
    await asyncio.sleep(max(1.0, backoff - elapsed))


async def command_loop(config: AgentConfig, executor: CommandExecutor, logger) -> None:
  poll_interval = max(config.command_poll_seconds, 5.0)
  while True:
    try:
      executor.poll_and_execute()
    except Exception as error:
      logger.error("Command loop error: %s", error)
    await asyncio.sleep(poll_interval)


async def run_agent(config_path: Optional[str] = None, interval_override: Optional[float] = None) -> None:
  config = load_config(config_path)
  if interval_override is not None and interval_override > 0:
    config.interval_seconds = interval_override
  root_dir = Path(__file__).resolve().parents[2]
  logger = configure_logging(config.logging, root_dir)
  logger.info("Starting MIRROR STAGE REFLECTOR (interval %.1fs)", config.interval_seconds)

  transport = HttpTransport(config.endpoint, logger.getChild("metrics"))

  tasks = [
    asyncio.create_task(telemetry_loop(config, transport, logger.getChild("telemetry"))),
  ]

  if config.command_endpoint:
    command_transport = CommandTransport(config.command_endpoint, logger.getChild("command_transport"))
    executor = CommandExecutor(config.hostname_override or socket.gethostname(), command_transport, logger.getChild("executor"))
    tasks.append(asyncio.create_task(command_loop(config, executor, logger.getChild("commands"))))

  await asyncio.gather(*tasks)
