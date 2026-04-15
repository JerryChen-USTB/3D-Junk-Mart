from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

from fastapi import HTTPException, Request, UploadFile

from shared.config import STORAGE_ROOT, TRAINER_SERVICE_PUBLIC_BASE_URL
from shared.task_status import MASK_INTERACTION_STATUSES, PIPELINE_ACTIVE_STATUSES
from shared.task_store import (
    atomic_write_json,
    build_task_record,
    create_task,
    delete_task,
    generate_task_id,
    get_task,
    list_tasks,
    task_model_dir,
    task_processed_dir,
    task_upload_dir,
)
from shared.training_config import object_masking_supported, resolve_quality_profile
from trainer_service.schemas import TaskResponse

DEFAULT_VIEWER_CONFIG = {
    "model_rotation_deg": [0, 0, 0],
    "model_translation": [0, 0, 0],
    "model_scale": 1.0,
    "camera_rotation_deg": [-18, 26, 0],
    "camera_distance": 1.6,
}
UPLOAD_VIDEO_MAX_DURATION_SECONDS = 60


def _probe_uploaded_video(video_path: Path) -> dict[str, object]:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_streams",
            "-show_format",
            str(video_path),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise HTTPException(
            status_code=400,
            detail=result.stderr.strip() or "视频元数据校验失败，请确认上传的是有效视频。",
        )

    try:
        metadata = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"无法解析视频元数据：{exc}") from exc

    if not isinstance(metadata, dict):
        raise HTTPException(status_code=400, detail="视频元数据格式不正确。")
    return metadata


def validate_uploaded_video(video_path: Path) -> dict[str, object]:
    metadata = _probe_uploaded_video(video_path)
    streams = metadata.get("streams")
    format_meta = metadata.get("format")
    if not isinstance(streams, list) or not isinstance(format_meta, dict):
        raise HTTPException(status_code=400, detail="视频元数据不完整。")

    video_stream = next(
        (
            stream
            for stream in streams
            if isinstance(stream, dict) and stream.get("codec_type") == "video"
        ),
        None,
    )
    if video_stream is None:
        raise HTTPException(status_code=400, detail="上传文件中未检测到有效视频流。")

    try:
        duration = float(format_meta.get("duration", 0) or 0)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="无法识别视频时长。") from exc

    if duration <= 0:
        raise HTTPException(status_code=400, detail="视频时长无效，请重新录制或选择视频。")
    if duration > UPLOAD_VIDEO_MAX_DURATION_SECONDS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"视频时长 {duration:.2f}s 超过 {UPLOAD_VIDEO_MAX_DURATION_SECONDS}s 限制。"
            ),
        )

    return metadata


def create_uploaded_task(
    *,
    title: str,
    description: str,
    price: str,
    video: UploadFile,
) -> dict[str, Any]:
    if not video.filename:
        raise HTTPException(status_code=400, detail="Missing video filename.")

    if video.content_type and not video.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Uploaded file must be a video.")

    task_id = generate_task_id()
    upload_dir = task_upload_dir(task_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    suffix = Path(video.filename).suffix.lower() or ".mp4"
    source_path = upload_dir / f"source{suffix}"

    try:
        with source_path.open("wb") as target:
            shutil.copyfileobj(video.file, target)
        video_metadata = validate_uploaded_video(source_path)
    except HTTPException:
        shutil.rmtree(upload_dir, ignore_errors=True)
        raise
    except Exception:
        shutil.rmtree(upload_dir, ignore_errors=True)
        raise

    task = build_task_record(
        task_id=task_id,
        title=title.strip(),
        description=description.strip(),
        price=price.strip(),
        source_filename=video.filename,
        video_path=source_path,
        video_metadata=video_metadata,
    )
    return create_task(task)


def load_task_or_404(task_id: str) -> dict[str, Any]:
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return task


def delete_task_or_404(task_id: str) -> None:
    load_task_or_404(task_id)
    delete_task(task_id)


def list_task_records(*, status_query: str | None = None) -> list[dict[str, Any]]:
    statuses = None
    if status_query:
        parsed = {item.strip() for item in status_query.split(",") if item.strip()}
        if parsed:
            statuses = parsed
    return list_tasks(statuses=statuses)


def _absolute_url(request: Request, rel_url: str | None) -> str | None:
    if not rel_url:
        return None

    if rel_url.startswith("http://") or rel_url.startswith("https://"):
        return rel_url

    base = TRAINER_SERVICE_PUBLIC_BASE_URL or str(request.base_url).rstrip("/")
    absolute = f"{base}{rel_url}"
    if not rel_url.startswith("/storage/"):
        return absolute

    storage_path = STORAGE_ROOT / rel_url.removeprefix("/storage/")
    try:
        stat = storage_path.stat()
    except OSError:
        return absolute

    separator = "&" if "?" in absolute else "?"
    return f"{absolute}{separator}v={stat.st_mtime_ns}_{stat.st_size}"


def _load_viewer_config(task_id: str) -> dict[str, Any]:
    metadata_path = task_model_dir(task_id) / "viewer.json"
    if not metadata_path.exists():
        return {}

    try:
        payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, TypeError, ValueError):
        return {}

    payload = payload if isinstance(payload, dict) else {}
    merged = dict(DEFAULT_VIEWER_CONFIG)
    merged.update(payload)
    return merged


def _processed_dataset_dir(task_id: str) -> Path:
    return task_processed_dir(task_id) / "dataset"


def _task_quality_profile(task: dict[str, Any]):
    return resolve_quality_profile(task.get("quality_profile"))


def _has_mask_debug_dataset(task_id: str) -> bool:
    dataset_dir = _processed_dataset_dir(task_id)
    return (
        dataset_dir.exists()
        and (dataset_dir / "transforms.json").exists()
        and (dataset_dir / "images").is_dir()
    )


def can_debug_masking(task: dict[str, Any]) -> bool:
    status_value = task.get("status")
    if status_value in PIPELINE_ACTIVE_STATUSES or status_value in MASK_INTERACTION_STATUSES:
        return False
    quality_name = task.get("quality_profile")
    if not quality_name:
        return False
    try:
        quality_profile = _task_quality_profile(task)
    except ValueError:
        return False
    if not object_masking_supported(quality_profile):
        return False
    return _has_mask_debug_dataset(task["task_id"])


def save_viewer_config(task_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    metadata_path = task_model_dir(task_id) / "viewer.json"
    current = _load_viewer_config(task_id) or dict(DEFAULT_VIEWER_CONFIG)
    current.update(payload)
    atomic_write_json(metadata_path, current)
    return current


def serialize_task(request: Request, task: dict[str, Any]) -> TaskResponse:
    model_rel_url = task.get("model_rel_path")
    viewer_config = _load_viewer_config(task["task_id"]) if task.get("task_id") else {}

    return TaskResponse(
        task_id=task["task_id"],
        title=task.get("title", ""),
        description=task.get("description", ""),
        price=task.get("price", ""),
        status=task.get("status", "uploaded"),
        progress=int(task.get("progress", 0)),
        status_message=task.get("status_message"),
        error_message=task.get("error_message"),
        created_at=task.get("created_at", ""),
        updated_at=task.get("updated_at", ""),
        video_url=_absolute_url(request, task.get("video_rel_path")),
        model_url=_absolute_url(request, model_rel_url),
        model_ply_url=_absolute_url(request, task.get("model_ply_rel_path")),
        model_sog_url=_absolute_url(request, task.get("model_sog_rel_path")),
        model_format=task.get("model_format"),
        viewer_url=None,
        viewer_config=viewer_config or None,
        log_url=_absolute_url(request, task.get("log_rel_path")),
        log_tail=list(task.get("log_tail") or []),
        train_step=task.get("train_step"),
        train_total_steps=task.get("train_total_steps"),
        train_eta=task.get("train_eta"),
        train_max_steps=task.get("train_max_steps"),
        quality_profile=task.get("quality_profile"),
        object_masking=bool(task.get("object_masking", False)),
        mask_prompt_frame_url=_absolute_url(request, task.get("mask_prompt_frame_rel_path")),
        mask_prompt_frame_name=task.get("mask_prompt_frame_name"),
        mask_prompt_frame_width=task.get("mask_prompt_frame_width"),
        mask_prompt_frame_height=task.get("mask_prompt_frame_height"),
        mask_prompts_url=_absolute_url(request, task.get("mask_prompts_rel_path")),
        mask_preview_url=_absolute_url(request, task.get("mask_preview_rel_path")),
        mask_preview_manifest_url=_absolute_url(request, task.get("mask_preview_manifest_rel_path")),
        mask_summary_url=_absolute_url(request, task.get("mask_summary_rel_path")),
        can_debug_masking=can_debug_masking(task),
        pipeline_pid=task.get("pipeline_pid"),
        mock_mode=bool(task.get("mock_mode", False)),
        is_published=bool(task.get("is_published", False)),
        published_at=task.get("published_at"),
        viewer_rotation_done=bool(task.get("viewer_rotation_done", False)),
        viewer_translation_done=bool(task.get("viewer_translation_done", False)),
        viewer_initial_view_done=bool(task.get("viewer_initial_view_done", False)),
        viewer_animation_approved=bool(task.get("viewer_animation_approved", False)),
    )
