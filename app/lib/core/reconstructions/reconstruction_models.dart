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
    this.listingId,
    this.statusMessage,
    this.errorMessage,
    this.videoUrl,
    this.modelUrl,
    this.modelPlyUrl,
    this.modelSogUrl,
    this.modelFormat,
    this.viewerUrl,
    this.logUrl,
    this.logTail = const <String>[],
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
    this.coverImageUrl,
  });

  final String taskId;
  final String? listingId;
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
  final String? modelPlyUrl;
  final String? modelSogUrl;
  final String? modelFormat;
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
  final String? coverImageUrl;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isStartable =>
      status == 'uploaded' || status == 'failed' || status == 'cancelled';
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
  bool get canOpenViewer =>
      viewerUrl != null && viewerUrl!.isNotEmpty && isReady;
  bool get hasPublishedListing =>
      isPublished && listingId != null && listingId!.isNotEmpty;
  bool get canPublish => isReady && !isPublished;
  bool get viewerWorkflowComplete =>
      viewerRotationDone &&
      viewerTranslationDone &&
      viewerInitialViewDone &&
      viewerAnimationApproved;

  String get statusLabel {
    switch (status) {
      case 'uploaded':
        return '待启动';
      case 'queued':
        return '排队中';
      case 'preprocessing':
        return '预处理中';
      case 'awaiting_mask_prompt':
        return '等待标注';
      case 'awaiting_mask_confirmation':
        return '等待确认';
      case 'masking':
        return 'Mask 处理中';
      case 'training':
        return '训练中';
      case 'exporting':
        return '导出中';
      case 'ready':
        return '模型已就绪';
      case 'failed':
        return '失败';
      case 'cancelled':
        return '已取消';
      default:
        return status;
    }
  }

  factory ReconstructionTask.fromJson(Map<String, dynamic> json, Uri apiRoot) {
    return ReconstructionTask(
      taskId: json['task_id']?.toString() ?? '',
      listingId: _stringOrNull(json['listing_id']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: json['price']?.toString() ?? '',
      status: json['status']?.toString() ?? 'uploaded',
      progress: _intOrZero(json['progress']),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      statusMessage: _stringOrNull(json['status_message']),
      errorMessage: _stringOrNull(json['error_message']),
      videoUrl: _resolveUrl(_stringOrNull(json['video_url']), apiRoot),
      modelUrl: _resolveUrl(_stringOrNull(json['model_url']), apiRoot),
      modelPlyUrl: _resolveUrl(_stringOrNull(json['model_ply_url']), apiRoot),
      modelSogUrl: _resolveUrl(_stringOrNull(json['model_sog_url']), apiRoot),
      modelFormat: _stringOrNull(json['model_format']),
      viewerUrl: _resolveUrl(_stringOrNull(json['viewer_url']), apiRoot),
      logUrl: _resolveUrl(_stringOrNull(json['log_url']), apiRoot),
      logTail: ((json['log_tail'] as List?) ?? const <Object?>[])
          .map((item) => item.toString())
          .toList(growable: false),
      trainStep: _intOrNull(json['train_step']),
      trainTotalSteps: _intOrNull(json['train_total_steps']),
      trainEta: _stringOrNull(json['train_eta']),
      trainMaxSteps: _intOrNull(json['train_max_steps']),
      qualityProfile: _stringOrNull(json['quality_profile']),
      objectMasking: json['object_masking'] == true,
      maskPromptFrameUrl: _resolveUrl(
        _stringOrNull(json['mask_prompt_frame_url']),
        apiRoot,
      ),
      maskPromptFrameName: _stringOrNull(json['mask_prompt_frame_name']),
      maskPromptFrameWidth: _intOrNull(json['mask_prompt_frame_width']),
      maskPromptFrameHeight: _intOrNull(json['mask_prompt_frame_height']),
      maskPromptsUrl: _resolveUrl(
        _stringOrNull(json['mask_prompts_url']),
        apiRoot,
      ),
      maskPreviewUrl: _resolveUrl(
        _stringOrNull(json['mask_preview_url']),
        apiRoot,
      ),
      maskPreviewManifestUrl: _resolveUrl(
        _stringOrNull(json['mask_preview_manifest_url']),
        apiRoot,
      ),
      maskSummaryUrl: _resolveUrl(
        _stringOrNull(json['mask_summary_url']),
        apiRoot,
      ),
      canDebugMasking: json['can_debug_masking'] == true,
      pipelinePid: _intOrNull(json['pipeline_pid']),
      mockMode: json['mock_mode'] == true,
      isPublished: json['is_published'] == true,
      publishedAt: _stringOrNull(json['published_at']),
      viewerRotationDone: json['viewer_rotation_done'] == true,
      viewerTranslationDone: json['viewer_translation_done'] == true,
      viewerInitialViewDone: json['viewer_initial_view_done'] == true,
      viewerAnimationApproved: json['viewer_animation_approved'] == true,
      coverImageUrl: _resolveUrl(
        _stringOrNull(
          (json['cover_media'] as Map?)?['thumbnail_url']?.toString() ??
              (json['cover_media'] as Map?)?['url']?.toString(),
        ),
        apiRoot,
      ),
    );
  }
}

class MaskPromptPoint {
  const MaskPromptPoint({
    required this.x,
    required this.y,
    required this.label,
  });

  final double x;
  final double y;
  final int label;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'x': x,
    'y': y,
    'label': label,
  };
}

class MaskPreviewManifest {
  const MaskPreviewManifest({
    required this.frameCount,
    required this.promptFrameIndex,
    required this.frameWidth,
    required this.frameHeight,
    required this.frames,
  });

  final int frameCount;
  final int promptFrameIndex;
  final int frameWidth;
  final int frameHeight;
  final List<MaskPreviewFrame> frames;

  factory MaskPreviewManifest.fromJson(Map<String, dynamic> json, Uri baseUrl) {
    final frames = ((json['frames'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) =>
              MaskPreviewFrame.fromJson(item.cast<String, dynamic>(), baseUrl),
        )
        .toList(growable: false);
    final promptFrameIndex = _intOrZero(json['prompt_frame_index']);
    return MaskPreviewManifest(
      frameCount: _intOrZero(json['frame_count']) == 0
          ? frames.length
          : _intOrZero(json['frame_count']),
      promptFrameIndex: frames.isEmpty
          ? 0
          : promptFrameIndex.clamp(0, frames.length - 1),
      frameWidth: _intOrZero(json['frame_width']),
      frameHeight: _intOrZero(json['frame_height']),
      frames: frames,
    );
  }
}

class MaskPreviewFrame {
  const MaskPreviewFrame({
    required this.index,
    required this.name,
    required this.imageUrl,
    required this.previewUrl,
  });

  final int index;
  final String name;
  final String imageUrl;
  final String previewUrl;

  factory MaskPreviewFrame.fromJson(Map<String, dynamic> json, Uri baseUrl) {
    return MaskPreviewFrame(
      index: _intOrZero(json['index']),
      name: json['name']?.toString() ?? '',
      imageUrl:
          _resolveUrl(_stringOrNull(json['image_rel_url']), baseUrl) ?? '',
      previewUrl:
          _resolveUrl(_stringOrNull(json['preview_rel_url']), baseUrl) ?? '',
    );
  }
}

String? _resolveUrl(String? raw, Uri apiRoot) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final resolved = apiRoot.resolve(raw);
  // When the base URL is proxied (e.g. /proxy/storage/...) but the resolved
  // URL lost the /proxy prefix (because `raw` was an absolute path like
  // /storage/...), re-insert the proxy prefix so the request goes through
  // the local backend proxy instead of the static file mount.
  if (apiRoot.path.contains('/proxy/') &&
      resolved.path.startsWith('/storage/') &&
      !resolved.path.startsWith('/proxy/')) {
    return resolved.replace(path: '/proxy${resolved.path}').toString();
  }
  return resolved.toString();
}

String? _stringOrNull(Object? value) {
  final normalized = value?.toString();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

int _intOrZero(Object? value) => _intOrNull(value) ?? 0;

int? _intOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}
