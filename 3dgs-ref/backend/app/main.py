from __future__ import annotations

import mimetypes
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backend.app.routes.reconstructions import AUTO_START_PIPELINE, router as reconstructions_router
from backend.app.schemas import HealthResponse
from shared.config import GS_SERVICE_BASE_URL, STORAGE_ROOT, TRAINER_SERVICE_BASE_URL, VIEWER_ROOT
from shared.task_store import ensure_layout

mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("application/wasm", ".wasm")

ensure_layout()


class CacheControlledStaticFiles(StaticFiles):
    def __init__(self, *args, cache_control_by_extension: dict[str, str] | None = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.cache_control_by_extension = cache_control_by_extension or {}

    async def get_response(self, path: str, scope):
        response = await super().get_response(path, scope)
        cache_control = self.cache_control_by_extension.get(Path(path).suffix.lower())
        if cache_control and response.status_code < 400:
            response.headers["Cache-Control"] = cache_control
        return response


app = FastAPI(
    title="3DGS Marketplace MVP",
    version="0.1.0",
    summary="Local MVP backend for video upload, task status, and viewer hosting.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(reconstructions_router)

app.mount(
    "/storage",
    CacheControlledStaticFiles(
        directory=STORAGE_ROOT,
        cache_control_by_extension={
            ".ply": "public, max-age=604800",
            ".sog": "public, max-age=604800",
        },
    ),
    name="storage",
)
app.mount(
    "/viewer",
    CacheControlledStaticFiles(
        directory=VIEWER_ROOT,
        html=True,
        cache_control_by_extension={
            ".css": "public, max-age=31536000, immutable",
            ".html": "no-cache",
            ".js": "public, max-age=31536000, immutable",
            ".mjs": "public, max-age=31536000, immutable",
        },
    ),
    name="viewer",
)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        storage_root=str(STORAGE_ROOT),
        viewer_root=str(VIEWER_ROOT),
        gs_service_base_url=GS_SERVICE_BASE_URL,
        trainer_service_base_url=TRAINER_SERVICE_BASE_URL,
        auto_start_pipeline=AUTO_START_PIPELINE,
        viewer_proxy_mode="local-static",
    )
