import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reconstruction_task.dart';
import '../services/api_client.dart';
import 'viewer_page.dart';

class TaskStatusPage extends StatefulWidget {
  const TaskStatusPage({
    super.key,
    required this.client,
    required this.initialTask,
  });

  final ApiClient client;
  final ReconstructionTask initialTask;

  @override
  State<TaskStatusPage> createState() => _TaskStatusPageState();
}

class _TaskStatusPageState extends State<TaskStatusPage> {
  Timer? _timer;
  late ReconstructionTask _task;
  _MaskPreviewManifest? _maskPreviewManifest;
  String? _loadedMaskPreviewManifestUrl;
  String? _preloadingMaskPreviewManifestUrl;
  Directory? _maskPreviewLocalCacheDir;
  Map<String, String> _maskPreviewLocalFiles = const {};
  String? _errorMessage;
  bool _isRefreshing = false;
  bool _isStartingPipeline = false;
  bool _isStartingMaskDebug = false;
  bool _isCancellingPipeline = false;
  bool _isGeneratingMaskPreview = false;
  bool _isConfirmingMaskPreview = false;
  bool _isLoadingMaskPreviewManifest = false;
  bool _isPreloadingMaskPreviewAssets = false;
  int _maskPreviewPreloadedAssets = 0;
  int _maskPreviewTotalAssets = 0;
  String _selectedQualityProfile = 'balanced';
  int _selectedTrainMaxSteps = 7000;
  bool _objectMasking = false;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _selectedQualityProfile = _task.qualityProfile ?? 'balanced';
    _selectedTrainMaxSteps = _task.trainMaxSteps ?? 7000;
    _objectMasking = _task.objectMasking;
    _syncMaskPreviewManifest(_task);
    _refreshTask();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshTask());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_clearMaskPreviewLocalCache());
    super.dispose();
  }

  bool _shouldPreserveLocalTrainingSettings(String status) {
    return status == 'uploaded' || status == 'failed' || status == 'cancelled';
  }

  Future<void> _syncMaskPreviewManifest(ReconstructionTask task) async {
    final manifestUrl = task.maskPreviewManifestUrl;
    if (manifestUrl == null || manifestUrl.isEmpty) {
      await _clearMaskPreviewLocalCache();
      if (mounted) {
        setState(() {
          _maskPreviewManifest = null;
          _loadedMaskPreviewManifestUrl = null;
          _isLoadingMaskPreviewManifest = false;
        });
      }
      return;
    }

    if (_loadedMaskPreviewManifestUrl == manifestUrl ||
        _isLoadingMaskPreviewManifest) {
      return;
    }

    setState(() {
      _isLoadingMaskPreviewManifest = true;
    });

    try {
      final payload = await widget.client.fetchMaskPreviewManifest(manifestUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        final manifest = _MaskPreviewManifest.fromJson(
          payload,
          manifestUrl,
        );
        _maskPreviewManifest = manifest;
        _loadedMaskPreviewManifestUrl = manifestUrl;
      });
      final manifest = _maskPreviewManifest;
      if (manifest != null) {
        unawaited(_preloadMaskPreviewAssets(manifest, manifestUrl));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载全帧预览失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMaskPreviewManifest = false;
        });
      }
    }
  }

  Future<void> _clearMaskPreviewLocalCache() async {
    _preloadingMaskPreviewManifestUrl = null;
    final cacheDir = _maskPreviewLocalCacheDir;
    _maskPreviewLocalCacheDir = null;
    _maskPreviewLocalFiles = const {};
    _isPreloadingMaskPreviewAssets = false;
    _maskPreviewPreloadedAssets = 0;
    _maskPreviewTotalAssets = 0;
    if (cacheDir != null) {
      try {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _preloadMaskPreviewAssets(
    _MaskPreviewManifest manifest,
    String manifestUrl,
  ) async {
    if (_preloadingMaskPreviewManifestUrl == manifestUrl ||
        (_loadedMaskPreviewManifestUrl == manifestUrl &&
            _maskPreviewLocalFiles.isNotEmpty &&
            _maskPreviewTotalAssets > 0 &&
            _maskPreviewPreloadedAssets >= _maskPreviewTotalAssets)) {
      return;
    }

    await _clearMaskPreviewLocalCache();

    final cacheDir = await Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}3dgs_mask_preview_${_task.taskId}_${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);

    final assets = <({String url, String localPath})>[];
    for (final frame in manifest.frames) {
      if (frame.imageUrl.isNotEmpty) {
        assets.add((
          url: frame.imageUrl,
          localPath:
              '${cacheDir.path}${Platform.pathSeparator}raw_${frame.index.toString().padLeft(5, '0')}.jpg',
        ));
      }
      if (frame.previewUrl.isNotEmpty) {
        assets.add((
          url: frame.previewUrl,
          localPath:
              '${cacheDir.path}${Platform.pathSeparator}preview_${frame.index.toString().padLeft(5, '0')}.jpg',
        ));
      }
    }

    if (!mounted) {
      await _clearMaskPreviewLocalCache();
      return;
    }

    setState(() {
      _preloadingMaskPreviewManifestUrl = manifestUrl;
      _maskPreviewLocalCacheDir = cacheDir;
      _maskPreviewLocalFiles = const {};
      _isPreloadingMaskPreviewAssets = true;
      _maskPreviewPreloadedAssets = 0;
      _maskPreviewTotalAssets = assets.length;
    });

    const batchSize = 4;
    for (var offset = 0; offset < assets.length; offset += batchSize) {
      if (_preloadingMaskPreviewManifestUrl != manifestUrl) {
        return;
      }

      final batch = assets.sublist(
        offset,
        math.min(offset + batchSize, assets.length),
      );

      final downloaded = <({String url, String localPath})>[];
      await Future.wait(
        batch.map((asset) async {
          try {
            await widget.client.downloadFile(asset.url, asset.localPath);
            downloaded.add(asset);
          } catch (_) {}
        }),
      );

      if (!mounted || _preloadingMaskPreviewManifestUrl != manifestUrl) {
        return;
      }

      setState(() {
        final next = Map<String, String>.from(_maskPreviewLocalFiles);
        for (final asset in downloaded) {
          next[asset.url] = asset.localPath;
        }
        _maskPreviewLocalFiles = next;
        _maskPreviewPreloadedAssets += downloaded.length;
      });
    }

    if (!mounted || _preloadingMaskPreviewManifestUrl != manifestUrl) {
      return;
    }

    setState(() {
      _isPreloadingMaskPreviewAssets = false;
    });
  }

  Future<void> _refreshTask() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      final task = await widget.client.fetchTask(_task.taskId);
      if (!mounted) {
        return;
      }
      final preserveLocalTrainingSettings =
          _shouldPreserveLocalTrainingSettings(task.status);
      setState(() {
        _task = task;
        _errorMessage = null;
        if (!preserveLocalTrainingSettings) {
          _selectedQualityProfile =
              task.qualityProfile ?? _selectedQualityProfile;
          _selectedTrainMaxSteps = task.trainMaxSteps ?? _selectedTrainMaxSteps;
          _objectMasking = task.objectMasking;
        }
      });
      await _syncMaskPreviewManifest(task);
      if (task.isReady || task.isFailed || task.isCancelled) {
        _timer?.cancel();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新状态失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openViewer() async {
    try {
      final latestTask = await widget.client.fetchTask(_task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _task = latestTask;
        _errorMessage = null;
      });

      if (!latestTask.isReady || latestTask.viewerUrl == null) {
        setState(() {
          _errorMessage = '当前任务还没有可用 Viewer 地址。';
        });
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ViewerPage(
            viewerUrl: latestTask.viewerUrl!,
            taskTitle: latestTask.title,
          ),
        ),
      );
      await _refreshTask();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '打开模型前刷新任务失败：$error';
      });
    }
  }

  Future<void> _startPipeline() async {
    setState(() {
      _isStartingPipeline = true;
      _errorMessage = null;
    });

    try {
      final task = await widget.client.startPipeline(
        taskId: _task.taskId,
        qualityProfile: _selectedQualityProfile,
        trainMaxSteps: _selectedTrainMaxSteps,
        objectMasking: _objectMasking,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskPreviewManifest(task);
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshTask(),
      );
      await _refreshTask();
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

  Future<void> _cancelPipeline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终止流水线'),
        content: const Text('确定要终止当前流水线吗？当前训练或 COLMAP 进程会被强制结束，任务会标记为已终止。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('终止'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isCancellingPipeline = true;
      _errorMessage = null;
    });

    try {
      final task = await widget.client.cancelPipeline(_task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      _timer?.cancel();
      await _refreshTask();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '终止流水线失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCancellingPipeline = false;
        });
      }
    }
  }

  Future<void> _startMaskDebug() async {
    setState(() {
      _isStartingMaskDebug = true;
      _errorMessage = null;
    });

    try {
      final task = await widget.client.startMaskDebug(_task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskPreviewManifest(task);
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshTask(),
      );
      await _refreshTask();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '进入 Mask 调试失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStartingMaskDebug = false;
        });
      }
    }
  }

  Future<void> _previewMaskPrompts(List<_MaskPromptPoint> points) async {
    if (points.where((point) => point.label == 1).isEmpty) {
      setState(() {
        _errorMessage = '请至少点选一个商品主体点。';
      });
      return;
    }

    setState(() {
      _isGeneratingMaskPreview = true;
      _errorMessage = null;
    });

    try {
      final task = await widget.client.previewMaskPrompts(
        taskId: _task.taskId,
        points: points
            .map((point) => {'x': point.x, 'y': point.y, 'label': point.label})
            .toList(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskPreviewManifest(task);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '生成 Mask 预览失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMaskPreview = false;
        });
      }
    }
  }

  Future<void> _confirmMaskPreview() async {
    setState(() {
      _isConfirmingMaskPreview = true;
      _errorMessage = null;
    });

    try {
      final task = await widget.client.confirmMaskPreview(_task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskPreviewManifest(task);
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshTask(),
      );
      await _refreshTask();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '确认 Mask 预览失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConfirmingMaskPreview = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = (_task.progress.clamp(0, 100)) / 100;
    final trainProgressText =
        (_task.trainStep != null && _task.trainTotalSteps != null)
        ? '${_task.trainStep} / ${_task.trainTotalSteps}'
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('任务状态')),
      body: RefreshIndicator(
        onRefresh: _refreshTask,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _task.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('task_id: ${_task.taskId}'),
            const SizedBox(height: 20),
            _StatusCard(task: _task, progressValue: progressValue),
            if (_task.status == 'uploaded' ||
                _task.status == 'failed' ||
                _task.status == 'cancelled') ...[
              const SizedBox(height: 20),
              _TrainingSettingsCard(
                selectedQualityProfile: _selectedQualityProfile,
                selectedTrainMaxSteps: _selectedTrainMaxSteps,
                objectMasking: _objectMasking,
                isStarting: _isStartingPipeline,
                isRetry:
                    _task.status == 'failed' || _task.status == 'cancelled',
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
            ],
            if (_task.canDebugMasking && !_task.needsMaskInteraction) ...[
              const SizedBox(height: 20),
              _MaskDebugCard(
                isStarting: _isStartingMaskDebug,
                onStart: _startMaskDebug,
              ),
            ],
            if (_task.needsMaskInteraction) ...[
              const SizedBox(height: 20),
              _MaskPromptCard(
                task: _task,
                previewManifest: _maskPreviewManifest,
                isLoadingPreviewManifest: _isLoadingMaskPreviewManifest,
                localPreviewFiles: _maskPreviewLocalFiles,
                isPreloadingPreviewAssets: _isPreloadingMaskPreviewAssets,
                preloadedPreviewAssets: _maskPreviewPreloadedAssets,
                totalPreviewAssets: _maskPreviewTotalAssets,
                isGeneratingPreview: _isGeneratingMaskPreview,
                isConfirming: _isConfirmingMaskPreview,
                onPreview: _previewMaskPrompts,
                onConfirm: _confirmMaskPreview,
              ),
            ],
            if (_task.isPipelineActive || _task.needsMaskInteraction) ...[
              const SizedBox(height: 20),
              _PipelineControlCard(
                isCancelling: _isCancellingPipeline,
                onCancel: _cancelPipeline,
              ),
            ],
            if (_task.logTail.isNotEmpty) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '实时日志',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _task.logTail.join('\n'),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '联调说明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('后端地址：${widget.client.baseUrl}'),
                    const SizedBox(height: 8),
                    Text('视频地址：${_task.videoUrl ?? "未生成"}'),
                    const SizedBox(height: 8),
                    Text('模型地址：${_task.modelUrl ?? "未生成"}'),
                    const SizedBox(height: 8),
                    Text('Viewer 地址：${_task.viewerUrl ?? "未生成"}'),
                    const SizedBox(height: 8),
                    Text('日志地址：${_task.logUrl ?? "未生成"}'),
                    if (_task.qualityProfile != null) ...[
                      const SizedBox(height: 8),
                      Text('质量档位：${_task.qualityProfile}'),
                    ],
                    if (_task.trainMaxSteps != null) ...[
                      const SizedBox(height: 8),
                      Text('最大训练步数：${_task.trainMaxSteps}'),
                    ],
                    const SizedBox(height: 8),
                    Text('Object masking：${_task.objectMasking ? "开启" : "关闭"}'),
                    if (_task.maskPromptFrameUrl != null) ...[
                      const SizedBox(height: 8),
                      Text('Mask 提示帧：${_task.maskPromptFrameUrl}'),
                    ],
                    if (_task.maskPreviewUrl != null) ...[
                      const SizedBox(height: 8),
                      Text('Mask 预览图：${_task.maskPreviewUrl}'),
                    ],
                    if (_task.maskPreviewManifestUrl != null) ...[
                      const SizedBox(height: 8),
                      Text('Mask 预览清单：${_task.maskPreviewManifestUrl}'),
                    ],
                    if (_task.maskSummaryUrl != null) ...[
                      const SizedBox(height: 8),
                      Text('Mask 摘要：${_task.maskSummaryUrl}'),
                    ],
                    if (trainProgressText != null) ...[
                      const SizedBox(height: 8),
                      Text('训练步数：$trainProgressText'),
                    ],
                    if (_task.trainEta != null) ...[
                      const SizedBox(height: 8),
                      Text('训练 ETA：${_task.trainEta}'),
                    ],
                    if (_task.mockMode) ...[
                      const SizedBox(height: 12),
                      const Text('当前任务通过 mock 管道完成，产物用于联调查看器，不代表真实训练结果。'),
                    ],
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _task.isReady && _task.viewerUrl != null
                  ? _openViewer
                  : null,
              icon: const Icon(Icons.view_in_ar_outlined),
              label: const Text('查看 3D 模型'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskPromptPoint {
  const _MaskPromptPoint({
    required this.x,
    required this.y,
    required this.label,
  });

  final double x;
  final double y;
  final int label;
}

class _MaskPromptCard extends StatefulWidget {
  const _MaskPromptCard({
    required this.task,
    required this.previewManifest,
    required this.isLoadingPreviewManifest,
    required this.localPreviewFiles,
    required this.isPreloadingPreviewAssets,
    required this.preloadedPreviewAssets,
    required this.totalPreviewAssets,
    required this.isGeneratingPreview,
    required this.isConfirming,
    required this.onPreview,
    required this.onConfirm,
  });

  final ReconstructionTask task;
  final _MaskPreviewManifest? previewManifest;
  final bool isLoadingPreviewManifest;
  final Map<String, String> localPreviewFiles;
  final bool isPreloadingPreviewAssets;
  final int preloadedPreviewAssets;
  final int totalPreviewAssets;
  final bool isGeneratingPreview;
  final bool isConfirming;
  final ValueChanged<List<_MaskPromptPoint>> onPreview;
  final VoidCallback onConfirm;

  @override
  State<_MaskPromptCard> createState() => _MaskPromptCardState();
}

class _MaskPromptCardState extends State<_MaskPromptCard> {
  final List<_MaskPromptPoint> _points = [];
  bool _negativeMode = false;
  bool _showPreview = false;
  int _currentPreviewFrameIndex = 0;

  @override
  void initState() {
    super.initState();
    _showPreview = widget.previewManifest != null;
    _currentPreviewFrameIndex = widget.previewManifest?.promptFrameIndex ?? 0;
  }

  @override
  void didUpdateWidget(covariant _MaskPromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.maskPreviewManifestUrl !=
        oldWidget.task.maskPreviewManifestUrl) {
      _showPreview = widget.previewManifest != null;
      _currentPreviewFrameIndex = widget.previewManifest?.promptFrameIndex ?? 0;
    }
  }

  bool get _isBusy => widget.isGeneratingPreview || widget.isConfirming;

  bool get _canEditPoints {
    if (_isBusy) {
      return false;
    }
    final manifest = widget.previewManifest;
    if (manifest == null) {
      return widget.task.maskPromptFrameUrl != null;
    }
    return !_showPreview &&
        _currentPreviewFrameIndex == manifest.promptFrameIndex;
  }

  _MaskPreviewFrame? get _selectedPreviewFrame {
    final manifest = widget.previewManifest;
    if (manifest == null || manifest.frames.isEmpty) {
      return null;
    }
    final safeIndex = _currentPreviewFrameIndex.clamp(
      0,
      manifest.frames.length - 1,
    );
    return manifest.frames[safeIndex];
  }

  void _addPoint(TapDownDetails details, BoxConstraints constraints) {
    if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
      return;
    }
    final x = (details.localPosition.dx / constraints.maxWidth)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = (details.localPosition.dy / constraints.maxHeight)
        .clamp(0.0, 1.0)
        .toDouble();
    setState(() {
      _points.add(_MaskPromptPoint(x: x, y: y, label: _negativeMode ? 0 : 1));
    });
  }

  void _undoPoint() {
    if (_points.isEmpty) {
      return;
    }
    setState(() {
      _points.removeLast();
    });
  }

  double get _aspectRatio {
    final manifest = widget.previewManifest;
    if (manifest != null &&
        manifest.frameWidth > 0 &&
        manifest.frameHeight > 0) {
      return manifest.frameWidth / manifest.frameHeight;
    }
    final width = widget.task.maskPromptFrameWidth;
    final height = widget.task.maskPromptFrameHeight;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 9 / 16;
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = widget.previewManifest != null;
    final selectedPreviewFrame = _selectedPreviewFrame;
    final imageUrl = selectedPreviewFrame != null
        ? (_showPreview
              ? selectedPreviewFrame.previewUrl
              : selectedPreviewFrame.imageUrl)
        : (_showPreview && widget.task.maskPreviewUrl != null
              ? widget.task.maskPreviewUrl
              : widget.task.maskPromptFrameUrl);
    final localImagePath = imageUrl == null
        ? null
        : widget.localPreviewFiles[imageUrl];
    final positiveCount = _points.where((point) => point.label == 1).length;
    final negativeCount = _points.length - positiveCount;
    final instructions = hasPreview
        ? '已生成全帧分割预览。拖动进度条查看任意时刻的商品分割效果；如需补点，请切回原始帧并回到提示帧。'
        : '请先在第一帧点选要保留的商品主体。绿色为商品正点；如果分割容易包含背景，可切到负点模式点击背景，再生成全帧分割预览。';
    final frameCount = widget.previewManifest?.frameCount ?? 0;
    final promptFrameIndex = widget.previewManifest?.promptFrameIndex ?? 0;
    final currentFrameLabel = selectedPreviewFrame == null
        ? (widget.task.maskPromptFrameName ?? 'frame_00001.png')
        : selectedPreviewFrame.name;
    final currentFrameText = frameCount > 0
        ? '当前帧：${_currentPreviewFrameIndex + 1} / $frameCount · $currentFrameLabel'
        : '当前帧：$currentFrameLabel';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Object Masking',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              instructions,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.task.maskPromptFrameName != null) ...[
              const SizedBox(height: 8),
              Text('提示帧：${widget.task.maskPromptFrameName}'),
            ],
            if (widget.isLoadingPreviewManifest) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('正在加载全帧预览清单...'),
            ],
            if (hasPreview &&
                (widget.isPreloadingPreviewAssets ||
                    widget.preloadedPreviewAssets > 0)) ...[
              const SizedBox(height: 12),
              Text(
                widget.totalPreviewAssets > 0
                    ? '本地预加载：${widget.preloadedPreviewAssets} / ${widget.totalPreviewAssets}'
                    : '正在准备本地预加载...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (hasPreview) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('原始帧'),
                    selected: !_showPreview,
                    onSelected: _isBusy
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _showPreview = false;
                              });
                            }
                          },
                  ),
                  ChoiceChip(
                    label: const Text('分割预览'),
                    selected: _showPreview,
                    onSelected: _isBusy
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _showPreview = true;
                              });
                            }
                          },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (hasPreview) ...[
              Text(currentFrameText),
              const SizedBox(height: 8),
              Slider(
                value: _currentPreviewFrameIndex.toDouble(),
                min: 0,
                max: (frameCount - 1).toDouble(),
                onChanged: frameCount <= 1 || _isBusy
                    ? null
                    : (value) {
                        setState(() {
                          _currentPreviewFrameIndex = value.round();
                        });
                      },
              ),
              Text(
                _currentPreviewFrameIndex == promptFrameIndex
                    ? '当前是提示帧，可以继续补点。'
                    : '当前不是提示帧。如需补点，请把滑杆移回提示帧并切到原始帧。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (imageUrl == null)
              const Text('等待后端生成提示帧。')
            else
              AspectRatio(
                aspectRatio: _aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapDown: _canEditPoints
                          ? (details) => _addPoint(details, constraints)
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (localImagePath != null)
                            Image.file(
                              File(localImagePath),
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(child: Text('本地预览图加载失败：$error')),
                            )
                          else
                            Image.network(
                              imageUrl,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(child: Text('预览图加载失败：$error')),
                            ),
                          if (!hasPreview ||
                              (!_showPreview &&
                                  _currentPreviewFrameIndex ==
                                      promptFrameIndex))
                            for (final point in _points)
                              Positioned(
                                left: point.x * constraints.maxWidth - 9,
                                top: point.y * constraints.maxHeight - 9,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: point.label == 1
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    border: Border.all(
                                      color: Colors.black87,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _negativeMode,
              onChanged: !_canEditPoints
                  ? null
                  : (value) {
                      setState(() {
                        _negativeMode = value;
                      });
                    },
              contentPadding: EdgeInsets.zero,
              title: const Text('负点模式'),
              subtitle: const Text('关闭时点击商品；开启时点击背景或不应保留的区域。'),
            ),
            Text('已添加正点 $positiveCount 个，负点 $negativeCount 个。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: !_canEditPoints || _points.isEmpty
                      ? null
                      : _undoPoint,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('撤销上一个点'),
                ),
                OutlinedButton.icon(
                  onPressed: !_canEditPoints || _points.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _points.clear();
                          });
                        },
                  icon: const Icon(Icons.clear_outlined),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isBusy ||
                          widget.task.maskPromptFrameUrl == null ||
                          positiveCount == 0
                      ? null
                      : () => widget.onPreview(List.unmodifiable(_points)),
                  icon: widget.isGeneratingPreview
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: Text(
                    widget.isGeneratingPreview
                        ? '生成预览中...'
                        : (hasPreview ? '重新生成全帧预览' : '生成全帧分割预览'),
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      _isBusy ||
                          !widget.task.isAwaitingMaskConfirmation ||
                          widget.previewManifest == null
                      ? null
                      : widget.onConfirm,
                  icon: widget.isConfirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(widget.isConfirming ? '确认中...' : '确认预览并开始训练'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskPreviewManifest {
  const _MaskPreviewManifest({
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
  final List<_MaskPreviewFrame> frames;

  factory _MaskPreviewManifest.fromJson(
    Map<String, dynamic> json,
    String baseUrl,
  ) {
    String resolveUrl(Object? value) {
      final raw = value?.toString() ?? '';
      if (raw.isEmpty) {
        return '';
      }
      final parsed = Uri.tryParse(raw);
      if (parsed != null && parsed.hasScheme) {
        return raw;
      }
      return Uri.parse(baseUrl).resolve(raw).toString();
    }

    final framePayload = (json['frames'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final frames = framePayload
        .map(
          (item) => _MaskPreviewFrame(
            index: (item['index'] ?? 0) as int,
            name: (item['name'] ?? '') as String,
            imageUrl: resolveUrl(item['image_rel_url']),
            previewUrl: resolveUrl(item['preview_rel_url']),
          ),
        )
        .toList();

    final promptFrameIndex = (json['prompt_frame_index'] ?? 0) as int;
    return _MaskPreviewManifest(
      frameCount: (json['frame_count'] ?? frames.length) as int,
      promptFrameIndex: frames.isEmpty
          ? 0
          : promptFrameIndex.clamp(0, frames.length - 1),
      frameWidth: (json['frame_width'] ?? 0) as int,
      frameHeight: (json['frame_height'] ?? 0) as int,
      frames: frames,
    );
  }
}

class _MaskPreviewFrame {
  const _MaskPreviewFrame({
    required this.index,
    required this.name,
    required this.imageUrl,
    required this.previewUrl,
  });

  final int index;
  final String name;
  final String imageUrl;
  final String previewUrl;
}

class _TrainingSettingsCard extends StatelessWidget {
  const _TrainingSettingsCard({
    required this.selectedQualityProfile,
    required this.selectedTrainMaxSteps,
    required this.objectMasking,
    required this.isStarting,
    required this.isRetry,
    required this.onQualityProfileChanged,
    required this.onTrainMaxStepsChanged,
    required this.onStart,
    this.onObjectMaskingChanged,
  });

  final String selectedQualityProfile;
  final int selectedTrainMaxSteps;
  final bool objectMasking;
  final bool isStarting;
  final bool isRetry;
  final ValueChanged<String> onQualityProfileChanged;
  final ValueChanged<int> onTrainMaxStepsChanged;
  final ValueChanged<bool>? onObjectMaskingChanged;
  final VoidCallback onStart;

  static const _qualityProfiles = <_QualityProfileOption>[
    _QualityProfileOption(
      value: 'fast',
      label: 'Fast',
      description: '最长边 1600，适合快速验证。',
    ),
    _QualityProfileOption(
      value: 'balanced',
      label: 'Balanced',
      description: '最长边 2560，默认推荐。',
    ),
    _QualityProfileOption(
      value: 'quality',
      label: 'Quality',
      description: '最长边 3200，细节更好但更耗时。',
    ),
    _QualityProfileOption(
      value: 'raw',
      label: 'Raw',
      description: '不主动缩放，仅建议实验。',
    ),
  ];

  static const _trainStepOptions = <int>[7000, 30000];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '训练设置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isRetry ? '上次流水线失败。调整配置后可以重新启动训练。' : '任务已创建但尚未开始训练。确认配置后手动启动流水线。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedQualityProfile,
              decoration: const InputDecoration(
                labelText: '质量档位',
                border: OutlineInputBorder(),
              ),
              items: _qualityProfiles
                  .map(
                    (profile) => DropdownMenuItem<String>(
                      value: profile.value,
                      child: Text('${profile.label} · ${profile.description}'),
                    ),
                  )
                  .toList(),
              onChanged: isStarting
                  ? null
                  : (value) {
                      if (value != null) {
                        onQualityProfileChanged(value);
                      }
                    },
            ),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: _trainStepOptions
                  .map(
                    (steps) => ButtonSegment<int>(
                      value: steps,
                      label: Text('$steps 轮'),
                    ),
                  )
                  .toList(),
              selected: {selectedTrainMaxSteps},
              onSelectionChanged: isStarting
                  ? null
                  : (values) {
                      if (values.isNotEmpty) {
                        onTrainMaxStepsChanged(values.first);
                      }
                    },
            ),
            const SizedBox(height: 12),
            Text(
              selectedTrainMaxSteps == 7000
                  ? '默认使用 7000 轮，优先缩短本地 MVP 等待时间。'
                  : '30000 轮用于高质量对比，耗时明显更长。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: objectMasking,
              onChanged: isStarting ? null : onObjectMaskingChanged,
              contentPadding: EdgeInsets.zero,
              title: const Text('Object masking'),
              subtitle: const Text(
                '开启后会在 COLMAP 完成后暂停，需先在第一帧点选并预览分割结果，确认后才继续训练。Raw 档暂不支持。',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isStarting ? null : onStart,
              icon: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_outlined),
              label: Text(
                isStarting ? '启动中...' : (isRetry ? '重新开始训练流水线' : '开始训练流水线'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskDebugCard extends StatelessWidget {
  const _MaskDebugCard({required this.isStarting, required this.onStart});

  final bool isStarting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mask 调试',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '当前任务已经有可复用的 COLMAP / transforms 数据。点击后会直接回到第一帧 Mask 提示页，跳过重新跑 COLMAP，适合反复调试 SAM 2 点选与预览效果。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isStarting ? null : onStart,
              icon: isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bug_report_outlined),
              label: Text(isStarting ? '进入中...' : '跳过 COLMAP，直接调试 Masking'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityProfileOption {
  const _QualityProfileOption({
    required this.value,
    required this.label,
    required this.description,
  });

  final String value;
  final String label;
  final String description;
}

class _PipelineControlCard extends StatelessWidget {
  const _PipelineControlCard({
    required this.isCancelling,
    required this.onCancel,
  });

  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '流水线控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '如果本次质量档位或耗时不符合预期，可以终止当前流水线，之后重新选择配置再启动。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: isCancelling ? null : onCancel,
              icon: isCancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(isCancelling ? '终止中...' : '终止流水线'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.task, required this.progressValue});

  final ReconstructionTask task;
  final double progressValue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '流水线状态',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Chip(label: Text(task.status)),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 12),
            Text('当前进度：${task.progress}%'),
            if (task.statusMessage != null &&
                task.statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('阶段说明：${task.statusMessage}'),
            ],
            if (task.trainStep != null && task.trainTotalSteps != null) ...[
              const SizedBox(height: 8),
              Text('训练步数：${task.trainStep} / ${task.trainTotalSteps}'),
            ],
            if (task.trainEta != null && task.trainEta!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('训练 ETA：${task.trainEta}'),
            ],
            if (task.errorMessage != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                '失败原因：${task.errorMessage}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
