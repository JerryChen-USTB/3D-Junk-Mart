import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/reconstruction_task.dart';
import '../services/api_client.dart';
import '../services/native_camera_service.dart';
import 'product_detail_page.dart';
import 'task_status_page.dart';
import 'viewer_page.dart';

class SellerPublishFlowPage extends StatefulWidget {
  const SellerPublishFlowPage({
    super.key,
    required this.apiBaseUrl,
    this.initialTaskId,
  });

  final String apiBaseUrl;
  final String? initialTaskId;

  @override
  State<SellerPublishFlowPage> createState() => _SellerPublishFlowPageState();
}

class _SellerPublishFlowPageState extends State<SellerPublishFlowPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController(text: '299.00');
  final _picker = ImagePicker();

  late final ApiClient _client;
  Timer? _timer;
  XFile? _selectedVideo;
  ReconstructionTask? _task;
  bool _isLoadingTask = false;
  bool _isCreatingTask = false;
  bool _isStartingPipeline = false;
  bool _isRefreshingTask = false;
  bool _isPublishing = false;
  bool _rotationDone = false;
  bool _translationDone = false;
  bool _initialViewDone = false;
  bool _animationApproved = false;
  int _currentStepIndex = 0;
  String _selectedQualityProfile = 'balanced';
  int _selectedTrainMaxSteps = 7000;
  bool _objectMasking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(widget.apiBaseUrl);
    if (widget.initialTaskId != null) {
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

  bool get _hasTask => _task != null;
  bool get _isObjectMaskingEnabled => _task?.objectMasking ?? _objectMasking;
  bool get _canShowViewerSteps => _task?.canOpenViewer ?? false;

  Future<void> _loadTask(String taskId) async {
    setState(() {
      _isLoadingTask = true;
      _errorMessage = null;
    });

    try {
      final task = await _client.fetchTask(taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(task);
        _syncCurrentStep(resetToRecommended: true);
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载草稿失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTask = false;
        });
      }
    }
  }

  void _applyTask(ReconstructionTask task) {
    _task = task;
    _titleController.text = task.title;
    _descriptionController.text = task.description;
    _priceController.text = task.price.isEmpty
        ? _priceController.text
        : task.price;
    _selectedQualityProfile = task.qualityProfile ?? _selectedQualityProfile;
    _selectedTrainMaxSteps = task.trainMaxSteps ?? _selectedTrainMaxSteps;
    _objectMasking = task.objectMasking;
    _rotationDone = task.viewerRotationDone || task.isPublished;
    _translationDone = task.viewerTranslationDone || task.isPublished;
    _initialViewDone = task.viewerInitialViewDone || task.isPublished;
    _animationApproved = task.viewerAnimationApproved || task.isPublished;
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
      final latest = await _client.fetchTask(task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(latest);
        _syncCurrentStep(autoAdvance: true);
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
    XFile? video;
    try {
      video = source == ImageSource.camera
          ? await NativeCameraService.captureHighQualityVideo()
          : await _picker.pickVideo(source: source);
    } on MissingPluginException {
      video = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(seconds: 60),
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '打开系统相机失败：${error.message ?? error.code}';
      });
      return;
    }
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
        _errorMessage = '请先选择或拍摄商品环绕视频。';
      });
      return;
    }

    setState(() {
      _isCreatingTask = true;
      _errorMessage = null;
    });

    try {
      final task = await _client.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: _priceController.text.trim(),
        video: _selectedVideo!,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(task);
        _syncCurrentStep(autoAdvance: true);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('商品草稿已创建，继续配置训练参数。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _formatSubmitError(error);
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
        _errorMessage = '请先完成第 1 步，创建商品草稿。';
      });
      return;
    }

    setState(() {
      _isStartingPipeline = true;
      _errorMessage = null;
    });

    try {
      final updatedTask = await _client.startPipeline(
        taskId: task.taskId,
        qualityProfile: _selectedQualityProfile,
        trainMaxSteps: _selectedTrainMaxSteps,
        objectMasking: _objectMasking,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _rotationDone = false;
        _translationDone = false;
        _initialViewDone = false;
        _animationApproved = false;
        _applyTask(updatedTask);
        _syncCurrentStep(autoAdvance: true);
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '启动流水线失败：$error';
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
        builder: (_) => TaskStatusPage(client: _client, initialTask: task),
      ),
    );
    await _refreshTask();
  }

  Future<void> _openRotationViewerStep() {
    return _openViewerWorkflow(
      title: '步骤 6 · 旋转矫正',
      headline: '在 viewer 中完成模型朝向校准',
      description:
          '页面会直接进入旋转矫正模式。拖动旋转环调整商品朝向，viewer 会自动保存当前校准；确认效果后直接点击下方按钮进入下一步。',
      actionLabel: '我已完成旋转矫正',
      queryParameters: const {'workflow': 'rotate'},
    );
  }

  Future<void> _openTranslationViewerStep() {
    return _openViewerWorkflow(
      title: '步骤 7 · 移动矫正',
      headline: '在 viewer 中完成模型平移校准',
      description:
          '页面会直接进入移动矫正模式。拖动平移箭头把商品放到更合适的展示中心，viewer 会自动保存当前校准；确认效果后直接点击下方按钮进入下一步。',
      actionLabel: '我已完成移动矫正',
      queryParameters: const {'workflow': 'translate'},
    );
  }

  Future<void> _openInitialViewViewerStep() {
    return _openViewerWorkflow(
      title: '步骤 8 · 设置初始相机',
      headline: '设置买家首次看到的默认视角',
      description:
          '页面会直接进入初始视角设置模式。拖动画面调整买家默认看到的角度，停止操作后 viewer 会自动保存当前视角；确认效果后直接点击下方按钮进入下一步。',
      actionLabel: '我已保存初始相机',
      queryParameters: const {'workflow': 'initial-view'},
    );
  }

  Future<void> _openAnimationPreviewViewerStep() {
    return _openViewerWorkflow(
      title: '步骤 9 · 动画预览确认',
      headline: '预览商品的默认展示动画',
      description: '页面会自动进入动画展示模式。若效果不满意，退出后可回到第 6-8 步继续调整坐标和初始相机，然后再次预览。',
      actionLabel: '动画效果已确认',
      queryParameters: const {'autoplay': '1'},
    );
  }

  Future<void> _openViewerWorkflow({
    required String title,
    required String headline,
    required String description,
    required String actionLabel,
    Map<String, String> queryParameters = const {},
  }) async {
    final task = _task;
    if (task == null || task.viewerUrl == null) {
      return;
    }

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ViewerWorkflowPage(
          title: title,
          headline: headline,
          description: description,
          actionLabel: actionLabel,
          viewerUrl: task.viewerUrl!,
          queryParameters: queryParameters,
        ),
      ),
    );

    if (completed != true || !mounted) {
      return;
    }

    try {
      final taskId = task.taskId;
      ReconstructionTask updatedTask;
      switch (title) {
        case '步骤 6 · 旋转矫正':
          updatedTask = await _client.updatePublishFlowState(
            taskId: taskId,
            viewerRotationDone: true,
          );
          break;
        case '步骤 7 · 移动矫正':
          updatedTask = await _client.updatePublishFlowState(
            taskId: taskId,
            viewerTranslationDone: true,
          );
          break;
        case '步骤 8 · 设置初始相机':
          updatedTask = await _client.updatePublishFlowState(
            taskId: taskId,
            viewerInitialViewDone: true,
          );
          break;
        case '步骤 9 · 动画预览确认':
          updatedTask = await _client.updatePublishFlowState(
            taskId: taskId,
            viewerAnimationApproved: true,
          );
          break;
        default:
          updatedTask = task;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(updatedTask);
        _syncCurrentStep(autoAdvance: true);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '保存步骤状态失败：$error';
      });
      return;
    }
    await _refreshTask();
  }

  Future<void> _publishListing() async {
    final task = _task;
    if (task == null) {
      return;
    }

    setState(() {
      _isPublishing = true;
      _errorMessage = null;
    });

    try {
      final publishedTask = await _client.publishTask(task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _applyTask(publishedTask);
        _syncCurrentStep(autoAdvance: true);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('3D 商品已发布到首页。')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '确认发布失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  Future<void> _openBuyerPreview() async {
    final task = _task;
    if (task == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProductDetailPage(apiBaseUrl: widget.apiBaseUrl, initialTask: task),
      ),
    );
    await _refreshTask();
  }

  String _formatSubmitError(Object error) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map<String, dynamic> &&
          responseData['detail'] != null) {
        return '创建草稿失败：${responseData['detail']}';
      }
      if (responseData is String && responseData.trim().isNotEmpty) {
        return '创建草稿失败：$responseData';
      }
    }
    return '创建草稿失败：$error';
  }

  List<_PublishFlowStep> _buildSteps() {
    final task = _task;
    final taskCreated = task != null;
    final preprocessingDone =
        task != null &&
        {
          'awaiting_mask_prompt',
          'awaiting_mask_confirmation',
          'training',
          'exporting',
          'ready',
        }.contains(task.status);
    final maskDone =
        !_isObjectMaskingEnabled ||
        (task != null &&
            {'training', 'exporting', 'ready'}.contains(task.status));

    return [
      _PublishFlowStep(
        number: 1,
        title: '上传视频 / 拍摄视频',
        state: taskCreated ? _FlowCardState.done : _FlowCardState.active,
      ),
      _PublishFlowStep(
        number: 2,
        title: '训练配置设置',
        state: !taskCreated
            ? _FlowCardState.waiting
            : (task.status == 'uploaded' || task.isFailed || task.isCancelled)
            ? _FlowCardState.active
            : _FlowCardState.done,
      ),
      _PublishFlowStep(
        number: 3,
        title: '数据预处理 / COLMAP',
        state: !taskCreated
            ? _FlowCardState.waiting
            : task.isFailed || task.isCancelled
            ? _FlowCardState.error
            : task.status == 'queued' || task.status == 'preprocessing'
            ? _FlowCardState.active
            : preprocessingDone
            ? _FlowCardState.done
            : _FlowCardState.waiting,
      ),
      _PublishFlowStep(
        number: 4,
        title: 'Object Masking 标注与确认',
        state: !_isObjectMaskingEnabled
            ? _FlowCardState.skipped
            : !taskCreated
            ? _FlowCardState.waiting
            : task.status == 'awaiting_mask_prompt' ||
                  task.status == 'awaiting_mask_confirmation'
            ? _FlowCardState.active
            : maskDone
            ? _FlowCardState.done
            : task.isFailed || task.isCancelled
            ? _FlowCardState.error
            : _FlowCardState.waiting,
      ),
      _PublishFlowStep(
        number: 5,
        title: '训练与导出',
        state: !taskCreated
            ? _FlowCardState.waiting
            : task.isReady
            ? _FlowCardState.done
            : task.isFailed || task.isCancelled
            ? _FlowCardState.error
            : task.status == 'training' || task.status == 'exporting'
            ? _FlowCardState.active
            : _FlowCardState.waiting,
      ),
      _PublishFlowStep(
        number: 6,
        title: 'viewer 旋转矫正',
        state: !_canShowViewerSteps
            ? _FlowCardState.waiting
            : (_rotationDone ? _FlowCardState.done : _FlowCardState.active),
      ),
      _PublishFlowStep(
        number: 7,
        title: 'viewer 移动矫正',
        state: !_rotationDone
            ? _FlowCardState.waiting
            : (_translationDone ? _FlowCardState.done : _FlowCardState.active),
      ),
      _PublishFlowStep(
        number: 8,
        title: '设置初始相机位置',
        state: !_translationDone
            ? _FlowCardState.waiting
            : (_initialViewDone ? _FlowCardState.done : _FlowCardState.active),
      ),
      _PublishFlowStep(
        number: 9,
        title: '预览商品展示动画',
        state: !_initialViewDone
            ? _FlowCardState.waiting
            : (_animationApproved
                  ? _FlowCardState.done
                  : _FlowCardState.active),
      ),
      _PublishFlowStep(
        number: 10,
        title: '横屏内嵌 viewer 确认发布',
        state: task?.isPublished == true
            ? _FlowCardState.done
            : _animationApproved
            ? _FlowCardState.active
            : _FlowCardState.waiting,
      ),
    ];
  }

  bool _isStepSkipped(int index) {
    return index == 3 && !_isObjectMaskingEnabled;
  }

  int? _previousStepIndex([int? fromIndex]) {
    final current = fromIndex ?? _currentStepIndex;
    for (var index = current - 1; index >= 0; index -= 1) {
      if (!_isStepSkipped(index)) {
        return index;
      }
    }
    return null;
  }

  int? _nextStepIndex([int? fromIndex]) {
    final current = fromIndex ?? _currentStepIndex;
    for (var index = current + 1; index < _buildSteps().length; index += 1) {
      if (!_isStepSkipped(index)) {
        return index;
      }
    }
    return null;
  }

  int _recommendedStepIndex(List<_PublishFlowStep> steps) {
    for (var index = 0; index < steps.length; index += 1) {
      final step = steps[index];
      if (_isStepSkipped(index)) {
        continue;
      }
      if (step.state == _FlowCardState.active ||
          step.state == _FlowCardState.error ||
          step.state == _FlowCardState.waiting) {
        return index;
      }
    }
    return steps.length - 1;
  }

  void _syncCurrentStep({
    bool autoAdvance = false,
    bool resetToRecommended = false,
  }) {
    final steps = _buildSteps();
    if (steps.isEmpty) {
      return;
    }

    if (resetToRecommended) {
      _currentStepIndex = _recommendedStepIndex(steps);
      return;
    }

    if (_isStepSkipped(_currentStepIndex)) {
      _currentStepIndex =
          _nextStepIndex(_currentStepIndex) ?? _recommendedStepIndex(steps);
      return;
    }

    if (!autoAdvance) {
      return;
    }

    final currentState = steps[_currentStepIndex].state;
    if (currentState == _FlowCardState.done ||
        currentState == _FlowCardState.skipped) {
      final next = _nextStepIndex(_currentStepIndex);
      if (next != null) {
        _currentStepIndex = next;
      }
    }
  }

  void _moveToPreviousStep() {
    final previous = _previousStepIndex();
    if (previous == null) {
      return;
    }
    setState(() {
      _currentStepIndex = previous;
    });
  }

  void _moveToNextStep() {
    final next = _nextStepIndex();
    if (next == null) {
      return;
    }
    setState(() {
      _currentStepIndex = next;
    });
  }

  String _statusText(ReconstructionTask task) {
    switch (task.status) {
      case 'uploaded':
        return '草稿已创建';
      case 'queued':
        return '等待启动';
      case 'preprocessing':
        return '预处理中';
      case 'awaiting_mask_prompt':
        return '等待点选提示点';
      case 'awaiting_mask_confirmation':
        return '等待确认 Mask 预览';
      case 'training':
        return '训练中';
      case 'exporting':
        return '导出中';
      case 'ready':
        return '模型已就绪';
      case 'failed':
        return '流程失败';
      case 'cancelled':
        return '流程已终止';
      default:
        return task.status;
    }
  }

  Widget _buildCurrentStepCard(ReconstructionTask? task) {
    switch (_currentStepIndex) {
      case 0:
        return _buildUploadCard(task);
      case 1:
        return _buildConfigCard(task);
      case 2:
        return _buildPreprocessingCard(task);
      case 3:
        return _buildMaskingCard(task);
      case 4:
        return _buildTrainingCard(task);
      case 5:
        return _buildViewerStepCard(
          number: 6,
          title: '进入 viewer，完成坐标系旋转矫正',
          subtitle: '在全屏 viewer 中使用“校准坐标 -> 旋转”完成朝向修正。',
          enabled: _canShowViewerSteps,
          completed: _rotationDone,
          onReopen: _rotationDone ? () => _openRotationViewerStep() : null,
        );
      case 6:
        return _buildViewerStepCard(
          number: 7,
          title: '仍在 viewer 内，完成坐标系移动矫正',
          subtitle: '在同一个 viewer 中继续使用“移动”工具，让商品更贴合中心展示位。',
          enabled: _rotationDone && _canShowViewerSteps,
          completed: _translationDone,
          onReopen: _translationDone
              ? () => _openTranslationViewerStep()
              : null,
        );
      case 7:
        return _buildViewerStepCard(
          number: 8,
          title: '仍在 viewer 内，设置初始相机位置',
          subtitle: '调整默认视角，让买家进入详情页时看到最合适的商品角度。',
          enabled: _translationDone && _canShowViewerSteps,
          completed: _initialViewDone,
          onReopen: _initialViewDone
              ? () => _openInitialViewViewerStep()
              : null,
        );
      case 8:
        return _buildAnimationPreviewCard(task);
      case 9:
        return _buildFinalPublishCard(task);
      default:
        return const SizedBox.shrink();
    }
  }

  String _primaryButtonLabel(_PublishFlowStep step) {
    final task = _task;
    switch (_currentStepIndex) {
      case 0:
        return task == null ? '创建草稿并下一步' : '下一步';
      case 1:
        return task == null
            ? '等待草稿创建'
            : (task.status == 'uploaded' || task.isFailed || task.isCancelled)
            ? '启动流水线并下一步'
            : '下一步';
      case 2:
        return step.state == _FlowCardState.done ? '下一步' : '查看预处理详情';
      case 3:
        if (_isStepSkipped(_currentStepIndex) ||
            step.state == _FlowCardState.done) {
          return '下一步';
        }
        return '进入 Mask 标注页';
      case 4:
        return step.state == _FlowCardState.done ? '下一步' : '查看训练详情';
      case 5:
        return _rotationDone ? '下一步' : '进入 viewer 旋转矫正';
      case 6:
        return _translationDone ? '下一步' : '进入 viewer 移动矫正';
      case 7:
        return _initialViewDone ? '下一步' : '进入 viewer 设置初始相机';
      case 8:
        return _animationApproved ? '下一步' : '进入 viewer 预览动画';
      case 9:
        return task?.isPublished == true ? '查看买家详情页' : '确认发布';
      default:
        return '下一步';
    }
  }

  bool _canRunPrimaryAction(_PublishFlowStep step) {
    final task = _task;
    switch (_currentStepIndex) {
      case 0:
        return !_isCreatingTask;
      case 1:
        if (task == null || _isStartingPipeline) {
          return false;
        }
        return task.status == 'uploaded' ||
            task.isFailed ||
            task.isCancelled ||
            step.state == _FlowCardState.done;
      case 2:
        return task != null;
      case 3:
        return task != null &&
            (_isStepSkipped(_currentStepIndex) ||
                step.state == _FlowCardState.done ||
                task.needsMaskInteraction);
      case 4:
        return task != null;
      case 5:
        return _canShowViewerSteps;
      case 6:
        return _rotationDone && _canShowViewerSteps;
      case 7:
        return _translationDone && _canShowViewerSteps;
      case 8:
        return _initialViewDone && _canShowViewerSteps;
      case 9:
        return task != null && !_isPublishing;
      default:
        return false;
    }
  }

  Future<void> _handlePrimaryAction() async {
    final steps = _buildSteps();
    final currentStep = steps[_currentStepIndex];
    final task = _task;

    switch (_currentStepIndex) {
      case 0:
        if (task == null) {
          await _createTask();
          return;
        }
        _moveToNextStep();
        return;
      case 1:
        if (task != null &&
            (task.status == 'uploaded' || task.isFailed || task.isCancelled)) {
          await _startPipeline();
          return;
        }
        _moveToNextStep();
        return;
      case 2:
        if (currentStep.state == _FlowCardState.done) {
          _moveToNextStep();
          return;
        }
        await _openTaskStatus();
        return;
      case 3:
        if (_isStepSkipped(_currentStepIndex) ||
            currentStep.state == _FlowCardState.done) {
          _moveToNextStep();
          return;
        }
        await _openTaskStatus();
        return;
      case 4:
        if (currentStep.state == _FlowCardState.done) {
          _moveToNextStep();
          return;
        }
        await _openTaskStatus();
        return;
      case 5:
        if (_rotationDone) {
          _moveToNextStep();
          return;
        }
        await _openRotationViewerStep();
        return;
      case 6:
        if (_translationDone) {
          _moveToNextStep();
          return;
        }
        await _openTranslationViewerStep();
        return;
      case 7:
        if (_initialViewDone) {
          _moveToNextStep();
          return;
        }
        await _openInitialViewViewerStep();
        return;
      case 8:
        if (_animationApproved) {
          _moveToNextStep();
          return;
        }
        await _openAnimationPreviewViewerStep();
        return;
      case 9:
        if (task?.isPublished == true) {
          await _openBuyerPreview();
          return;
        }
        await _publishListing();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final currentStep = steps[_currentStepIndex];
    final task = _task;

    return Scaffold(
      appBar: AppBar(
        title: const Text('发布 3D 商品'),
        actions: [
          if (task != null)
            IconButton(
              onPressed: _isRefreshingTask ? null : _refreshTask,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新流程状态',
            ),
        ],
      ),
      body: _isLoadingTask
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  _StepTimeline(
                    steps: steps,
                    currentStepIndex: _currentStepIndex,
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        _currentStepIndex == 9 ? 0 : 16,
                        16,
                        _currentStepIndex == 9 ? 0 : 16,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _currentStepIndex == 9 ? 16 : 0,
                            ),
                            child: Text(
                              '当前步骤：${currentStep.number} / ${steps.length} · ${currentStep.title}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildCurrentStepCard(task),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _previousStepIndex() == null
                                  ? null
                                  : _moveToPreviousStep,
                              child: const Text('上一步'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _canRunPrimaryAction(currentStep)
                                  ? _handlePrimaryAction
                                  : null,
                              child: Text(_primaryButtonLabel(currentStep)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUploadCard(ReconstructionTask? task) {
    final selectedVideoName = _selectedVideo?.name ?? '尚未选择视频';
    return _FlowStepCard(
      number: 1,
      title: '上传视频 / 拍摄视频',
      subtitle: '创建一个 3D 商品草稿，后续训练配置、viewer 校准和发布都围绕这个 task 继续推进。',
      state: task != null ? _FlowCardState.done : _FlowCardState.active,
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            enabled: task == null,
            decoration: const InputDecoration(labelText: '商品标题'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入商品标题';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            enabled: task == null,
            minLines: 3,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '商品描述'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _priceController,
            enabled: task == null,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '价格'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入价格';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task == null
                      ? '当前素材：$selectedVideoName'
                      : '已创建草稿：${task.taskId}',
                ),
                const SizedBox(height: 12),
                if (task == null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isCreatingTask
                              ? null
                              : () => _pickVideo(ImageSource.gallery),
                          child: const Text('从相册选择'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isCreatingTask
                              ? null
                              : () => _pickVideo(ImageSource.camera),
                          child: const Text('原生相机录制'),
                        ),
                      ),
                    ],
                  )
                else
                  Text('状态：${_statusText(task)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard(ReconstructionTask? task) {
    final canConfigure =
        task != null &&
        (task.status == 'uploaded' || task.isFailed || task.isCancelled);

    return _FlowStepCard(
      number: 2,
      title: '训练配置设置',
      subtitle: '卖家手动选择质量档位、训练轮数与 Object Masking 策略，然后启动自动流程。',
      state: !_hasTask
          ? _FlowCardState.waiting
          : canConfigure
          ? _FlowCardState.active
          : _FlowCardState.done,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedQualityProfile,
            decoration: const InputDecoration(labelText: '质量档位'),
            items: const [
              DropdownMenuItem(value: 'fast', child: Text('Fast · 快速验证')),
              DropdownMenuItem(
                value: 'balanced',
                child: Text('Balanced · 默认推荐'),
              ),
              DropdownMenuItem(value: 'quality', child: Text('Quality · 更高画质')),
              DropdownMenuItem(value: 'raw', child: Text('Raw · 原始分辨率实验')),
            ],
            onChanged: canConfigure
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedQualityProfile = value;
                      if (value == 'raw') {
                        _objectMasking = false;
                      }
                    });
                  }
                : null,
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 7000, label: Text('7000 轮')),
              ButtonSegment<int>(value: 30000, label: Text('30000 轮')),
            ],
            selected: {_selectedTrainMaxSteps},
            onSelectionChanged: canConfigure
                ? (values) {
                    if (values.isEmpty) {
                      return;
                    }
                    setState(() {
                      _selectedTrainMaxSteps = values.first;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Object Masking'),
            subtitle: const Text('开启后会在 COLMAP 完成后暂停，卖家需要手动完成 SAM 2 标注与确认。'),
            value: _objectMasking,
            onChanged: canConfigure && _selectedQualityProfile != 'raw'
                ? (value) {
                    setState(() {
                      _objectMasking = value;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (task != null)
                OutlinedButton(
                  onPressed: _openTaskStatus,
                  child: const Text('查看详情'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreprocessingCard(ReconstructionTask? task) {
    final state = !_hasTask
        ? _FlowCardState.waiting
        : task!.isFailed || task.isCancelled
        ? _FlowCardState.error
        : task.status == 'queued' || task.status == 'preprocessing'
        ? _FlowCardState.active
        : {
            'awaiting_mask_prompt',
            'awaiting_mask_confirmation',
            'training',
            'exporting',
            'ready',
          }.contains(task.status)
        ? _FlowCardState.done
        : _FlowCardState.waiting;

    return _FlowStepCard(
      number: 3,
      title: '数据预处理 / COLMAP',
      subtitle: '这里对应你现有流水线中的抽帧、COLMAP 位姿恢复和数据整理环节。',
      state: state,
      child: task == null
          ? const Text('先完成前两步，系统才会开始自动预处理。')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (task.progress.clamp(0, 100)) / 100,
                ),
                const SizedBox(height: 12),
                Text('当前状态：${_statusText(task)}'),
                if (task.statusMessage != null &&
                    task.statusMessage!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(task.statusMessage!),
                ],
                if (task.errorMessage != null &&
                    task.errorMessage!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _openTaskStatus,
                  child: const Text('查看详细日志'),
                ),
              ],
            ),
    );
  }

  Widget _buildMaskingCard(ReconstructionTask? task) {
    final stepState = !_isObjectMaskingEnabled
        ? _FlowCardState.skipped
        : !_hasTask
        ? _FlowCardState.waiting
        : task!.status == 'awaiting_mask_prompt' ||
              task.status == 'awaiting_mask_confirmation'
        ? _FlowCardState.active
        : {'training', 'exporting', 'ready'}.contains(task.status)
        ? _FlowCardState.done
        : task.isFailed || task.isCancelled
        ? _FlowCardState.error
        : _FlowCardState.waiting;

    return _FlowStepCard(
      number: 4,
      title: 'SAM 2 点选 / 预览 / 确认',
      subtitle: '只有开启 Object Masking 才会经过这一步。',
      state: stepState,
      child: !_isObjectMaskingEnabled
          ? const Text('当前配置未开启 Object Masking，已自动跳过。')
          : task == null
          ? const Text('等待任务创建并开始预处理。')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.needsMaskInteraction
                      ? 'COLMAP 已完成，当前正等待卖家进入标注页点选前景/背景并检查全帧预览。'
                      : '一旦状态进入等待标注，你可以从这里直接跳到现有 SAM 2 调试页。',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: task.needsMaskInteraction ? _openTaskStatus : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    task.isAwaitingMaskConfirmation ? '进入预览确认页' : '进入点选标注页',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTrainingCard(ReconstructionTask? task) {
    final stepState = !_hasTask
        ? _FlowCardState.waiting
        : task!.isReady
        ? _FlowCardState.done
        : task.isFailed || task.isCancelled
        ? _FlowCardState.error
        : task.status == 'training' || task.status == 'exporting'
        ? _FlowCardState.active
        : _FlowCardState.waiting;

    return _FlowStepCard(
      number: 5,
      title: '训练与导出',
      subtitle: '这一段直接复用现有 nerfstudio / splatfacto 训练链，并在结束后生成 viewer 可消费的模型。',
      state: stepState,
      child: task == null
          ? const Text('完成前面的草稿和配置后，系统才会进入训练。')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (task.progress.clamp(0, 100)) / 100,
                ),
                const SizedBox(height: 12),
                Text('训练状态：${_statusText(task)}'),
                if (task.trainStep != null && task.trainTotalSteps != null) ...[
                  const SizedBox(height: 8),
                  Text('训练步数：${task.trainStep} / ${task.trainTotalSteps}'),
                ],
                if (task.trainEta != null && task.trainEta!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('预计剩余：${task.trainEta}'),
                ],
                if (task.isReady) ...[
                  const SizedBox(height: 8),
                  const Text('模型已经生成，可以继续进入后续 viewer 校准步骤。'),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _openTaskStatus,
                  child: const Text('查看训练详情'),
                ),
              ],
            ),
    );
  }

  Widget _buildViewerStepCard({
    required int number,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool completed,
    VoidCallback? onReopen,
  }) {
    return _FlowStepCard(
      number: number,
      title: title,
      subtitle: subtitle,
      state: !_canShowViewerSteps
          ? _FlowCardState.waiting
          : completed
          ? _FlowCardState.done
          : enabled
          ? _FlowCardState.active
          : _FlowCardState.waiting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            completed
                ? '已完成本步。你仍然可以再次进入 viewer 继续调整。'
                : '进入全屏 viewer 后，按说明完成操作并返回确认。',
          ),
          if (completed && onReopen != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onReopen,
              child: const Text('重新进入 viewer 调整'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimationPreviewCard(ReconstructionTask? task) {
    final enabled = _initialViewDone && _canShowViewerSteps;
    return _FlowStepCard(
      number: 9,
      title: '预览商品展示动画',
      subtitle: '卖家在全屏 viewer 中预览最终商品展示动画；如果不满意，可以返回第 6-8 步重新调整。',
      state: !_initialViewDone
          ? _FlowCardState.waiting
          : _animationApproved
          ? _FlowCardState.done
          : _FlowCardState.active,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('建议先进入 viewer，点击“动画展示”检查默认展示效果。'),
          const SizedBox(height: 12),
          Text(enabled ? '使用底部主按钮进入动画预览。' : '等待前面的 viewer 步骤完成后，底部主按钮会进入动画预览。'),
          if (_animationApproved && task != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _openAnimationPreviewViewerStep,
              child: const Text('重新进入 viewer 预览动画'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinalPublishCard(ReconstructionTask? task) {
    final state = task?.isPublished == true
        ? _FlowCardState.done
        : _animationApproved
        ? _FlowCardState.active
        : _FlowCardState.waiting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _FlowStepCard(
            number: 10,
            title: '横屏内嵌 viewer 确认发布',
            subtitle: '这一步模拟最终电商详情页的 3D 卡片：横屏、自动播放、只允许买家移动视角，不允许编辑模型。',
            state: state,
            child: Text(
              task == null
                  ? '完成前面的流程后，这里会显示最终发布预览。'
                  : (task.isPublished
                        ? '商品已经发布成功。现在首页和买家详情页都会以只读 viewer 的形式展示它。'
                        : '当前窗口会自动播放商品展示动画。你可以拖动画面检查买家实际看到的交互效果。'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: task != null && task.canOpenViewer
              ? ViewerFrame(
                  viewerUrl: task.viewerUrl!,
                  additionalQueryParameters: const {
                    'readonly': '1',
                    'embed': '1',
                    'autoplay': '1',
                    'minimal': '1',
                  },
                )
              : Container(
                  color: Colors.black87,
                  alignment: Alignment.center,
                  child: const Text(
                    '等待模型生成完成',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
        ),
        if (task != null && task.isPublished) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _openBuyerPreview,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('查看买家详情页'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ViewerWorkflowPage extends StatelessWidget {
  const _ViewerWorkflowPage({
    required this.title,
    required this.headline,
    required this.description,
    required this.actionLabel,
    required this.viewerUrl,
    this.queryParameters = const {},
  });

  final String title;
  final String headline;
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(description),
              ],
            ),
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
                      child: const Text('稍后再说'),
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

enum _FlowCardState { done, active, waiting, error, skipped }

class _PublishFlowStep {
  const _PublishFlowStep({
    required this.number,
    required this.title,
    required this.state,
  });

  final int number;
  final String title;
  final _FlowCardState state;
}

class _StepTimeline extends StatelessWidget {
  const _StepTimeline({required this.steps, required this.currentStepIndex});

  final List<_PublishFlowStep> steps;
  final int currentStepIndex;

  Color _colorForStep(BuildContext context, _FlowCardState state) {
    return switch (state) {
      _FlowCardState.done => Colors.green,
      _FlowCardState.active => Theme.of(context).colorScheme.primary,
      _FlowCardState.error => Theme.of(context).colorScheme.error,
      _FlowCardState.skipped => Theme.of(context).colorScheme.secondary,
      _FlowCardState.waiting => Theme.of(context).colorScheme.outlineVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = steps[currentStepIndex];

    return Material(
      elevation: 1,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(steps.length, (index) {
                final step = steps[index];
                final color = _colorForStep(context, step.state);
                return Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index == 0
                              ? Colors.transparent
                              : _colorForStep(
                                  context,
                                  steps[index - 1].state == _FlowCardState.done
                                      ? _FlowCardState.done
                                      : step.state,
                                ),
                        ),
                      ),
                      Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Text(
                          '${step.number}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index == steps.length - 1
                              ? Colors.transparent
                              : _colorForStep(context, step.state),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(
              '步骤 ${currentStep.number} / ${steps.length}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              currentStep.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowStepCard extends StatelessWidget {
  const _FlowStepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.child,
  });

  final int number;
  final String title;
  final String subtitle;
  final _FlowCardState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chipColor = switch (state) {
      _FlowCardState.done => Colors.green,
      _FlowCardState.active => Theme.of(context).colorScheme.primary,
      _FlowCardState.error => Theme.of(context).colorScheme.error,
      _FlowCardState.skipped => Theme.of(context).colorScheme.secondary,
      _FlowCardState.waiting => Theme.of(context).colorScheme.outline,
    };
    final label = switch (state) {
      _FlowCardState.done => '已完成',
      _FlowCardState.active => '当前步骤',
      _FlowCardState.error => '需要处理',
      _FlowCardState.skipped => '已跳过',
      _FlowCardState.waiting => '待开始',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: chipColor.withValues(alpha: 0.12),
                  foregroundColor: chipColor,
                  child: Text('$number'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(subtitle),
                    ],
                  ),
                ),
                Chip(label: Text(label)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
