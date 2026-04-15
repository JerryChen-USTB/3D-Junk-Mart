from __future__ import annotations

from typing import Any, Iterable, Mapping
from urllib.parse import urlencode

from fastapi import Request

from backend.app.schemas import ReconstructionTaskResponse
from shared.task_store import create_task, get_task, now_iso, update_task

VIEWER_BUILD_VERSION = "20260409_44"

REMOTE_TASK_FIELDS = (
    "title",
    "description",
    "price",
    "status",
    "progress",
    "status_message",
    "error_message",
    "created_at",
    "updated_at",
    "video_url",
    "model_url",
    "model_ply_url",
    "model_sog_url",
    "model_format",
    "viewer_url",
    "viewer_config",
    "log_url",
    "log_tail",
    "train_step",
    "train_total_steps",
    "train_eta",
    "train_max_steps",
    "quality_profile",
    "object_masking",
    "mask_prompt_frame_url",
    "mask_prompt_frame_name",
    "mask_prompt_frame_width",
    "mask_prompt_frame_height",
    "mask_prompts_url",
    "mask_preview_url",
    "mask_preview_manifest_url",
    "mask_summary_url",
    "can_debug_masking",
    "pipeline_pid",
    "mock_mode",
)

BUSINESS_DEFAULTS: dict[str, Any] = {
    "is_published": False,
    "published_at": None,
    "viewer_rotation_done": False,
    "viewer_translation_done": False,
    "viewer_initial_view_done": False,
    "viewer_animation_approved": False,
}


def _normalize_remote_task(remote_task: Mapping[str, Any]) -> dict[str, Any]:
    task_id = str(remote_task.get("task_id") or "").strip()
    if not task_id:
        raise ValueError("Remote task payload is missing task_id.")

    payload: dict[str, Any] = {"task_id": task_id}
    for field in REMOTE_TASK_FIELDS:
        payload[field] = remote_task.get(field)

    payload["progress"] = int(payload.get("progress") or 0)
    payload["log_tail"] = list(payload.get("log_tail") or [])
    payload["object_masking"] = bool(payload.get("object_masking", False))
    payload["can_debug_masking"] = bool(payload.get("can_debug_masking", False))
    payload["mock_mode"] = bool(payload.get("mock_mode", False))
    payload["viewer_config"] = (
        dict(payload["viewer_config"]) if isinstance(payload.get("viewer_config"), Mapping) else None
    )
    return payload


def upsert_remote_task(remote_task: Mapping[str, Any]) -> dict[str, Any]:
    payload = _normalize_remote_task(remote_task)
    existing = get_task(payload["task_id"])

    for field, default in BUSINESS_DEFAULTS.items():
        payload[field] = existing.get(field, default) if existing else default

    payload["remote_synced_at"] = now_iso()

    if existing is None:
        return create_task(payload)
    changes = dict(payload)
    changes.pop("task_id", None)
    return update_task(payload["task_id"], **changes)


def upsert_remote_tasks(remote_tasks: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return [upsert_remote_task(remote_task) for remote_task in remote_tasks]


def _append_viewer_param(query: dict[str, str], key: str, value: object | None) -> None:
    if value is None:
        return
    query[key] = str(value)


def _viewer_query_from_config(viewer_config: Mapping[str, Any] | None) -> dict[str, str]:
    if not isinstance(viewer_config, Mapping):
        return {}

    query: dict[str, str] = {}

    model_rotation = viewer_config.get("model_rotation_deg")
    if isinstance(model_rotation, list) and len(model_rotation) >= 3:
        _append_viewer_param(query, "model_rx", model_rotation[0])
        _append_viewer_param(query, "model_ry", model_rotation[1])
        _append_viewer_param(query, "model_rz", model_rotation[2])

    model_translation = viewer_config.get("model_translation")
    if isinstance(model_translation, list) and len(model_translation) >= 3:
        _append_viewer_param(query, "model_tx", model_translation[0])
        _append_viewer_param(query, "model_ty", model_translation[1])
        _append_viewer_param(query, "model_tz", model_translation[2])

    _append_viewer_param(query, "model_scale", viewer_config.get("model_scale"))

    camera_rotation = viewer_config.get("camera_rotation_deg")
    if isinstance(camera_rotation, list) and len(camera_rotation) >= 3:
        _append_viewer_param(query, "cam_rx", camera_rotation[0])
        _append_viewer_param(query, "cam_ry", camera_rotation[1])
        _append_viewer_param(query, "cam_rz", camera_rotation[2])

    _append_viewer_param(query, "cam_dist", viewer_config.get("camera_distance"))
    return query


def _build_local_viewer_url(request: Request, task: Mapping[str, Any]) -> str | None:
    model_url = task.get("model_url")
    if not model_url:
        return None

    query = {
        "task_id": str(task.get("task_id") or ""),
        "model": str(model_url),
        "viewer_build": VIEWER_BUILD_VERSION,
    }
    query.update(_viewer_query_from_config(task.get("viewer_config")))
    base = str(request.base_url).rstrip("/")
    serialized = urlencode(query)
    return f"{base}/viewer/index.html?{serialized}" if serialized else f"{base}/viewer/index.html"


def serialize_mirror_task(request: Request, task: Mapping[str, Any]) -> ReconstructionTaskResponse:
    payload = dict(task)
    payload["viewer_url"] = _build_local_viewer_url(request, task)
    return ReconstructionTaskResponse.model_validate(payload)
