import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/reconstructions/reconstruction_models.dart';
import '../../core/reconstructions/reconstructions_repository.dart';
import '../../theme/app_colors.dart';
import '../viewer/viewer_page.dart';
import 'reconstruction_task_status_page.dart';

class ReconstructionPublishFlowPage extends StatefulWidget {
  const ReconstructionPublishFlowPage({
    super.key,
    required this.apiClient,
    this.accessToken,
    this.initialTaskId,
    this.onMarketplaceChanged,
    this.onOpenListing,
  });

  final ApiClient apiClient;
  final String? accessToken;
  final String? initialTaskId;
  final VoidCallback? onMarketplaceChanged;
  final ValueChanged<String>? onOpenListing;

  @override
  State<ReconstructionPublishFlowPage> createState() =>
      _ReconstructionPublishFlowPageState();
}

class _ReconstructionPublishFlowPageState
    extends State<ReconstructionPublishFlowPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController(text: '299.00');
  final _picker = ImagePicker();

  late final ReconstructionsRepository _repository;
  Timer? _timer;
  XFile? _selectedVideo;
  ReconstructionTask? _task;
  bool _isLoadingTask = false;
  bool _isCreatingTask = false;
  bool _isStartingPipeline = false;
  bool _isRefreshingTask = false;
  bool _isPublishing = false;
  String _selectedQualityProfile = 'balanced';
  int _selectedTrainMaxSteps = 7000;
  bool _objectMasking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = ReconstructionsRepository(widget.apiClient);
    if (widget.initialTaskId != null && widget.initialTaskId!.isNotEmpty) {
      _loadTask(widget.initialTaskId!);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _applyTask(ReconstructionTask task) {
    _task = task;
    _titleController.text = task.title;
    _descriptionController.text = task.description;
    if (task.price.isNotEmpty) {
      _priceController.text = task.price;
    }
    _selectedQualityProfile = task.qualityProfile ?? _selectedQualityProfile;
    _selectedTrainMaxSteps = task.trainMaxSteps ?? _selectedTrainMaxSteps;
    _objectMasking = task.objectMasking;
  }

  void _syncPolling() {
    _timer?.cancel();
    final task = _task;
    if (task == null) {
      return;
    }
    if (task.isPipelineActive || task.needsMaskInteraction) {
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshTask(silent: true),
      );
    }
  }

  Future<void> _loadTask(String taskId) async {
    setState(() {
      _isLoadingTask = true;
      _errorMessage = null;
    });
    try {
      final task = await _repository.fetchTask(
        taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(task);
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载任务失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTask = false;
        });
      }
    }
  }

  Future<void> _refreshTask({bool silent = false}) async {
    final task = _task;
    if (task == null || _isRefreshingTask) {
      return;
    }
    if (!silent) {
      setState(() {
        _isRefreshingTask = true;
        _errorMessage = null;
      });
    } else {
      _isRefreshingTask = true;
    }
    try {
      final latest = await _repository.fetchTask(
        task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(latest);
      });
      _syncPolling();
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      setState(() {
        _errorMessage = '刷新任务失败：$error';
      });
    } finally {
      _isRefreshingTask = false;
      if (mounted && !silent) {
        setState(() {});
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final video = await _picker.pickVideo(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      maxDuration: const Duration(seconds: 60),
    );
    if (video == null || !mounted) {
      return;
    }
    setState(() {
      _selectedVideo = video;
      _errorMessage = null;
    });
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedVideo == null) {
      setState(() {
        _errorMessage = '请先拍摄或选择一段环绕视频。';
      });
      return;
    }
    setState(() {
      _isCreatingTask = true;
      _errorMessage = null;
    });
    try {
      final task = await _repository.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: _priceController.text.trim(),
        video: _selectedVideo!,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(task);
      });
      _syncPolling();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('草稿已创建，接下来可以启动训练。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '创建任务失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingTask = false;
        });
      }
    }
  }

  Future<void> _startPipeline() async {
    final task = _task;
    if (task == null) {
      setState(() {
        _errorMessage = '请先创建任务草稿。';
      });
      return;
    }
    setState(() {
      _isStartingPipeline = true;
      _errorMessage = null;
    });
    try {
      final updated = await _repository.startPipeline(
        taskId: task.taskId,
        qualityProfile: _selectedQualityProfile,
        trainMaxSteps: _selectedTrainMaxSteps,
        objectMasking: _objectMasking,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(updated);
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '启动训练失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStartingPipeline = false;
        });
      }
    }
  }

  Future<void> _openTaskStatus() async {
    final task = _task;
    if (task == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReconstructionTaskStatusPage(
          repository: _repository,
          initialTask: task,
          accessToken: widget.accessToken,
        ),
      ),
    );
    await _refreshTask();
  }

  Future<void> _markViewerStep(_ViewerWorkflowStep step) async {
    final task = _task;
    if (task == null || task.viewerUrl == null) {
      return;
    }
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ViewerWorkflowPage(
          title: step.title,
          description: step.description,
          actionLabel: step.actionLabel,
          viewerUrl: task.viewerUrl!,
          queryParameters: step.queryParameters,
        ),
      ),
    );
    if (completed != true || !mounted) {
      return;
    }

    try {
      final updated = await _repository.updatePublishFlowState(
        taskId: task.taskId,
        viewerRotationDone: step == _ViewerWorkflowStep.rotate ? true : null,
        viewerTranslationDone: step == _ViewerWorkflowStep.translate
            ? true
            : null,
        viewerInitialViewDone: step == _ViewerWorkflowStep.initialView
            ? true
            : null,
        viewerAnimationApproved: step == _ViewerWorkflowStep.animation
            ? true
            : null,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(updated);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '保存 Viewer 步骤失败：$error';
      });
    }
  }

  Future<void> _publishTask() async {
    final task = _task;
    if (task == null) {
      return;
    }
    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });
    try {
      final published = await _repository.publishTask(
        task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(published);
      });
      widget.onMarketplaceChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('3D 商品已发布到 marketplace。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '发布失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  void _openPublishedListing() {
    final listingId = _task?.listingId;
    if (listingId == null || listingId.isEmpty) {
      return;
    }
    widget.onOpenListing?.call(listingId);
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final canConfigureViewer = task?.canOpenViewer == true;
    final canPublish =
        task?.canPublish == true && task?.viewerWorkflowComplete == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('3DGS 发布流'),
        actions: [
          IconButton(
            onPressed: task == null || _isRefreshingTask
                ? null
                : () => _refreshTask(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: _isLoadingTask
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  const _FlowHeroCard(),
                  const SizedBox(height: 12),
                  _StepSummary(task: task),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _FlowErrorBanner(message: _errorMessage!),
                  ],
                  const SizedBox(height: 12),
                  _DraftCard(
                    formKey: _formKey,
                    titleController: _titleController,
                    descriptionController: _descriptionController,
                    priceController: _priceController,
                    selectedVideo: _selectedVideo,
                    hasCreatedTask: task != null,
                    isCreating: _isCreatingTask,
                    onPickCamera: () => _pickVideo(ImageSource.camera),
                    onPickGallery: () => _pickVideo(ImageSource.gallery),
                    onCreate: _createTask,
                  ),
                  const SizedBox(height: 12),
                  _TrainingCard(
                    task: task,
                    selectedQualityProfile: _selectedQualityProfile,
                    selectedTrainMaxSteps: _selectedTrainMaxSteps,
                    objectMasking: _objectMasking,
                    isStarting: _isStartingPipeline,
                    onQualityProfileChanged: (value) {
                      setState(() {
                        _selectedQualityProfile = value;
                        if (value == 'raw') {
                          _objectMasking = false;
                        }
                      });
                    },
                    onTrainMaxStepsChanged: (value) {
                      setState(() {
                        _selectedTrainMaxSteps = value;
                      });
                    },
                    onObjectMaskingChanged: _selectedQualityProfile == 'raw'
                        ? null
                        : (value) {
                            setState(() {
                              _objectMasking = value;
                            });
                          },
                    onStart: _startPipeline,
                  ),
                  if (task != null) ...[
                    const SizedBox(height: 12),
                    _TaskMonitorCard(task: task, onOpenStatus: _openTaskStatus),
                  ],
                  if (canConfigureViewer) ...[
                    const SizedBox(height: 12),
                    _ViewerWorkflowCard(
                      task: task!,
                      onOpenRotate: () =>
                          _markViewerStep(_ViewerWorkflowStep.rotate),
                      onOpenTranslate: () =>
                          _markViewerStep(_ViewerWorkflowStep.translate),
                      onOpenInitialView: () =>
                          _markViewerStep(_ViewerWorkflowStep.initialView),
                      onOpenAnimation: () =>
                          _markViewerStep(_ViewerWorkflowStep.animation),
                    ),
                  ],
                  if (task != null) ...[
                    const SizedBox(height: 12),
                    _PublishCard(
                      task: task,
                      canPublish: canPublish,
                      isPublishing: _isPublishing,
                      onPublish: _publishTask,
                      onOpenListing: task.hasPublishedListing
                          ? _openPublishedListing
                          : null,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

enum _ViewerWorkflowStep {
  rotate(
    title: '步骤 1: 校准朝向',
    description: '进入 rotate 模式，调整模型朝向到更适合展示的正面。',
    actionLabel: '我已完成朝向校准',
    queryParameters: <String, String>{'workflow': 'rotate'},
  ),
  translate(
    title: '步骤 2: 校准平移',
    description: '进入 translate 模式，把模型摆到更合适的展示中心位置。',
    actionLabel: '我已完成平移校准',
    queryParameters: <String, String>{'workflow': 'translate'},
  ),
  initialView(
    title: '步骤 3: 设定初始视角',
    description: '调整买家首次打开详情页时看到的默认视角。',
    actionLabel: '我已保存初始视角',
    queryParameters: <String, String>{'workflow': 'initial-view'},
  ),
  animation(
    title: '步骤 4: 预览展示动画',
    description: '以自动播放模式检查最终展示动画是否自然。',
    actionLabel: '动画效果确认无误',
    queryParameters: <String, String>{'autoplay': '1'},
  );

  const _ViewerWorkflowStep({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.queryParameters,
  });

  final String title;
  final String description;
  final String actionLabel;
  final Map<String, String> queryParameters;
}

class _FlowHeroCard extends StatelessWidget {
  const _FlowHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE891), Color(0xFFF8D045)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Video to 3D listing',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(
            '上传环绕视频后，当前 App 会依次经过远程训练、Mask 交互、Viewer 校准，再把结果发布回 marketplace listing。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepSummary extends StatelessWidget {
  const _StepSummary({required this.task});

  final ReconstructionTask? task;

  @override
  Widget build(BuildContext context) {
    final steps = <({String label, bool done, bool active})>[
      (label: '草稿', done: task != null, active: task == null),
      (
        label: '训练',
        done: task?.isReady == true,
        active: task != null && !(task?.isReady == true),
      ),
      (
        label: 'Viewer',
        done: task?.viewerWorkflowComplete == true,
        active:
            task?.canOpenViewer == true &&
            !(task?.viewerWorkflowComplete == true),
      ),
      (
        label: '发布',
        done: task?.isPublished == true,
        active: task?.canPublish == true,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: steps
          .map((step) {
            final background = step.done
                ? AppColors.mint.withValues(alpha: 0.14)
                : step.active
                ? AppColors.accent
                : AppColors.surfaceSoft;
            final foreground = step.done
                ? AppColors.mint
                : step.active
                ? AppColors.primary
                : AppColors.textMuted;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                step.label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: foreground),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.formKey,
    required this.titleController,
    required this.descriptionController,
    required this.priceController,
    required this.selectedVideo,
    required this.hasCreatedTask,
    required this.isCreating,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onCreate,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController priceController;
  final XFile? selectedVideo;
  final bool hasCreatedTask;
  final bool isCreating;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 创建任务草稿', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextFormField(
                controller: titleController,
                readOnly: hasCreatedTask,
                decoration: const InputDecoration(labelText: '商品标题'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入标题' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descriptionController,
                readOnly: hasCreatedTask,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '商品描述'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceController,
                readOnly: hasCreatedTask,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '价格'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入价格' : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: hasCreatedTask ? null : onPickCamera,
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('拍摄视频'),
                  ),
                  OutlinedButton.icon(
                    onPressed: hasCreatedTask ? null : onPickGallery,
                    icon: const Icon(Icons.video_library_rounded),
                    label: const Text('从相册选择'),
                  ),
                ],
              ),
              if (selectedVideo != null) ...[
                const SizedBox(height: 12),
                Text(
                  '已选择: ${selectedVideo!.name.isEmpty ? selectedVideo!.path : selectedVideo!.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: hasCreatedTask || isCreating ? null : onCreate,
                icon: isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  isCreating ? '创建中...' : (hasCreatedTask ? '草稿已创建' : '创建草稿'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.task,
    required this.selectedQualityProfile,
    required this.selectedTrainMaxSteps,
    required this.objectMasking,
    required this.isStarting,
    required this.onQualityProfileChanged,
    required this.onTrainMaxStepsChanged,
    required this.onObjectMaskingChanged,
    required this.onStart,
  });

  final ReconstructionTask? task;
  final String selectedQualityProfile;
  final int selectedTrainMaxSteps;
  final bool objectMasking;
  final bool isStarting;
  final ValueChanged<String> onQualityProfileChanged;
  final ValueChanged<int> onTrainMaxStepsChanged;
  final ValueChanged<bool>? onObjectMaskingChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final enabled = task != null && task!.isStartable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('2. 启动训练', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              task == null
                  ? '先创建任务，再选择质量档位和训练步数。'
                  : enabled
                  ? '任务已上传，可以手动启动远程 3DGS 流水线。'
                  : '当前任务已经进入流程，训练参数以服务器记录为准。',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedQualityProfile,
              decoration: const InputDecoration(labelText: '质量档位'),
              items: const [
                DropdownMenuItem(value: 'fast', child: Text('Fast')),
                DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                DropdownMenuItem(value: 'quality', child: Text('Quality')),
                DropdownMenuItem(value: 'raw', child: Text('Raw')),
              ],
              onChanged: enabled && !isStarting
                  ? (value) {
                      if (value != null) {
                        onQualityProfileChanged(value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 7000, label: Text('7000 步')),
                  ButtonSegment<int>(value: 30000, label: Text('30000 步')),
                ],
                selected: <int>{selectedTrainMaxSteps},
                onSelectionChanged: enabled && !isStarting
                    ? (values) {
                        if (values.isNotEmpty) {
                          onTrainMaxStepsChanged(values.first);
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: objectMasking,
              onChanged: enabled && !isStarting ? onObjectMaskingChanged : null,
              contentPadding: EdgeInsets.zero,
              title: const Text('Object Masking'),
              subtitle: const Text('训练前先做主体/背景交互式分割。'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled && !isStarting ? onStart : null,
              icon: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isStarting ? '启动中...' : '开始训练'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMonitorCard extends StatelessWidget {
  const _TaskMonitorCard({required this.task, required this.onOpenStatus});

  final ReconstructionTask task;
  final VoidCallback onOpenStatus;

  @override
  Widget build(BuildContext context) {
    final progressValue = (task.progress.clamp(0, 100)) / 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '3. 流程监控',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text(task.statusLabel)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 10),
            Text(task.statusMessage ?? '当前进度 ${task.progress}%'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onOpenStatus,
              icon: const Icon(Icons.dashboard_customize_rounded),
              label: Text(
                task.needsMaskInteraction ? '进入 Mask 交互页' : '打开任务状态页',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerWorkflowCard extends StatelessWidget {
  const _ViewerWorkflowCard({
    required this.task,
    required this.onOpenRotate,
    required this.onOpenTranslate,
    required this.onOpenInitialView,
    required this.onOpenAnimation,
  });

  final ReconstructionTask task;
  final VoidCallback onOpenRotate;
  final VoidCallback onOpenTranslate;
  final VoidCallback onOpenInitialView;
  final VoidCallback onOpenAnimation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('4. Viewer 校准', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('模型 ready 后，按顺序完成朝向、平移、初始视角和动画确认。'),
            const SizedBox(height: 12),
            _ViewerStepTile(
              title: '朝向校准',
              done: task.viewerRotationDone,
              enabled: true,
              onTap: onOpenRotate,
            ),
            const SizedBox(height: 8),
            _ViewerStepTile(
              title: '平移校准',
              done: task.viewerTranslationDone,
              enabled: task.viewerRotationDone,
              onTap: onOpenTranslate,
            ),
            const SizedBox(height: 8),
            _ViewerStepTile(
              title: '初始视角',
              done: task.viewerInitialViewDone,
              enabled: task.viewerTranslationDone,
              onTap: onOpenInitialView,
            ),
            const SizedBox(height: 8),
            _ViewerStepTile(
              title: '动画预览',
              done: task.viewerAnimationApproved,
              enabled: task.viewerInitialViewDone,
              onTap: onOpenAnimation,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ViewerPage(
                      viewerUrl: task.viewerUrl!,
                      title: task.title.isEmpty ? '3D 模型' : task.title,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_full_rounded),
              label: const Text('直接打开 Viewer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerStepTile extends StatelessWidget {
  const _ViewerStepTile({
    required this.title,
    required this.done,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.mint
        : enabled
        ? AppColors.primary
        : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.adjust_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: FilledButton.tonal(
              onPressed: enabled ? onTap : null,
              child: Text(done ? '重新进入' : '开始'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishCard extends StatelessWidget {
  const _PublishCard({
    required this.task,
    required this.canPublish,
    required this.isPublishing,
    required this.onPublish,
    this.onOpenListing,
  });

  final ReconstructionTask task;
  final bool canPublish;
  final bool isPublishing;
  final VoidCallback onPublish;
  final VoidCallback? onOpenListing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '5. 发布到 Marketplace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              task.isPublished
                  ? '当前任务已经生成 marketplace listing，并可从首页/搜索/详情页进入。'
                  : task.viewerWorkflowComplete
                  ? 'Viewer 步骤已经完成，可以发布到 marketplace。'
                  : '建议先完成 Viewer 的四个步骤，再执行最终发布。',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canPublish && !isPublishing ? onPublish : null,
              icon: isPublishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish_rounded),
              label: Text(
                isPublishing
                    ? '发布中...'
                    : (task.isPublished ? '已发布' : '发布到 Marketplace'),
              ),
            ),
            if (task.hasPublishedListing && onOpenListing != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenListing,
                icon: const Icon(Icons.storefront_rounded),
                label: Text('打开 Listing ${task.listingId}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowErrorBanner extends StatelessWidget {
  const _FlowErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.coral),
      ),
    );
  }
}

class _ViewerWorkflowPage extends StatelessWidget {
  const _ViewerWorkflowPage({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.viewerUrl,
    required this.queryParameters,
  });

  final String title;
  final String description;
  final String actionLabel;
  final String viewerUrl;
  final Map<String, String> queryParameters;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: AppColors.surfaceSoft,
            child: Text(description),
          ),
          Expanded(
            child: ViewerFrame(
              viewerUrl: viewerUrl,
              additionalQueryParameters: queryParameters,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('稍后处理'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
