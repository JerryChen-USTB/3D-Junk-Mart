from __future__ import annotations


PIPELINE_ACTIVE_STATUSES = {"queued", "preprocessing", "masking", "training", "exporting"}
MASK_INTERACTION_STATUSES = {"awaiting_mask_prompt", "awaiting_mask_confirmation"}
PIPELINE_CANCELABLE_STATUSES = PIPELINE_ACTIVE_STATUSES | MASK_INTERACTION_STATUSES
PIPELINE_STARTABLE_STATUSES = {"uploaded", "failed", "cancelled"}
