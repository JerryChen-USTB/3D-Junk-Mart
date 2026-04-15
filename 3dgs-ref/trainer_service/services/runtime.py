from __future__ import annotations

import json
import os
import signal
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from shared.config import REPO_ROOT, STORAGE_ROOT
from shared.task_status import (
    MASK_INTERACTION_STATUSES,
    PIPELINE_ACTIVE_STATUSES,
    PIPELINE_CANCELABLE_STATUSES,
    PIPELINE_STARTABLE_STATUSES,
)
from shared.task_store import (
    atomic_write_json,
    get_task,
    path_to_storage_url,
    task_processed_dir,
    update_task,
)
from shared.training_config import (
    adapt_quality_profile_to_video,
    object_masking_supported,
    resolve_quality_profile,
    resolve_train_max_steps,
    restore_effective_quality_profile,
)
from trainer.pipeline import (
    PipelineReporter,
    build_sam2_preview_command,
    format_command_failure,
    run_logged_streaming_command,
    select_mask_prompt_frame,
)


def _get_task_or_404(task_id: str) -> dict[str, Any]:
    task = get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found.")
    return task


def _task_input_video_path(task: dict[str, Any]) -> Path:
    video_rel_path = task.get("video_rel_path")
    if not video_rel_path:
        raise HTTPException(status_code=400, detail="Task has no uploaded video.")
    if not video_rel_path.startswith("/storage/"):
        raise HTTPException(status_code=400, detail="Task video path is invalid.")

    input_video = STORAGE_ROOT / video_rel_path.removeprefix("/storage/")
    if not input_video.exists():
        raise HTTPException(status_code=404, detail="Uploaded video file not found.")
    return input_video


def _kill_process_tree(pid: int) -> None:
    if os.name == "nt":
        result = subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
        output = "\n".join(part for part in (result.stdout, result.stderr) if part)
        normalized_output = output.lower()
        not_found_markers = ("not found", "not running", "找不到", "未找到", "不存在")
        if result.returncode != 0 and not any(marker in normalized_output for marker in not_found_markers):
            raise RuntimeError(output.strip() or f"taskkill failed for PID {pid}.")
        return

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return


def _find_windows_task_pids(task_id: str) -> list[int]:
    escaped_task_id = task_id.replace("'", "''")
    script = (
        "Get-CimInstance Win32_Process | "
        f"Where-Object {{ $_.CommandLine -like '*{escaped_task_id}*' -and $_.ProcessId -ne $PID }} | "
        "Select-Object -ExpandProperty ProcessId"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []

    pids: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pids.append(int(line))
        except ValueError:
            continue
    return pids


def _find_task_process_pids(task_id: str, stored_pid: int | None) -> list[int]:
    pids: list[int] = []
    if stored_pid is not None:
        pids.append(stored_pid)
    if os.name == "nt":
        pids.extend(_find_windows_task_pids(task_id))
    return sorted(set(pids), reverse=True)


def _terminate_task_processes(task_id: str, stored_pid: int | None) -> list[int]:
    pids = _find_task_process_pids(task_id, stored_pid)
    killed: list[int] = []
    errors: list[str] = []

    for pid in pids:
        try:
            _kill_process_tree(pid)
            killed.append(pid)
        except RuntimeError as exc:
            errors.append(f"PID {pid}: {exc}")

    if errors and not killed:
        raise RuntimeError("; ".join(errors))
    return killed


def _start_pipeline_subprocess(
    task_id: str,
    input_video: Path,
    *,
    quality_profile: str,
    train_max_steps: int,
    object_masking: bool,
    mock_mode: bool,
    resume_after_mask: bool = False,
) -> int:
    command = [
        sys.executable,
        "-m",
        "trainer.pipeline",
        "--task-id",
        task_id,
        "--input-video",
        str(input_video),
        "--output-root",
        str(STORAGE_ROOT),
        "--quality-profile",
        quality_profile,
        "--train-max-steps",
        str(train_max_steps),
    ]

    if mock_mode:
        command.append("--mock")
    if object_masking:
        command.append("--object-masking")
    if resume_after_mask:
        command.append("--resume-after-mask")

    process = subprocess.Popen(
        command,
        cwd=str(REPO_ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
    )
    return int(process.pid)


def _mask_preview_frames_dir(task_id: str) -> Path:
    return task_processed_dir(task_id) / "mask_preview_frames"


def _mask_preview_manifest_path(task_id: str) -> Path:
    return task_processed_dir(task_id) / "mask_preview_manifest.json"


def _mask_preview_frame_path(task_id: str, frame_name: str) -> Path:
    return _mask_preview_frames_dir(task_id) / f"{Path(frame_name).stem}.jpg"


def _mask_prompts_path(task_id: str) -> Path:
    return task_processed_dir(task_id) / "mask_prompts.json"


def _processed_dataset_dir(task_id: str) -> Path:
    return task_processed_dir(task_id) / "dataset"


def _task_quality_profile(task: dict[str, Any]):
    return resolve_quality_profile(task.get("quality_profile"))


def _task_effective_quality_profile(task: dict[str, Any]):
    requested_profile = _task_quality_profile(task)
    restored_profile = restore_effective_quality_profile(task, requested_profile)
    if restored_profile is not None:
        return restored_profile

    video_metadata = task.get("video_metadata")
    if isinstance(video_metadata, dict):
        return adapt_quality_profile_to_video(video_metadata, requested_profile)

    return requested_profile


def _write_mask_prompts(task_id: str, task: dict[str, Any], points: list[Any]) -> Path:
    prompt_frame_name = task.get("mask_prompt_frame_name")
    if not prompt_frame_name:
        raise HTTPException(status_code=400, detail="Task has no mask prompt frame.")

    prompts_path = _mask_prompts_path(task_id)
    prompts_payload = {
        "task_id": task_id,
        "prompt_frame_name": prompt_frame_name,
        "prompt_frame_rel_path": task.get("mask_prompt_frame_rel_path"),
        "points": [
            point.model_dump() if hasattr(point, "model_dump") else point.dict() if hasattr(point, "dict") else point
            for point in points
        ],
    }
    atomic_write_json(prompts_path, prompts_payload)
    return prompts_path


def _clear_mask_debug_artifacts(task_id: str) -> None:
    dataset_dir = _processed_dataset_dir(task_id)

    for path in (
        _mask_prompts_path(task_id),
        task_processed_dir(task_id) / "mask_preview_overlay.png",
        _mask_preview_manifest_path(task_id),
        dataset_dir / "mask_summary.json",
    ):
        try:
            path.unlink(missing_ok=True)
        except OSError:
            continue

    for directory in (
        _mask_preview_frames_dir(task_id),
        dataset_dir / "masks",
        dataset_dir / "masks_2",
        dataset_dir / "masks_4",
    ):
        try:
            shutil.rmtree(directory)
        except OSError:
            continue


def _can_debug_masking(task: dict[str, Any]) -> bool:
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

    dataset_dir = _processed_dataset_dir(task["task_id"])
    return (
        dataset_dir.exists()
        and (dataset_dir / "transforms.json").exists()
        and (dataset_dir / "images").is_dir()
    )


def start_pipeline(
    task_id: str,
    *,
    quality_profile_name: str,
    train_max_steps: int,
    object_masking: bool,
    mock_mode: bool,
) -> int:
    task = _get_task_or_404(task_id)
    current_status = task.get("status")
    can_start_from_queued = current_status == "queued" and task.get("pipeline_pid") in {None, "", 0}
    if current_status not in PIPELINE_STARTABLE_STATUSES and not can_start_from_queued:
        raise HTTPException(
            status_code=409,
            detail=(
                "Pipeline can only be started from uploaded, failed, or cancelled status, "
                f"current status is {current_status}."
            ),
        )

    try:
        quality_profile = resolve_quality_profile(quality_profile_name).name
        train_steps = resolve_train_max_steps(train_max_steps)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if object_masking and not object_masking_supported(resolve_quality_profile(quality_profile)):
        raise HTTPException(
            status_code=400,
            detail="Object masking is disabled for the raw profile in the MVP because mask generation at full resolution is too expensive.",
        )

    input_video = _task_input_video_path(task)
    update_task(
        task_id,
        status="queued",
        progress=0,
        status_message="训练配置已确认，正在启动流水线",
        error_message=None,
        model_rel_path=None,
        model_ply_rel_path=None,
        model_sog_rel_path=None,
        model_format=None,
        log_rel_path=None,
        log_tail=[],
        train_step=None,
        train_total_steps=None,
        train_eta=None,
        train_max_steps=train_steps,
        quality_profile=quality_profile,
        object_masking=object_masking,
        mask_prompt_frame_rel_path=None,
        mask_prompt_frame_name=None,
        mask_prompt_frame_width=None,
        mask_prompt_frame_height=None,
        mask_prompts_rel_path=None,
        mask_preview_rel_path=None,
        mask_preview_manifest_rel_path=None,
        mask_summary_rel_path=None,
        pipeline_pid=None,
        mock_mode=mock_mode,
        viewer_rotation_done=False,
        viewer_translation_done=False,
        viewer_initial_view_done=False,
        viewer_animation_approved=False,
    )

    try:
        pipeline_pid = _start_pipeline_subprocess(
            task_id,
            input_video,
            quality_profile=quality_profile,
            train_max_steps=train_steps,
            object_masking=object_masking,
            mock_mode=mock_mode,
        )
    except OSError as exc:
        update_task(
            task_id,
            status="failed",
            progress=100,
            status_message="流水线启动失败",
            error_message=str(exc),
            pipeline_pid=None,
        )
        raise HTTPException(status_code=500, detail=f"Failed to start pipeline: {exc}") from exc

    update_task(task_id, pipeline_pid=pipeline_pid)
    return pipeline_pid


def cancel_pipeline(task_id: str) -> list[int]:
    task = _get_task_or_404(task_id)
    current_status = task.get("status")

    if current_status == "cancelled":
        return []
    if current_status not in PIPELINE_CANCELABLE_STATUSES:
        raise HTTPException(
            status_code=409,
            detail=f"Pipeline can only be cancelled while active, current status is {current_status}.",
        )

    stored_pid = task.get("pipeline_pid")
    try:
        parsed_pid = int(stored_pid) if stored_pid is not None else None
    except (TypeError, ValueError):
        parsed_pid = None

    try:
        killed_pids = _terminate_task_processes(task_id, parsed_pid)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=f"Failed to terminate pipeline: {exc}") from exc

    message = "流水线已终止"
    if killed_pids:
        message = f"流水线已终止，已结束进程 {', '.join(str(pid) for pid in killed_pids)}"
    else:
        message = "未找到运行中的流水线进程，已标记任务为已终止"

    update_task(
        task_id,
        status="cancelled",
        progress=int(task.get("progress") or 0),
        status_message=message,
        error_message=None,
        pipeline_pid=None,
        train_eta=None,
    )
    return killed_pids


def start_mask_debug(task_id: str) -> None:
    task = _get_task_or_404(task_id)
    current_status = task.get("status")

    if current_status in PIPELINE_ACTIVE_STATUSES:
        raise HTTPException(
            status_code=409,
            detail=f"Mask debug can only start when the pipeline is idle, current status is {current_status}.",
        )
    if current_status in MASK_INTERACTION_STATUSES:
        return
    if not _can_debug_masking(task):
        if (task.get("quality_profile") or "").strip().lower() == "raw":
            raise HTTPException(status_code=400, detail="Mask debug is disabled for the raw profile in the MVP.")
        raise HTTPException(
            status_code=400,
            detail="This task does not have reusable COLMAP output. Wait until preprocessing finishes at least once.",
        )

    processed_dir = task_processed_dir(task_id)
    dataset_dir = _processed_dataset_dir(task_id)
    quality_profile = _task_effective_quality_profile(task)

    _clear_mask_debug_artifacts(task_id)
    update_task(
        task_id,
        object_masking=True,
        error_message=None,
        pipeline_pid=None,
        progress=54,
        train_step=None,
        train_total_steps=None,
        train_eta=None,
        mask_prompts_rel_path=None,
        mask_preview_rel_path=None,
        mask_preview_manifest_rel_path=None,
        mask_summary_rel_path=None,
    )

    reporter = PipelineReporter(task_id, processed_dir, reset_log=False)
    reporter.log_event(
        "mask-debug",
        "Re-entering object masking debug using existing COLMAP dataset",
        force=True,
        dataset_dir=str(dataset_dir),
        quality_profile=quality_profile.name,
        previous_status=current_status,
    )
    select_mask_prompt_frame(dataset_dir, quality_profile, reporter)
    update_task(
        task_id,
        object_masking=True,
        error_message=None,
        pipeline_pid=None,
        mask_prompts_rel_path=None,
        mask_preview_rel_path=None,
        mask_preview_manifest_rel_path=None,
        mask_summary_rel_path=None,
    )


def generate_mask_preview(task_id: str, points: list[Any]) -> None:
    task = _get_task_or_404(task_id)
    if task.get("status") not in MASK_INTERACTION_STATUSES:
        raise HTTPException(
            status_code=409,
            detail=(
                "Mask prompts can only be submitted while awaiting_mask_prompt or "
                f"awaiting_mask_confirmation, current status is {task.get('status')}."
            ),
        )
    if not task.get("object_masking"):
        raise HTTPException(status_code=400, detail="Object masking is not enabled for this task.")
    if not points:
        raise HTTPException(status_code=400, detail="At least one mask prompt point is required.")
    if not any(getattr(point, "label", None) == 1 for point in points):
        raise HTTPException(status_code=400, detail="At least one positive object point is required.")

    processed_dir = task_processed_dir(task_id)
    prompt_frame_name = task.get("mask_prompt_frame_name")
    if not prompt_frame_name:
        raise HTTPException(status_code=400, detail="Task has no mask prompt frame.")

    try:
        quality_profile = _task_effective_quality_profile(task)
        prompts_path = _write_mask_prompts(task_id, task, points)
        preview_frames_dir = _mask_preview_frames_dir(task_id)
        preview_manifest_path = _mask_preview_manifest_path(task_id)
        preview_path = _mask_preview_frame_path(task_id, prompt_frame_name)

        update_task(
            task_id,
            status=task.get("status"),
            progress=int(task.get("progress") or 54),
            status_message="正在生成全帧分割预览，请稍候",
            error_message=None,
            mask_prompts_rel_path=path_to_storage_url(prompts_path),
            mask_preview_rel_path=None,
            mask_preview_manifest_rel_path=None,
            mask_summary_rel_path=None,
            pipeline_pid=None,
        )

        reporter = PipelineReporter(task_id, processed_dir, reset_log=False)
        reporter.log_event(
            "mask-preview",
            "Generating SAM 2 full-video preview for mask inspection",
            force=True,
            prompt_frame_name=prompt_frame_name,
            positive_points=sum(1 for point in points if getattr(point, "label", None) == 1),
            negative_points=sum(1 for point in points if getattr(point, "label", None) == 0),
            preview_frames_dir=str(preview_frames_dir),
            preview_manifest_path=str(preview_manifest_path),
        )
        result = run_logged_streaming_command(
            reporter,
            "mask-preview",
            build_sam2_preview_command(
                dataset_dir=processed_dir / "dataset",
                prompts_path=prompts_path,
                quality_profile=quality_profile,
                output_preview_dir=preview_frames_dir,
                output_preview_manifest_path=preview_manifest_path,
            ),
            cwd=REPO_ROOT,
            on_line=lambda line: reporter.log(line, stage="mask-preview"),
        )
        if result.returncode != 0:
            raise RuntimeError(format_command_failure(result, "SAM 2 preview generation failed."))

        update_task(
            task_id,
            status="awaiting_mask_confirmation",
            progress=int(task.get("progress") or 54),
            status_message="已生成全帧分割预览，请拖动进度条检查任意时刻的分割效果；如果不理想，可以补点后重新预览",
            error_message=None,
            mask_prompts_rel_path=path_to_storage_url(prompts_path),
            mask_preview_rel_path=path_to_storage_url(preview_path),
            mask_preview_manifest_rel_path=path_to_storage_url(preview_manifest_path),
            mask_summary_rel_path=path_to_storage_url(processed_dir / "dataset" / "mask_summary.json"),
            pipeline_pid=None,
        )
        reporter.log_event(
            "mask-preview",
            "SAM 2 full-video preview generated",
            force=True,
            task_status="awaiting_mask_confirmation",
            preview_path=str(preview_path),
            preview_manifest_path=str(preview_manifest_path),
        )
    except (OSError, RuntimeError, ValueError) as exc:
        update_task(
            task_id,
            status=task.get("status") or "awaiting_mask_prompt",
            progress=int(task.get("progress") or 54),
            status_message="全帧分割预览生成失败，请调整提示点后重试",
            error_message=str(exc),
            pipeline_pid=None,
        )
        raise HTTPException(status_code=500, detail=f"Failed to generate mask preview: {exc}") from exc


def resume_after_mask(task_id: str) -> int:
    task = _get_task_or_404(task_id)
    current_status = task.get("status")
    can_resume_from_queued = current_status == "queued" and task.get("pipeline_pid") in {None, "", 0}
    if current_status != "awaiting_mask_confirmation" and not can_resume_from_queued:
        raise HTTPException(
            status_code=409,
            detail=(
                "Mask confirmation is only allowed while awaiting_mask_confirmation, "
                f"current status is {current_status}."
            ),
        )
    if not task.get("object_masking"):
        raise HTTPException(status_code=400, detail="Object masking is not enabled for this task.")

    input_video = _task_input_video_path(task)
    prompts_path = _mask_prompts_path(task_id)
    if not prompts_path.exists():
        raise HTTPException(status_code=400, detail="Mask prompts were not found. Please regenerate the preview first.")

    preview_manifest_path = _mask_preview_manifest_path(task_id)
    if not preview_manifest_path.exists():
        raise HTTPException(
            status_code=400,
            detail="Mask preview manifest was not found. Please regenerate the preview first.",
        )

    prompt_frame_name = task.get("mask_prompt_frame_name")
    preview_path = _mask_preview_frame_path(task_id, prompt_frame_name) if prompt_frame_name else None
    if preview_path is None or not preview_path.exists():
        raise HTTPException(
            status_code=400,
            detail="Mask preview frame was not found. Please regenerate the preview first.",
        )

    update_task(
        task_id,
        status="queued",
        progress=int(task.get("progress") or 54),
        status_message="Mask 预览已确认，正在启动 SAM 2 分割流水线",
        error_message=None,
        pipeline_pid=None,
    )

    try:
        pipeline_pid = _start_pipeline_subprocess(
            task_id,
            input_video,
            quality_profile=task.get("quality_profile") or "balanced",
            train_max_steps=int(task.get("train_max_steps") or 7000),
            object_masking=True,
            mock_mode=bool(task.get("mock_mode", False)),
            resume_after_mask=True,
        )
    except OSError as exc:
        update_task(
            task_id,
            status="failed",
            progress=100,
            status_message="SAM 2 分割流水线启动失败",
            error_message=str(exc),
            pipeline_pid=None,
        )
        raise HTTPException(status_code=500, detail=f"Failed to start mask pipeline: {exc}") from exc

    update_task(task_id, pipeline_pid=pipeline_pid)
    return pipeline_pid
