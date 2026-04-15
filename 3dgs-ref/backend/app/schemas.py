from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class ReconstructionTaskResponse(BaseModel):
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


class PipelineStartRequest(BaseModel):
    quality_profile: str = "balanced"
    train_max_steps: int = 7000
    object_masking: bool = False
    mock_mode: bool | None = None


class MaskPromptPoint(BaseModel):
    x: float = Field(ge=0.0, le=1.0)
    y: float = Field(ge=0.0, le=1.0)
    label: int = Field(ge=0, le=1)


class MaskPromptRequest(BaseModel):
    points: list[MaskPromptPoint] = Field(default_factory=list)


class ViewerConfigUpdate(BaseModel):
    model_rotation_deg: list[float] | None = Field(default=None, min_length=3, max_length=3)
    model_translation: list[float] | None = Field(default=None, min_length=3, max_length=3)
    model_scale: float | None = None
    camera_rotation_deg: list[float] | None = Field(default=None, min_length=3, max_length=3)
    camera_distance: float | None = None


class ViewerConfigResponse(BaseModel):
    task_id: str
    viewer_config: dict[str, Any]
    task: ReconstructionTaskResponse


class PublishFlowStateUpdate(BaseModel):
    viewer_rotation_done: bool | None = None
    viewer_translation_done: bool | None = None
    viewer_initial_view_done: bool | None = None
    viewer_animation_approved: bool | None = None


class HealthResponse(BaseModel):
    status: str
    storage_root: str
    viewer_root: str
    gs_service_base_url: str
    trainer_service_base_url: str
    auto_start_pipeline: bool
    viewer_proxy_mode: str
