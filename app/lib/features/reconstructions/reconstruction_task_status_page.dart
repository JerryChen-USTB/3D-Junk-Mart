import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/reconstructions/reconstruction_models.dart';
import '../../core/reconstructions/reconstructions_repository.dart';
import '../../theme/app_colors.dart';
import '../viewer/viewer_page.dart';

class ReconstructionTaskStatusPage extends StatefulWidget {
  const ReconstructionTaskStatusPage({
    super.key,
    required this.repository,
    required this.initialTask,
    this.accessToken,
  });

  final ReconstructionsRepository repository;
  final ReconstructionTask initialTask;
  final String? accessToken;

  @override
  State<ReconstructionTaskStatusPage> createState() =>
      _ReconstructionTaskStatusPageState();
}

class _ReconstructionTaskStatusPageState
    extends State<ReconstructionTaskStatusPage> {
  Timer? _timer;
  late ReconstructionTask _task;
  MaskPreviewManifest? _maskManifest;
  String? _maskManifestUrl;
  bool _negativeMode = false;
  bool _isRefreshing = false;
  bool _isStartingPipeline = false;
  bool _isCancelling = false;
  bool _isStartingMaskDebug = false;
  bool _isGeneratingMaskPreview = false;
  bool _isConfirmingMaskPreview = false;
  bool _isLoadingMaskManifest = false;
  int _selectedTrainMaxSteps = 7000;
  String _selectedQualityProfile = 'balanced';
  bool _objectMasking = false;
  int _selectedFrameIndex = 0;
  bool _showPreview = true;
  String? _errorMessage;
  final List<MaskPromptPoint> _points = <MaskPromptPoint>[];

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _selectedQualityProfile = _task.qualityProfile ?? 'balanced';
    _selectedTrainMaxSteps = _task.trainMaxSteps ?? 7000;
    _objectMasking = _task.objectMasking;
    _syncMaskManifest(_task);
    _refreshTask(silent: true);
    _syncPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncPolling() {
    _timer?.cancel();
    if (_task.isPipelineActive || _task.needsMaskInteraction) {
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshTask(silent: true),
      );
    }
  }

  Future<void> _syncMaskManifest(ReconstructionTask task) async {
    final manifestUrl = task.maskPreviewManifestUrl;
    if (manifestUrl == null || manifestUrl.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _maskManifest = null;
        _maskManifestUrl = null;
        _selectedFrameIndex = 0;
        _showPreview = true;
      });
      return;
    }
    if (_maskManifestUrl == manifestUrl || _isLoadingMaskManifest) {
      return;
    }

    setState(() {
      _isLoadingMaskManifest = true;
    });
    try {
      final manifest = await widget.repository.fetchMaskPreviewManifest(
        manifestUrl,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _maskManifest = manifest;
        _maskManifestUrl = manifestUrl;
        _selectedFrameIndex = manifest.promptFrameIndex;
        _showPreview = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载 Mask 预览失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMaskManifest = false;
        });
      }
    }
  }

  Future<void> _refreshTask({bool silent = false}) async {
    if (_isRefreshing) {
      return;
    }
    if (!silent) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    } else {
      _isRefreshing = true;
    }

    try {
      final task = await widget.repository.fetchTask(
        _task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
        if (!_task.isStartable) {
          _selectedQualityProfile =
              _task.qualityProfile ?? _selectedQualityProfile;
          _selectedTrainMaxSteps =
              _task.trainMaxSteps ?? _selectedTrainMaxSteps;
          _objectMasking = _task.objectMasking;
        }
      });
      await _syncMaskManifest(task);
      _syncPolling();
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      setState(() {
        _errorMessage = '刷新任务失败：$error';
      });
    } finally {
      _isRefreshing = false;
      if (mounted && !silent) {
        setState(() {});
      }
    }
  }

  Future<void> _startPipeline() async {
    setState(() {
      _isStartingPipeline = true;
      _errorMessage = null;
    });
    try {
      final task = await widget.repository.startPipeline(
        taskId: _task.taskId,
        qualityProfile: _selectedQualityProfile,
        trainMaxSteps: _selectedTrainMaxSteps,
        objectMasking: _objectMasking,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
        _points.clear();
      });
      await _syncMaskManifest(task);
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

  Future<void> _cancelPipeline() async {
    setState(() {
      _isCancelling = true;
      _errorMessage = null;
    });
    try {
      final task = await widget.repository.cancelPipeline(
        _task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '终止流程失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
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
      final task = await widget.repository.startMaskDebug(
        _task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
        _points.clear();
      });
      await _syncMaskManifest(task);
      _syncPolling();
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

  Future<void> _previewMaskPrompts() async {
    if (_points.where((item) => item.label == 1).isEmpty) {
      setState(() {
        _errorMessage = '至少要有一个正样本点。';
      });
      return;
    }

    setState(() {
      _isGeneratingMaskPreview = true;
      _errorMessage = null;
    });
    try {
      final task = await widget.repository.previewMaskPrompts(
        taskId: _task.taskId,
        points: List<MaskPromptPoint>.unmodifiable(_points),
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskManifest(task);
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
      final task = await widget.repository.confirmMaskPreview(
        _task.taskId,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task = task;
      });
      await _syncMaskManifest(task);
      _syncPolling();
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

  Future<void> _openViewer() async {
    if (!_task.canOpenViewer || _task.viewerUrl == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerPage(
          viewerUrl: _task.viewerUrl!,
          title: _task.title.isEmpty ? '3D 模型' : _task.title,
        ),
      ),
    );
    await _refreshTask();
  }

  void _addMaskPoint(TapDownDetails details, BoxConstraints constraints) {
    if (!_task.needsMaskInteraction ||
        _task.maskPromptFrameUrl == null ||
        (_maskManifest != null &&
            _selectedFrameIndex != _maskManifest!.promptFrameIndex &&
            _showPreview)) {
      return;
    }
    final x = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final y = (details.localPosition.dy / constraints.maxHeight).clamp(
      0.0,
      1.0,
    );
    setState(() {
      _points.add(MaskPromptPoint(x: x, y: y, label: _negativeMode ? 0 : 1));
    });
  }

  String? _currentMaskImageUrl() {
    final manifest = _maskManifest;
    if (manifest == null || manifest.frames.isEmpty) {
      return _task.maskPromptFrameUrl;
    }
    final frame = manifest.frames[_selectedFrameIndex];
    if (_showPreview && frame.previewUrl.isNotEmpty) {
      return frame.previewUrl;
    }
    if (frame.imageUrl.isNotEmpty) {
      return frame.imageUrl;
    }
    return _task.maskPromptFrameUrl;
  }

  bool _showPointOverlay() {
    if (!_task.needsMaskInteraction) {
      return false;
    }
    if (_maskManifest == null) {
      return true;
    }
    return !_showPreview &&
        _selectedFrameIndex == _maskManifest!.promptFrameIndex;
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = (_task.progress.clamp(0, 100)) / 100;
    return Scaffold(
      appBar: AppBar(
        title: Text(_task.title.isEmpty ? '任务状态' : _task.title),
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : () => _refreshTask(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshTask(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _StatusCard(task: _task, progressValue: progressValue),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            if (_task.isStartable) ...[
              const SizedBox(height: 12),
              _TrainingSettingsCard(
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
            ],
            if (_task.canDebugMasking && !_task.needsMaskInteraction) ...[
              const SizedBox(height: 12),
              _ActionCard(
                title: '复用 COLMAP 结果调试 Mask',
                subtitle: '跳回首帧标注页，重新点选主体和背景，不再重跑预处理。',
                actionLabel: _isStartingMaskDebug ? '进入中...' : '开始调试',
                onPressed: _isStartingMaskDebug ? null : _startMaskDebug,
                foreground: AppColors.mint,
              ),
            ],
            if (_task.needsMaskInteraction) ...[
              const SizedBox(height: 12),
              _MaskPromptCard(
                task: _task,
                manifest: _maskManifest,
                currentImageUrl: _currentMaskImageUrl(),
                points: _points,
                negativeMode: _negativeMode,
                selectedFrameIndex: _selectedFrameIndex,
                showPreview: _showPreview,
                isLoadingManifest: _isLoadingMaskManifest,
                isGeneratingPreview: _isGeneratingMaskPreview,
                isConfirming: _isConfirmingMaskPreview,
                onTapImage: _addMaskPoint,
                onNegativeModeChanged: (value) {
                  setState(() {
                    _negativeMode = value;
                  });
                },
                onShowPreviewChanged: (value) {
                  setState(() {
                    _showPreview = value;
                  });
                },
                onFrameChanged: (value) {
                  setState(() {
                    _selectedFrameIndex = value;
                  });
                },
                onUndo: _points.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _points.removeLast();
                        });
                      },
                onClear: _points.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _points.clear();
                        });
                      },
                onPreview: _previewMaskPrompts,
                onConfirm: _confirmMaskPreview,
                showPointOverlay: _showPointOverlay(),
              ),
            ],
            if (_task.isPipelineActive || _task.needsMaskInteraction) ...[
              const SizedBox(height: 12),
              _ActionCard(
                title: '停止当前流程',
                subtitle: '如果参数不合适，可以终止当前任务，再重新启动训练。',
                actionLabel: _isCancelling ? '停止中...' : '终止任务',
                onPressed: _isCancelling ? null : _cancelPipeline,
                foreground: AppColors.coral,
              ),
            ],
            if (_task.canOpenViewer) ...[
              const SizedBox(height: 12),
              _ActionCard(
                title: '打开 3D Viewer',
                subtitle: '查看当前模型效果，验证导出结果和 Viewer 可访问性。',
                actionLabel: '进入 Viewer',
                onPressed: _openViewer,
                foreground: AppColors.ocean,
              ),
            ],
            if (_task.logTail.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LogsCard(logTail: _task.logTail),
            ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title.isEmpty ? task.taskId : task.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '任务 ID: ${task.taskId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(task.statusLabel)),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 10),
            Text('当前进度 ${task.progress}%'),
            if (task.statusMessage != null &&
                task.statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.statusMessage!),
            ],
            if (task.trainStep != null && task.trainTotalSteps != null) ...[
              const SizedBox(height: 8),
              Text('训练步数 ${task.trainStep} / ${task.trainTotalSteps}'),
            ],
            if (task.trainEta != null && task.trainEta!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('预计剩余 ${task.trainEta}'),
            ],
            if (task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.coral),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrainingSettingsCard extends StatelessWidget {
  const _TrainingSettingsCard({
    required this.selectedQualityProfile,
    required this.selectedTrainMaxSteps,
    required this.objectMasking,
    required this.isStarting,
    required this.onQualityProfileChanged,
    required this.onTrainMaxStepsChanged,
    required this.onStart,
    this.onObjectMaskingChanged,
  });

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('训练参数', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedQualityProfile,
              decoration: const InputDecoration(labelText: '质量档位'),
              items: const [
                DropdownMenuItem(value: 'fast', child: Text('Fast')),
                DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                DropdownMenuItem(value: 'quality', child: Text('Quality')),
                DropdownMenuItem(value: 'raw', child: Text('Raw')),
              ],
              onChanged: isStarting
                  ? null
                  : (value) {
                      if (value != null) {
                        onQualityProfileChanged(value);
                      }
                    },
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
                onSelectionChanged: isStarting
                    ? null
                    : (values) {
                        if (values.isNotEmpty) {
                          onTrainMaxStepsChanged(values.first);
                        }
                      },
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: objectMasking,
              onChanged: isStarting ? null : onObjectMaskingChanged,
              title: const Text('Object Masking'),
              subtitle: const Text('在 COLMAP 完成后暂停，进入首帧标注和全帧预览确认。'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isStarting ? null : onStart,
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    required this.foreground,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: foreground.withValues(alpha: 0.14),
                foregroundColor: foreground,
              ),
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaskPromptCard extends StatelessWidget {
  const _MaskPromptCard({
    required this.task,
    required this.manifest,
    required this.currentImageUrl,
    required this.points,
    required this.negativeMode,
    required this.selectedFrameIndex,
    required this.showPreview,
    required this.isLoadingManifest,
    required this.isGeneratingPreview,
    required this.isConfirming,
    required this.showPointOverlay,
    required this.onTapImage,
    required this.onNegativeModeChanged,
    required this.onShowPreviewChanged,
    required this.onFrameChanged,
    required this.onUndo,
    required this.onClear,
    required this.onPreview,
    required this.onConfirm,
  });

  final ReconstructionTask task;
  final MaskPreviewManifest? manifest;
  final String? currentImageUrl;
  final List<MaskPromptPoint> points;
  final bool negativeMode;
  final int selectedFrameIndex;
  final bool showPreview;
  final bool isLoadingManifest;
  final bool isGeneratingPreview;
  final bool isConfirming;
  final bool showPointOverlay;
  final void Function(TapDownDetails details, BoxConstraints constraints)
  onTapImage;
  final ValueChanged<bool> onNegativeModeChanged;
  final ValueChanged<bool> onShowPreviewChanged;
  final ValueChanged<int> onFrameChanged;
  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final VoidCallback onPreview;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final frameCount = manifest?.frames.length ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mask 标注与确认', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              task.isAwaitingMaskConfirmation
                  ? '检查自动生成的全帧预览，如果轮廓合适就确认继续训练。'
                  : '在首帧上点选主体和背景，然后生成全帧 Mask 预览。',
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: (task.maskPromptFrameWidth != null &&
                          task.maskPromptFrameHeight != null &&
                          task.maskPromptFrameHeight! > 0)
                  ? task.maskPromptFrameWidth! / task.maskPromptFrameHeight!
                  : 4 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: currentImageUrl == null
                    ? const Center(child: Text('等待首帧预览图'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onTapDown: (details) =>
                                onTapImage(details, constraints),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  currentImageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(child: Text('预览图加载失败')),
                                ),
                                if (showPointOverlay)
                                  for (final point in points)
                                    Positioned(
                                      left: point.x * constraints.maxWidth - 8,
                                      top: point.y * constraints.maxHeight - 8,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: point.label == 1
                                              ? AppColors.mint
                                              : AppColors.coral,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                if (isLoadingManifest)
                                  const Align(
                                    alignment: Alignment.topCenter,
                                    child: LinearProgressIndicator(),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (frameCount > 0) ...[
              Text('预览帧 ${selectedFrameIndex + 1} / $frameCount'),
              Slider(
                value: selectedFrameIndex.toDouble(),
                min: 0,
                max: (frameCount - 1).toDouble(),
                divisions: frameCount > 1 ? frameCount - 1 : 1,
                onChanged: (value) => onFrameChanged(value.round()),
              ),
              SwitchListTile(
                value: showPreview,
                onChanged: onShowPreviewChanged,
                contentPadding: EdgeInsets.zero,
                title: const Text('显示分割预览'),
              ),
            ],
            SwitchListTile(
              value: negativeMode,
              onChanged: onNegativeModeChanged,
              contentPadding: EdgeInsets.zero,
              title: const Text('负样本模式'),
              subtitle: const Text('关闭时点主体，开启时点背景或不应保留的区域。'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('撤销'),
                ),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: isGeneratingPreview ? null : onPreview,
                  icon: isGeneratingPreview
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: Text(isGeneratingPreview ? '生成中...' : '生成预览'),
                ),
                FilledButton.tonalIcon(
                  onPressed: task.isAwaitingMaskConfirmation && !isConfirming
                      ? onConfirm
                      : null,
                  icon: isConfirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(isConfirming ? '确认中...' : '确认并继续'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.logTail});

  final List<String> logTail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实时日志', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(
              logTail.join('\n'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.45,
                fontFamily: 'Consolas',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

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
