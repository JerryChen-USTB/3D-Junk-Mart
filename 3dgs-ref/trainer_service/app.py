from __future__ import annotations

import sys
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from shared.config import (
    REPO_ROOT,
    STORAGE_ROOT,
    TRAINER_SERVICE_AUTH_TOKEN,
    TRAINER_SERVICE_PUBLIC_BASE_URL,
    VIEWER_ROOT,
)
from shared.task_status import PIPELINE_CANCELABLE_STATUSES
from shared.task_store import ensure_layout, get_task
from trainer_service.schemas import (
    InternalActionResponse,
    InternalMaskPreviewRequest,
    InternalPipelineStartRequest,
    MaskPreviewRequest,
    TaskResponse,
    TaskStartRequest,
    TrainerServiceHealthResponse,
    ViewerConfigResponse,
    ViewerConfigUpdate,
)
from trainer_service.services.runtime import (
    cancel_pipeline,
    generate_mask_preview,
    resume_after_mask,
    start_mask_debug,
    start_pipeline,
)
from trainer_service.services.task_api import (
    create_uploaded_task,
    delete_task_or_404,
    list_task_records,
    load_task_or_404,
    save_viewer_config,
    serialize_task,
)

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
    title="3DGS Trainer Service",
    version="0.2.0",
    summary="Remote 3DGS service for task management, training execution, and model hosting.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _require_internal_token(x_internal_token: str | None = Header(default=None)) -> None:
    if not TRAINER_SERVICE_AUTH_TOKEN:
        return
    if x_internal_token == TRAINER_SERVICE_AUTH_TOKEN:
        return
    raise HTTPException(status_code=401, detail="Invalid trainer service internal token.")


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


@app.get("/health", response_model=TrainerServiceHealthResponse)
def health() -> TrainerServiceHealthResponse:
    return TrainerServiceHealthResponse(
        status="ok",
        repo_root=str(REPO_ROOT),
        storage_root=str(STORAGE_ROOT),
        viewer_root=str(VIEWER_ROOT),
        python_executable=sys.executable,
        public_base_url=TRAINER_SERVICE_PUBLIC_BASE_URL,
    )


@app.post("/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    request: Request,
    title: str = Form(...),
    description: str = Form(""),
    price: str = Form(""),
    video: UploadFile = File(...),
) -> TaskResponse:
    task = create_uploaded_task(
        title=title,
        description=description,
        price=price,
        video=video,
    )
    return serialize_task(request, task)


@app.get("/tasks", response_model=list[TaskResponse])
def list_tasks(
    request: Request,
    status: str | None = None,
) -> list[TaskResponse]:
    return [serialize_task(request, task) for task in list_task_records(status_query=status)]


@app.get("/tasks/{task_id}", response_model=TaskResponse)
def get_task_detail(
    request: Request,
    task_id: str,
) -> TaskResponse:
    return serialize_task(request, load_task_or_404(task_id))


@app.post("/tasks/{task_id}/start", response_model=TaskResponse)
def start_public_task(
    request: Request,
    task_id: str,
    payload: TaskStartRequest,
) -> TaskResponse:
    start_pipeline(
        task_id,
        quality_profile_name=payload.quality_profile,
        train_max_steps=payload.train_max_steps,
        object_masking=payload.object_masking,
        mock_mode=payload.mock_mode,
    )
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return serialize_task(request, task)


@app.post("/tasks/{task_id}/cancel", response_model=TaskResponse)
def cancel_public_task(
    request: Request,
    task_id: str,
) -> TaskResponse:
    cancel_pipeline(task_id)
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return serialize_task(request, task)


@app.post("/tasks/{task_id}/mask-debug", response_model=TaskResponse)
def start_public_mask_debug(
    request: Request,
    task_id: str,
) -> TaskResponse:
    start_mask_debug(task_id)
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return serialize_task(request, task)


@app.post("/tasks/{task_id}/mask-preview", response_model=TaskResponse)
def preview_public_mask(
    request: Request,
    task_id: str,
    payload: MaskPreviewRequest,
) -> TaskResponse:
    generate_mask_preview(task_id, payload.points)
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return serialize_task(request, task)


@app.post("/tasks/{task_id}/mask-confirm", response_model=TaskResponse)
def confirm_public_mask(
    request: Request,
    task_id: str,
) -> TaskResponse:
    resume_after_mask(task_id)
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return serialize_task(request, task)


def _round_vec3(values: list[float]) -> list[float]:
    return [round(float(values[index]), 4) for index in range(3)]


@app.put("/tasks/{task_id}/viewer", response_model=ViewerConfigResponse)
def update_public_viewer_config(
    request: Request,
    task_id: str,
    payload: ViewerConfigUpdate,
) -> ViewerConfigResponse:
    task = load_task_or_404(task_id)
    if not task.get("model_rel_path"):
        raise HTTPException(status_code=400, detail="Task has no generated model.")

    patch: dict[str, object] = {}
    if payload.model_rotation_deg is not None:
        patch["model_rotation_deg"] = _round_vec3(payload.model_rotation_deg)
    if payload.model_translation is not None:
        patch["model_translation"] = _round_vec3(payload.model_translation)
    if payload.model_scale is not None:
        patch["model_scale"] = round(float(payload.model_scale), 6)
    if payload.camera_rotation_deg is not None:
        patch["camera_rotation_deg"] = _round_vec3(payload.camera_rotation_deg)
    if payload.camera_distance is not None:
        patch["camera_distance"] = round(float(payload.camera_distance), 6)

    viewer_config = save_viewer_config(task_id, patch)
    latest_task = load_task_or_404(task_id)
    return ViewerConfigResponse(
        task_id=task_id,
        viewer_config=viewer_config,
        task=serialize_task(request, latest_task),
    )


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_public_task(
    task_id: str,
) -> Response:
    task = load_task_or_404(task_id)
    if task.get("status") in PIPELINE_CANCELABLE_STATUSES:
        raise HTTPException(
            status_code=409,
            detail="Delete is disabled while the pipeline is active or waiting for mask interaction.",
        )
    delete_task_or_404(task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post("/internal/tasks/{task_id}/start", response_model=InternalActionResponse)
def start_task(
    task_id: str,
    payload: InternalPipelineStartRequest,
    _auth: None = Depends(_require_internal_token),
) -> InternalActionResponse:
    pipeline_pid = start_pipeline(
        task_id,
        quality_profile_name=payload.quality_profile,
        train_max_steps=payload.train_max_steps,
        object_masking=payload.object_masking,
        mock_mode=payload.mock_mode,
    )
    return InternalActionResponse(
        task_id=task_id,
        message="training started",
        pipeline_pid=pipeline_pid,
        worker_job_id=task_id,
    )


@app.post("/internal/tasks/{task_id}/cancel", response_model=InternalActionResponse)
def cancel_task(
    task_id: str,
    _auth: None = Depends(_require_internal_token),
) -> InternalActionResponse:
    killed_pids = cancel_pipeline(task_id)
    return InternalActionResponse(
        task_id=task_id,
        message="training cancelled",
        killed_pids=killed_pids,
    )


@app.post("/internal/tasks/{task_id}/mask-debug", response_model=InternalActionResponse)
def start_task_mask_debug(
    task_id: str,
    _auth: None = Depends(_require_internal_token),
) -> InternalActionResponse:
    start_mask_debug(task_id)
    return InternalActionResponse(
        task_id=task_id,
        message="mask debug started",
        worker_job_id=task_id,
    )


@app.post("/internal/tasks/{task_id}/mask-preview", response_model=InternalActionResponse)
def preview_task_mask(
    task_id: str,
    payload: InternalMaskPreviewRequest,
    _auth: None = Depends(_require_internal_token),
) -> InternalActionResponse:
    generate_mask_preview(task_id, payload.points)
    return InternalActionResponse(
        task_id=task_id,
        message="mask preview generated",
        worker_job_id=task_id,
    )


@app.post("/internal/tasks/{task_id}/resume", response_model=InternalActionResponse)
def resume_task(
    task_id: str,
    _auth: None = Depends(_require_internal_token),
) -> InternalActionResponse:
    pipeline_pid = resume_after_mask(task_id)
    return InternalActionResponse(
        task_id=task_id,
        message="mask-confirm resume started",
        pipeline_pid=pipeline_pid,
        worker_job_id=task_id,
    )
