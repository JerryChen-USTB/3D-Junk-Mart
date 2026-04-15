from __future__ import annotations

from typing import Any

import httpx

from shared.config import (
    TRAINER_SERVICE_BASE_URL,
    TRAINER_SERVICE_TIMEOUT_SECONDS,
    trainer_service_headers,
)


class TrainerServiceError(RuntimeError):
    def __init__(self, detail: str, *, status_code: int = 502) -> None:
        super().__init__(detail)
        self.detail = detail
        self.status_code = status_code


class TrainerClient:
    def __init__(self) -> None:
        self.base_url = TRAINER_SERVICE_BASE_URL
        self.timeout = TRAINER_SERVICE_TIMEOUT_SECONDS

    async def _request(self, method: str, path: str, *, json_payload: dict[str, Any] | None = None) -> dict[str, Any]:
        if not self.base_url:
            raise TrainerServiceError("TRAINER_SERVICE_BASE_URL is not configured.", status_code=503)

        url = f"{self.base_url}{path}"
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.request(
                    method,
                    url,
                    json=json_payload,
                    headers=trainer_service_headers(),
                )
        except httpx.ConnectError as exc:
            raise TrainerServiceError(
                f"Failed to connect to trainer service at {self.base_url}: {exc}",
                status_code=503,
            ) from exc
        except httpx.TimeoutException as exc:
            raise TrainerServiceError(
                f"Trainer service request timed out after {self.timeout:.1f}s.",
                status_code=504,
            ) from exc
        except httpx.HTTPError as exc:
            raise TrainerServiceError(f"Trainer service request failed: {exc}", status_code=502) from exc

        if response.status_code >= 400:
            detail: str
            try:
                payload = response.json()
            except ValueError:
                payload = None

            if isinstance(payload, dict) and payload.get("detail"):
                detail = str(payload["detail"])
            else:
                detail = response.text.strip() or f"Trainer service returned HTTP {response.status_code}."
            raise TrainerServiceError(detail, status_code=response.status_code)

        try:
            payload = response.json()
        except ValueError:
            return {}
        return payload if isinstance(payload, dict) else {}

    async def start_task(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._request("POST", f"/internal/tasks/{task_id}/start", json_payload=payload)

    async def cancel_task(self, task_id: str) -> dict[str, Any]:
        return await self._request("POST", f"/internal/tasks/{task_id}/cancel")

    async def start_mask_debug(self, task_id: str) -> dict[str, Any]:
        return await self._request("POST", f"/internal/tasks/{task_id}/mask-debug")

    async def preview_mask(self, task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._request("POST", f"/internal/tasks/{task_id}/mask-preview", json_payload=payload)

    async def resume_task(self, task_id: str) -> dict[str, Any]:
        return await self._request("POST", f"/internal/tasks/{task_id}/resume")


trainer_client = TrainerClient()
