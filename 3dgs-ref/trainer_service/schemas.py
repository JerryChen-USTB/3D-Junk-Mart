from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from shared.training_config import DEFAULT_TRAIN_MAX_STEPS, default_quality_profile_name


class InternalPipelineStartRequest(BaseModel):
    quality_profile: str = Field(default_factory=default_quality_profile_name)
    train_max_steps: int = DEFAULT_TRAIN_MAX_STEPS
    object_masking: bool = False
    mock_mode: bool = False


class InternalMaskPromptPoint(BaseModel):
    x: float = Field(ge=0.0, le=1.0)
    y: float = Field(ge=0.0, le=1.0)
    label: int = Field(ge=0, le=1)


class InternalMaskPreviewRequest(BaseModel):
    points: list[InternalMaskPromptPoint] = Field(default_factory=list)


class TaskStartRequest(InternalPipelineStartRequest):
    pass


class MaskPreviewRequest(InternalMaskPreviewRequest):
    pass


class TaskResponse(BaseModel):
    task_id: str
    title: str
    description: str
    price: str
    status: str
    progress: int
    status_message: str | None = None
    error_message: str | None = None
    created_at: str
    updated_at: str
    video_url: str | None = None
    model_url: str | None = None
    model_ply_url: str | None = None
    model_sog_url: str | None = None
    model_format: str | None = None
    viewer_url: str | None = None
    viewer_config: dict[str, Any] | None = None
    log_url: str | None = None
    log_tail: list[str] = Field(default_factory=list)
    train_step: int | None = None
    train_total_steps: int | None = None
    train_eta: str | None = None
    train_max_steps: int | None = None
    quality_profile: str | None = None
    object_masking: bool = False
    mask_prompt_frame_url: str | None = None
    mask_prompt_frame_name: str | None = None
    mask_prompt_frame_width: int | None = None
    mask_prompt_frame_height: int | None = None
    mask_prompts_url: str | None = None
    mask_preview_url: str | None = None
    mask_preview_manifest_url: str | None = None
    mask_summary_url: str | None = None
    can_debug_masking: bool = False
    pipeline_pid: int | None = None
    mock_mode: bool = False
    is_published: bool = False
    published_at: str | None = None
    viewer_rotation_done: bool = False
    viewer_translation_done: bool = False
    viewer_initial_view_done: bool = False
    viewer_animation_approved: bool = False


class ViewerConfigUpdate(BaseModel):
    model_rotation_deg: list[float] | None = Field(default=None, min_length=3, max_length=3)
    model_translation: list[float] | None = Field(default=None, min_length=3, max_length=3)
    model_scale: float | None = None
    camera_rotation_deg: list[float] | None = Field(default=None, min_length=3, max_length=3)
    camera_distance: float | None = None


class ViewerConfigResponse(BaseModel):
    task_id: str
    viewer_config: dict[str, Any]
    task: TaskResponse


class InternalActionResponse(BaseModel):
    accepted: bool = True
    task_id: str
    message: str
    pipeline_pid: int | None = None
    worker_job_id: str | None = None
    killed_pids: list[int] = Field(default_factory=list)


class TrainerServiceHealthResponse(BaseModel):
    status: str
    repo_root: str
    storage_root: str
    viewer_root: str
    python_executable: str
    public_base_url: str | None = None
