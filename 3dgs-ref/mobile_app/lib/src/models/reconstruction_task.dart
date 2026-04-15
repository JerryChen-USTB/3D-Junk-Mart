class ReconstructionTask {
  const ReconstructionTask({
    required this.taskId,
    required this.title,
    required this.description,
    required this.price,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    this.statusMessage,
    this.errorMessage,
    this.videoUrl,
    this.modelUrl,
    this.viewerUrl,
    this.logUrl,
    this.logTail = const [],
    this.trainStep,
    this.trainTotalSteps,
    this.trainEta,
    this.trainMaxSteps,
    this.qualityProfile,
    this.objectMasking = false,
    this.maskPromptFrameUrl,
    this.maskPromptFrameName,
    this.maskPromptFrameWidth,
    this.maskPromptFrameHeight,
    this.maskPromptsUrl,
    this.maskPreviewUrl,
    this.maskPreviewManifestUrl,
    this.maskSummaryUrl,
    this.canDebugMasking = false,
    this.pipelinePid,
    this.mockMode = false,
    this.isPublished = false,
    this.publishedAt,
    this.viewerRotationDone = false,
    this.viewerTranslationDone = false,
    this.viewerInitialViewDone = false,
    this.viewerAnimationApproved = false,
  });

  final String taskId;
  final String title;
  final String description;
  final String price;
  final String status;
  final int progress;
  final String createdAt;
  final String updatedAt;
  final String? statusMessage;
  final String? errorMessage;
  final String? videoUrl;
  final String? modelUrl;
  final String? viewerUrl;
  final String? logUrl;
  final List<String> logTail;
  final int? trainStep;
  final int? trainTotalSteps;
  final String? trainEta;
  final int? trainMaxSteps;
  final String? qualityProfile;
  final bool objectMasking;
  final String? maskPromptFrameUrl;
  final String? maskPromptFrameName;
  final int? maskPromptFrameWidth;
  final int? maskPromptFrameHeight;
  final String? maskPromptsUrl;
  final String? maskPreviewUrl;
  final String? maskPreviewManifestUrl;
  final String? maskSummaryUrl;
  final bool canDebugMasking;
  final int? pipelinePid;
  final bool mockMode;
  final bool isPublished;
  final String? publishedAt;
  final bool viewerRotationDone;
  final bool viewerTranslationDone;
  final bool viewerInitialViewDone;
  final bool viewerAnimationApproved;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get canOpenViewer => isReady && viewerUrl != null;
  bool get canPublish => isReady && !isPublished && viewerUrl != null;
  bool get isAwaitingMaskPrompt => status == 'awaiting_mask_prompt';
  bool get isAwaitingMaskConfirmation => status == 'awaiting_mask_confirmation';
  bool get needsMaskInteraction =>
      isAwaitingMaskPrompt || isAwaitingMaskConfirmation;
  bool get isPipelineActive =>
      status == 'queued' ||
      status == 'preprocessing' ||
      status == 'masking' ||
      status == 'training' ||
      status == 'exporting';

  factory ReconstructionTask.fromJson(Map<String, dynamic> json) {
    return ReconstructionTask(
      taskId: json['task_id'] as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      price: (json['price'] ?? '') as String,
      status: (json['status'] ?? 'uploaded') as String,
      progress: (json['progress'] ?? 0) as int,
      createdAt: (json['created_at'] ?? '') as String,
      updatedAt: (json['updated_at'] ?? '') as String,
      statusMessage: json['status_message'] as String?,
      errorMessage: json['error_message'] as String?,
      videoUrl: json['video_url'] as String?,
      modelUrl: json['model_url'] as String?,
      viewerUrl: json['viewer_url'] as String?,
      logUrl: json['log_url'] as String?,
      logTail: (json['log_tail'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      trainStep: json['train_step'] as int?,
      trainTotalSteps: json['train_total_steps'] as int?,
      trainEta: json['train_eta'] as String?,
      trainMaxSteps: json['train_max_steps'] as int?,
      qualityProfile: json['quality_profile'] as String?,
      objectMasking: (json['object_masking'] ?? false) as bool,
      maskPromptFrameUrl: json['mask_prompt_frame_url'] as String?,
      maskPromptFrameName: json['mask_prompt_frame_name'] as String?,
      maskPromptFrameWidth: json['mask_prompt_frame_width'] as int?,
      maskPromptFrameHeight: json['mask_prompt_frame_height'] as int?,
      maskPromptsUrl: json['mask_prompts_url'] as String?,
      maskPreviewUrl: json['mask_preview_url'] as String?,
      maskPreviewManifestUrl: json['mask_preview_manifest_url'] as String?,
      maskSummaryUrl: json['mask_summary_url'] as String?,
      canDebugMasking: (json['can_debug_masking'] ?? false) as bool,
      pipelinePid: json['pipeline_pid'] as int?,
      mockMode: (json['mock_mode'] ?? false) as bool,
      isPublished: (json['is_published'] ?? false) as bool,
      publishedAt: json['published_at'] as String?,
      viewerRotationDone: (json['viewer_rotation_done'] ?? false) as bool,
      viewerTranslationDone: (json['viewer_translation_done'] ?? false) as bool,
      viewerInitialViewDone:
          (json['viewer_initial_view_done'] ?? false) as bool,
      viewerAnimationApproved:
          (json['viewer_animation_approved'] ?? false) as bool,
    );
  }
}
