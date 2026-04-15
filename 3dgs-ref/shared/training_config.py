from __future__ import annotations

import os
import re
from dataclasses import asdict, dataclass, replace
from typing import Any


DEFAULT_TRAIN_MAX_STEPS = 7000
TRAIN_MAX_STEP_OPTIONS = (7000, 30000)
DEFAULT_QUALITY_PROFILE = "balanced"


@dataclass(frozen=True)
class QualityProfile:
    name: str
    video_max_long_edge: int | None
    process_num_downscales: int
    train_downscale_factor: int | None
    model_num_downscales: int
    description: str


MIN_TRAIN_LONG_EDGE_BY_PROFILE = {
    "fast": 720,
    "balanced": 960,
    "quality": 1280,
    "raw": 0,
}


QUALITY_PROFILES = {
    "fast": QualityProfile(
        name="fast",
        video_max_long_edge=1600,
        process_num_downscales=2,
        train_downscale_factor=2,
        model_num_downscales=2,
        description="Lower resolution profile for quick local checks.",
    ),
    "balanced": QualityProfile(
        name="balanced",
        video_max_long_edge=2560,
        process_num_downscales=2,
        train_downscale_factor=2,
        model_num_downscales=2,
        description="Default MVP profile, targeting better detail while keeping training cost bounded.",
    ),
    "quality": QualityProfile(
        name="quality",
        video_max_long_edge=3200,
        process_num_downscales=2,
        train_downscale_factor=2,
        model_num_downscales=1,
        description="Higher-detail profile for good captures and enough VRAM.",
    ),
    "raw": QualityProfile(
        name="raw",
        video_max_long_edge=None,
        process_num_downscales=2,
        train_downscale_factor=1,
        model_num_downscales=1,
        description="Experimental profile that keeps original resolution and is likely to be expensive.",
    ),
}


def resolve_quality_profile(name: str | None) -> QualityProfile:
    normalized = (name or DEFAULT_QUALITY_PROFILE).strip().lower()
    profile = QUALITY_PROFILES.get(normalized)
    if profile is None:
        known = ", ".join(sorted(QUALITY_PROFILES))
        raise ValueError(f"Unknown quality profile '{name}'. Expected one of: {known}.")
    return profile


def default_quality_profile_name() -> str:
    normalized = os.getenv("TRAINING_QUALITY_PROFILE", DEFAULT_QUALITY_PROFILE).strip().lower()
    if normalized in QUALITY_PROFILES:
        return normalized
    return DEFAULT_QUALITY_PROFILE


def object_masking_supported(quality_profile: QualityProfile) -> bool:
    return quality_profile.name != "raw"


def primary_video_stream(metadata: dict[str, Any]) -> dict[str, Any]:
    return next((stream for stream in metadata.get("streams", []) if stream.get("codec_type") == "video"), {})


def video_dimensions(metadata: dict[str, Any]) -> tuple[int, int]:
    stream = primary_video_stream(metadata)
    width = int(stream.get("width", 0) or 0)
    height = int(stream.get("height", 0) or 0)
    return width, height


def effective_long_edge_for_profile(metadata: dict[str, Any], quality_profile: QualityProfile) -> int:
    width, height = video_dimensions(metadata)
    long_edge = max(width, height)
    if quality_profile.video_max_long_edge is None:
        return long_edge
    return min(long_edge, quality_profile.video_max_long_edge)


def adapt_quality_profile_to_video(metadata: dict[str, Any], quality_profile: QualityProfile) -> QualityProfile:
    base_train_factor = quality_profile.train_downscale_factor or 1
    effective_train_factor = base_train_factor
    effective_long_edge = effective_long_edge_for_profile(metadata, quality_profile)
    min_train_long_edge = MIN_TRAIN_LONG_EDGE_BY_PROFILE.get(quality_profile.name, 0)

    while effective_train_factor > 1 and (effective_long_edge / effective_train_factor) < min_train_long_edge:
        effective_train_factor //= 2

    effective_model_num_downscales = quality_profile.model_num_downscales
    if effective_train_factor < base_train_factor:
        effective_model_num_downscales = min(effective_model_num_downscales, 1)

    return replace(
        quality_profile,
        train_downscale_factor=effective_train_factor,
        model_num_downscales=effective_model_num_downscales,
    )


def serialize_quality_profile(profile: QualityProfile) -> dict[str, Any]:
    payload = asdict(profile)
    payload["effective_train_long_edge_min"] = MIN_TRAIN_LONG_EDGE_BY_PROFILE.get(profile.name, 0)
    return payload


def infer_task_train_downscale_factor(task: dict[str, Any]) -> int | None:
    raw_value = task.get("effective_train_downscale_factor")
    if raw_value is not None:
        try:
            return max(int(raw_value), 1)
        except (TypeError, ValueError):
            return None

    prompt_path = str(task.get("mask_prompt_frame_rel_path") or "").replace("\\", "/")
    matched = re.search(r"/images_(\d+)/", prompt_path)
    if matched:
        try:
            return max(int(matched.group(1)), 1)
        except ValueError:
            return None
    if "/images/" in prompt_path:
        return 1
    return None


def restore_effective_quality_profile(task: dict[str, Any], quality_profile: QualityProfile) -> QualityProfile | None:
    train_factor = infer_task_train_downscale_factor(task)
    if train_factor is None:
        return None

    raw_model_num_downscales = task.get("effective_model_num_downscales")
    if raw_model_num_downscales is None:
        model_num_downscales = (
            min(quality_profile.model_num_downscales, 1)
            if train_factor < (quality_profile.train_downscale_factor or 1)
            else quality_profile.model_num_downscales
        )
    else:
        try:
            model_num_downscales = max(int(raw_model_num_downscales), 0)
        except (TypeError, ValueError):
            model_num_downscales = quality_profile.model_num_downscales

    return replace(
        quality_profile,
        train_downscale_factor=train_factor,
        model_num_downscales=model_num_downscales,
    )


def resolve_train_max_steps(value: int | str | None) -> int:
    if value is None:
        return DEFAULT_TRAIN_MAX_STEPS

    try:
        steps = int(value)
    except (TypeError, ValueError):
        known = ", ".join(str(option) for option in TRAIN_MAX_STEP_OPTIONS)
        raise ValueError(f"Unknown train max steps '{value}'. Expected one of: {known}.")

    if steps not in TRAIN_MAX_STEP_OPTIONS:
        known = ", ".join(str(option) for option in TRAIN_MAX_STEP_OPTIONS)
        raise ValueError(f"Unknown train max steps '{value}'. Expected one of: {known}.")
    return steps


def default_train_max_steps() -> int:
    return resolve_train_max_steps(os.getenv("TRAINING_MAX_STEPS", str(DEFAULT_TRAIN_MAX_STEPS)))
