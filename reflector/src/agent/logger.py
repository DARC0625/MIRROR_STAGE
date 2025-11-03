"""Logging utilities for MIRROR STAGE REFLECTOR."""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

from .config import LoggingConfig


def configure_logging(config: LoggingConfig, root_dir: Path) -> logging.Logger:
  logger = logging.getLogger("reflector")
  logger.setLevel(getattr(logging, config.level.upper(), logging.INFO))
  logger.propagate = False

  # Clear previous handlers when reconfiguring
  logger.handlers.clear()

  formatter = logging.Formatter(
    fmt="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
  )

  stream_handler = logging.StreamHandler()
  stream_handler.setFormatter(formatter)
  logger.addHandler(stream_handler)

  log_file: Optional[str] = config.file
  if log_file:
    log_path = (root_dir / log_file).expanduser().resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    file_handler = RotatingFileHandler(
      log_path,
      maxBytes=config.max_bytes,
      backupCount=config.backup_count,
      encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

  return logger
