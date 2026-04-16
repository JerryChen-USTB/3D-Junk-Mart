from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, Request
from fastapi import HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backend.app.http import error, http_exception_response, validation_error_details
from backend.app.routes.marketplace import router as marketplace_router
from backend.app.routes.reconstructions import router as reconstructions_router
from backend.app.schemas import HealthResponse
from backend.app.services.marketplace_store import get_store
from shared.task_store import ensure_layout
from shared.config import GS_SERVICE_BASE_URL, STORAGE_ROOT, VIEWER_ROOT

STORAGE_ROOT.mkdir(parents=True, exist_ok=True)
VIEWER_ROOT.mkdir(parents=True, exist_ok=True)
(STORAGE_ROOT / "uploads").mkdir(parents=True, exist_ok=True)


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
    title="3dv-junk-mart Marketplace Backend",
    version="0.1.0",
    summary="SQLite-backed marketplace backend with remote 3DGS service integration.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(marketplace_router)
app.include_router(reconstructions_router)


@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc: HTTPException):
    return http_exception_response(request, exc)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request, exc: RequestValidationError):
    return error(
        request,
        message="请求参数校验失败。",
        status_code=422,
        details=validation_error_details(exc),
    )


@app.on_event("startup")
def startup() -> None:
    ensure_layout()
    get_store()


# ---------------------------------------------------------------------------
# Reverse proxy: forward /proxy/storage/... requests to the remote trainer
# service so that the phone (connected via USB to localhost) can access
# model files hosted on the remote server without a direct connection.
# ---------------------------------------------------------------------------
import httpx
from fastapi.responses import StreamingResponse

_proxy_client: httpx.AsyncClient | None = None


def _get_proxy_client() -> httpx.AsyncClient:
    global _proxy_client
    if _proxy_client is None or _proxy_client.is_closed:
        _proxy_client = httpx.AsyncClient(timeout=120.0)
    return _proxy_client


@app.on_event("shutdown")
async def _close_proxy_client() -> None:
    global _proxy_client
    if _proxy_client is not None:
        await _proxy_client.aclose()
        _proxy_client = None


@app.api_route("/proxy/storage/{path:path}", methods=["GET", "HEAD"])
async def proxy_remote_storage(path: str, request: Request):
    """Proxy storage file requests to the remote trainer service."""
    remote_url = f"{GS_SERVICE_BASE_URL.rstrip('/')}/storage/{path}"

    # Forward query string (e.g. cache-busting ?v=...)
    if request.url.query:
        remote_url += f"?{request.url.query}"

    client = _get_proxy_client()
    try:
        remote_response = await client.request(
            method=request.method,
            url=remote_url,
            headers={
                k: v for k, v in request.headers.items()
                if k.lower() not in ("host", "connection")
            },
        )
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Failed to reach trainer service: {exc}")

    # Stream the response back to the client
    response_headers = dict(remote_response.headers)
    # Remove hop-by-hop headers
    for header in ("transfer-encoding", "connection", "keep-alive"):
        response_headers.pop(header, None)

    # Add CORS headers for WebView cross-origin requests
    response_headers["Access-Control-Allow-Origin"] = "*"

    return StreamingResponse(
        content=remote_response.aiter_bytes(chunk_size=65536),
        status_code=remote_response.status_code,
        headers=response_headers,
        media_type=response_headers.get("content-type"),
    )

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
        },
    ),
    name="viewer",
)


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse.model_validate(get_store().health_snapshot())
