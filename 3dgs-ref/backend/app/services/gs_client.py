from __future__ import annotations

from typing import Any

import httpx

from shared.config import GS_SERVICE_BASE_URL, GS_SERVICE_TIMEOUT_SECONDS


class GsServiceError(RuntimeError):
    def __init__(self, detail: str, *, status_code: int = 502) -> None:
        super().__init__(detail)
        self.detail = detail
        self.status_code = status_code


class GsServiceClient:
    def __init__(self) -> None:
        self.base_url = GS_SERVICE_BASE_URL
        self.timeout = GS_SERVICE_TIMEOUT_SECONDS

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json_payload: dict[str, Any] | None = None,
        data_payload: dict[str, Any] | None = None,
        files_payload: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> Any:
        if not self.base_url:
            raise GsServiceError("GS_SERVICE_BASE_URL is not configured.", status_code=503)

        url = f"{self.base_url}{path}"
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.request(
                    method,
                    url,
                    json=json_payload,
                    data=data_payload,
                    files=files_payload,
                    params=params,
                )
        except httpx.ConnectError as exc:
            raise GsServiceError(
                f"Failed to connect to 3DGS service at {self.base_url}: {exc}",
                status_code=503,
            ) from exc
        except httpx.TimeoutException as exc:
            raise GsServiceError(
                f"3DGS service request timed out after {self.timeout:.1f}s.",
                status_code=504,
            ) from exc
        except httpx.HTTPError as exc:
            raise GsServiceError(f"3DGS service request failed: {exc}", status_code=502) from exc

        if response.status_code >= 400:
            detail: str
            try:
                payload = response.json()
            except ValueError:
                payload = None

            if isinstance(payload, dict) and payload.get("detail"):
                detail = str(payload["detail"])
            else:
                detail = response.text.strip() or f"3DGS service returned HTTP {response.status_code}."
            raise GsServiceError(detail, status_code=response.status_code)

        try:
            payload = response.json()
        except ValueError:
            return {}
        return payload

    async def create_task(
        self,
        *,
        title: str,
        description: str,
        price: str,
        video_filename: str,
        video_bytes: bytes,
        content_type: str | None = None,
    ) -> Any:
        return await self._request(
            "POST",
            "/tasks",
            data_payload={
                "title": title,
                "description": description,
                "price": price,
            },
            files_payload={
                "video": (
                    video_filename,
                    video_bytes,
                    content_type or "application/octet-stream",
                )
            },
        )

    async def get_task(self, task_id: str) -> Any:
        return await self._request("GET", f"/tasks/{task_id}")

    async def list_tasks(self, *, status: str | None = None) -> Any:
        params = {"status": status} if status else None
        return await self._request("GET", "/tasks", params=params)

    async def start_task(self, task_id: str, payload: dict[str, Any]) -> Any:
        return await self._request("POST", f"/tasks/{task_id}/start", json_payload=payload)

    async def cancel_task(self, task_id: str) -> Any:
        return await self._request("POST", f"/tasks/{task_id}/cancel")

    async def start_mask_debug(self, task_id: str) -> Any:
        return await self._request("POST", f"/tasks/{task_id}/mask-debug")

    async def preview_mask(self, task_id: str, payload: dict[str, Any]) -> Any:
        return await self._request("POST", f"/tasks/{task_id}/mask-preview", json_payload=payload)

    async def confirm_mask(self, task_id: str) -> Any:
        return await self._request("POST", f"/tasks/{task_id}/mask-confirm")

    async def update_viewer(self, task_id: str, payload: dict[str, Any]) -> Any:
        return await self._request("PUT", f"/tasks/{task_id}/viewer", json_payload=payload)

    async def delete_task(self, task_id: str) -> Any:
        return await self._request("DELETE", f"/tasks/{task_id}")


gs_client = GsServiceClient()
