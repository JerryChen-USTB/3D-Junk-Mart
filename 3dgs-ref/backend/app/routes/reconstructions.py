from __future__ import annotations

import os

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile, status

from backend.app.schemas import (
    MaskPromptRequest,
    PipelineStartRequest,
    PublishFlowStateUpdate,
    ReconstructionTaskResponse,
    ViewerConfigResponse,
    ViewerConfigUpdate,
)
from backend.app.services.gs_client import GsServiceError, gs_client
from backend.app.services.reconstruction_mirror import serialize_mirror_task, upsert_remote_task, upsert_remote_tasks
from shared.task_status import PIPELINE_CANCELABLE_STATUSES
from shared.task_store import delete_task as delete_local_task, get_task, now_iso, update_task
from shared.training_config import object_masking_supported, resolve_quality_profile, resolve_train_max_steps

router = APIRouter(prefix="/api/v1/reconstructions", tags=["reconstructions"])

AUTO_START_PIPELINE = False
AUTO_START_PIPELINE_MOCK = os.getenv("BACKEND_PIPELINE_MOCK", "false").lower() == "true"


def _raise_http_from_gs(exc: GsServiceError) -> None:
    raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc

async def _refresh_remote_task(task_id: str) -> dict:
    try:
        remote_task = await gs_client.get_task(task_id)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)
    return upsert_remote_task(remote_task)


async def _ensure_local_or_remote_task(task_id: str) -> dict:
    local_task = get_task(task_id)
    if local_task is not None:
        return local_task
    return await _refresh_remote_task(task_id)


@router.post("", response_model=ReconstructionTaskResponse, status_code=status.HTTP_201_CREATED)
async def create_reconstruction(
    request: Request,
    title: str = Form(...),
    description: str = Form(""),
    price: str = Form(""),
    video: UploadFile = File(...),
) -> ReconstructionTaskResponse:
    if not video.filename:
        raise HTTPException(status_code=400, detail="Missing video filename.")
    if video.content_type and not video.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be a video.")

    video_bytes = await video.read()
    if not video_bytes:
        raise HTTPException(status_code=400, detail="Uploaded video is empty.")

    try:
        remote_task = await gs_client.create_task(
            title=title.strip(),
            description=description.strip(),
            price=price.strip(),
            video_filename=video.filename,
            video_bytes=video_bytes,
            content_type=video.content_type,
        )
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/pipeline/start", response_model=ReconstructionTaskResponse)
async def start_reconstruction_pipeline(
    request: Request,
    task_id: str,
    payload: PipelineStartRequest,
) -> ReconstructionTaskResponse:
    try:
        quality_profile = resolve_quality_profile(payload.quality_profile)
        train_max_steps = resolve_train_max_steps(payload.train_max_steps)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if payload.object_masking and not object_masking_supported(quality_profile):
        raise HTTPException(
            status_code=400,
            detail="Object masking is disabled for the raw profile in the MVP because mask generation at full resolution is too expensive.",
        )

    mock_mode = AUTO_START_PIPELINE_MOCK if payload.mock_mode is None else payload.mock_mode

    try:
        remote_task = await gs_client.start_task(
            task_id,
            {
                "quality_profile": quality_profile.name,
                "train_max_steps": train_max_steps,
                "object_masking": payload.object_masking,
                "mock_mode": mock_mode,
            },
        )
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/pipeline/cancel", response_model=ReconstructionTaskResponse)
async def cancel_reconstruction_pipeline(request: Request, task_id: str) -> ReconstructionTaskResponse:
    try:
        remote_task = await gs_client.cancel_task(task_id)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/mask-debug", response_model=ReconstructionTaskResponse)
async def start_mask_debug(request: Request, task_id: str) -> ReconstructionTaskResponse:
    try:
        remote_task = await gs_client.start_mask_debug(task_id)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/mask-prompts", response_model=ReconstructionTaskResponse)
@router.post("/{task_id}/mask-preview", response_model=ReconstructionTaskResponse)
async def preview_mask_prompts(
    request: Request,
    task_id: str,
    payload: MaskPromptRequest,
) -> ReconstructionTaskResponse:
    if not payload.points:
        raise HTTPException(status_code=400, detail="At least one mask prompt point is required.")
    if not any(point.label == 1 for point in payload.points):
        raise HTTPException(status_code=400, detail="At least one positive object point is required.")

    try:
        remote_task = await gs_client.preview_mask(
            task_id,
            {
                "points": [
                    point.model_dump() if hasattr(point, "model_dump") else point.dict()
                    for point in payload.points
                ],
            },
        )
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/mask-confirm", response_model=ReconstructionTaskResponse)
async def confirm_mask_preview(request: Request, task_id: str) -> ReconstructionTaskResponse:
    try:
        remote_task = await gs_client.confirm_mask(task_id)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    mirrored_task = upsert_remote_task(remote_task)
    return serialize_mirror_task(request, mirrored_task)


@router.get("/{task_id}", response_model=ReconstructionTaskResponse)
async def get_reconstruction(request: Request, task_id: str) -> ReconstructionTaskResponse:
    mirrored_task = await _refresh_remote_task(task_id)
    return serialize_mirror_task(request, mirrored_task)


@router.post("/{task_id}/publish", response_model=ReconstructionTaskResponse)
async def publish_reconstruction(request: Request, task_id: str) -> ReconstructionTaskResponse:
    task = await _refresh_remote_task(task_id)

    if task.get("status") != "ready":
        raise HTTPException(
            status_code=409,
            detail=f"Only ready tasks can be published, current status is {task.get('status')}.",
        )
    if not task.get("model_url"):
        raise HTTPException(status_code=400, detail="Task has no generated viewer or model URL.")

    updated_task = update_task(
        task_id,
        is_published=True,
        published_at=task.get("published_at") or now_iso(),
    )
    return serialize_mirror_task(request, updated_task)


@router.put("/{task_id}/publish-flow", response_model=ReconstructionTaskResponse)
async def update_publish_flow_state(
    request: Request,
    task_id: str,
    payload: PublishFlowStateUpdate,
) -> ReconstructionTaskResponse:
    task = await _ensure_local_or_remote_task(task_id)

    changes = {}
    if payload.viewer_rotation_done is not None:
        changes["viewer_rotation_done"] = payload.viewer_rotation_done
    if payload.viewer_translation_done is not None:
        changes["viewer_translation_done"] = payload.viewer_translation_done
    if payload.viewer_initial_view_done is not None:
        changes["viewer_initial_view_done"] = payload.viewer_initial_view_done
    if payload.viewer_animation_approved is not None:
        changes["viewer_animation_approved"] = payload.viewer_animation_approved

    if not changes:
        return serialize_mirror_task(request, task)

    updated_task = update_task(task_id, **changes)
    return serialize_mirror_task(request, updated_task)


@router.put("/{task_id}/viewer", response_model=ViewerConfigResponse)
async def update_viewer_config(
    request: Request,
    task_id: str,
    payload: ViewerConfigUpdate,
) -> ViewerConfigResponse:
    await _ensure_local_or_remote_task(task_id)
    try:
        response_payload = await gs_client.update_viewer(
            task_id,
            {
                "model_rotation_deg": payload.model_rotation_deg,
                "model_translation": payload.model_translation,
                "model_scale": payload.model_scale,
                "camera_rotation_deg": payload.camera_rotation_deg,
                "camera_distance": payload.camera_distance,
            },
        )
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    if not isinstance(response_payload, dict):
        raise HTTPException(status_code=502, detail="3DGS service returned an invalid viewer config payload.")

    remote_task = response_payload.get("task")
    viewer_config = response_payload.get("viewer_config")
    if not isinstance(remote_task, dict) or not isinstance(viewer_config, dict):
        raise HTTPException(status_code=502, detail="3DGS service returned an incomplete viewer config payload.")

    latest_task = upsert_remote_task(remote_task)
    return ViewerConfigResponse(
        task_id=task_id,
        viewer_config=viewer_config,
        task=serialize_mirror_task(request, latest_task),
    )


@router.get("", response_model=list[ReconstructionTaskResponse])
async def list_reconstructions(
    request: Request,
    status: str | None = None,
) -> list[ReconstructionTaskResponse]:
    try:
        remote_tasks = await gs_client.list_tasks(status=status)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    if not isinstance(remote_tasks, list):
        raise HTTPException(status_code=502, detail="3DGS service returned an invalid task list payload.")

    mirrored_tasks = upsert_remote_tasks(task for task in remote_tasks if isinstance(task, dict))
    return [serialize_mirror_task(request, task) for task in mirrored_tasks]


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reconstruction(task_id: str) -> Response:
    local_task = get_task(task_id)

    try:
        remote_task = await gs_client.get_task(task_id)
    except GsServiceError as exc:
        if exc.status_code != 404:
            _raise_http_from_gs(exc)
        if local_task is None:
            raise HTTPException(status_code=404, detail="Task not found.") from exc
        try:
            delete_local_task(task_id)
        except FileNotFoundError as delete_exc:
            raise HTTPException(status_code=404, detail="Task not found.") from delete_exc
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    mirrored_task = upsert_remote_task(remote_task)
    if mirrored_task.get("status") in PIPELINE_CANCELABLE_STATUSES:
        raise HTTPException(
            status_code=409,
            detail="Delete is disabled while the pipeline is active or waiting for mask interaction.",
        )

    try:
        await gs_client.delete_task(task_id)
    except GsServiceError as exc:
        _raise_http_from_gs(exc)

    if get_task(task_id) is not None:
        try:
            delete_local_task(task_id)
        except FileNotFoundError:
            pass

    return Response(status_code=status.HTTP_204_NO_CONTENT)
