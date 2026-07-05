from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import Any

import structlog

logger = structlog.get_logger(__name__)


class JobRunner:
    def enqueue(self, coro_factory: Callable[[], Awaitable[Any]], *, label: str, delay_seconds: float = 0.1) -> None:
        task = asyncio.create_task(self._run(coro_factory, label=label, delay_seconds=delay_seconds))
        task.add_done_callback(self._log_task_errors)

    async def _run(
        self,
        coro_factory: Callable[[], Awaitable[Any]],
        *,
        label: str,
        delay_seconds: float,
    ) -> None:
        try:
            if delay_seconds > 0:
                await asyncio.sleep(delay_seconds)
            await coro_factory()
        except Exception:
            logger.exception("background_job_failed", label=label)

    def _log_task_errors(self, task: asyncio.Task[Any]) -> None:
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            logger.error("background_task_exception", error=str(exc))


job_runner = JobRunner()
