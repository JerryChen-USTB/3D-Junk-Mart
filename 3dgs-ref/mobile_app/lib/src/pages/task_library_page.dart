import 'package:flutter/material.dart';

import '../models/reconstruction_task.dart';
import '../services/api_client.dart';
import 'task_status_page.dart';
import 'viewer_page.dart';

enum _TaskFilter {
  all('全部任务', null),
  ready('已生成', 'ready'),
  active('进行中', 'uploaded,queued,preprocessing,training,exporting'),
  failed('失败', 'failed');

  const _TaskFilter(this.label, this.statusQuery);

  final String label;
  final String? statusQuery;
}

class TaskLibraryPage extends StatefulWidget {
  const TaskLibraryPage({super.key, required this.client});

  final ApiClient client;

  @override
  State<TaskLibraryPage> createState() => _TaskLibraryPageState();
}

class _TaskLibraryPageState extends State<TaskLibraryPage> {
  _TaskFilter _filter = _TaskFilter.ready;
  bool _isLoading = true;
  String? _errorMessage;
  String? _openingTaskId;
  String? _debuggingTaskId;
  List<ReconstructionTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await widget.client.fetchTasks(status: _filter.statusQuery);
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载任务列表失败：$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openTask(ReconstructionTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskStatusPage(client: widget.client, initialTask: task),
      ),
    );
    await _loadTasks();
  }

  Future<void> _openReadyTask(ReconstructionTask task) async {
    setState(() {
      _openingTaskId = task.taskId;
      _errorMessage = null;
    });

    try {
      final latestTask = await widget.client.fetchTask(task.taskId);
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = _tasks
            .map((item) => item.taskId == latestTask.taskId ? latestTask : item)
            .toList();
      });

      if (!latestTask.isReady || latestTask.viewerUrl == null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                TaskStatusPage(client: widget.client, initialTask: latestTask),
          ),
        );
        if (mounted) {
          await _loadTasks();
        }
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

      if (mounted) {
        await _loadTasks();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '打开模型前刷新任务失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _openingTaskId = null;
        });
      }
    }
  }

  Future<void> _startMaskDebug(ReconstructionTask task) async {
    setState(() {
      _debuggingTaskId = task.taskId;
      _errorMessage = null;
    });

    try {
      final latestTask = await widget.client.startMaskDebug(task.taskId);
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = _tasks
            .map((item) => item.taskId == latestTask.taskId ? latestTask : item)
            .toList();
      });

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TaskStatusPage(client: widget.client, initialTask: latestTask),
        ),
      );

      if (mounted) {
        await _loadTasks();
      }
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
          _debuggingTaskId = null;
        });
      }
    }
  }

  Future<void> _openModelCache() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerPage(
          viewerUrl: widget.client.viewerCacheUrl,
          taskTitle: '模型缓存管理',
        ),
      ),
    );
  }

  String _formatTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }

    final local = parsed.toLocal();
    String two(int item) => item.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _statusText(ReconstructionTask task) {
    switch (task.status) {
      case 'uploaded':
        return '已创建';
      case 'queued':
        return '等待启动';
      case 'preprocessing':
        return '预处理中';
      case 'training':
        return '训练中';
      case 'exporting':
        return '导出中';
      case 'ready':
        return '已生成';
      case 'failed':
        return '失败';
      case 'cancelled':
        return '已终止';
      default:
        return task.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('已生成模型'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadTasks,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新列表',
          ),
          IconButton(
            onPressed: _openModelCache,
            icon: const Icon(Icons.storage_outlined),
            tooltip: '管理模型缓存',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _TaskFilter.values.map((filter) {
                    return ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (selected) {
                        if (!selected) {
                          return;
                        }
                        setState(() {
                          _filter = filter;
                        });
                        _loadTasks();
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadTasks,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
    }

    if (_tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [Text('当前筛选条件下还没有任务。先去首页创建重建任务，或切换到“全部任务”查看历史记录。')],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _tasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = _tasks[index];
        final canViewModel = task.isReady && task.viewerUrl != null;
        final isOpening = _openingTaskId == task.taskId;
        final isDebugging = _debuggingTaskId == task.taskId;

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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '任务号：${task.taskId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '更新时间：${_formatTime(task.updatedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Chip(label: Text(_statusText(task))),
                  ],
                ),
                const SizedBox(height: 12),
                Text('当前进度：${task.progress}%'),
                if (task.statusMessage != null &&
                    task.statusMessage!.isNotEmpty) ...[
                  const SizedBox(height: 6),
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: isOpening ? null : () => _openTask(task),
                      child: Text(isOpening ? '打开中...' : '查看状态'),
                    ),
                    if (canViewModel)
                      FilledButton.tonalIcon(
                        onPressed: isOpening
                            ? null
                            : () => _openReadyTask(task),
                        icon: const Icon(Icons.view_in_ar_outlined),
                        label: const Text('查看模型'),
                      ),
                    if (task.canDebugMasking)
                      OutlinedButton.icon(
                        onPressed: isDebugging
                            ? null
                            : () => _startMaskDebug(task),
                        icon: isDebugging
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bug_report_outlined),
                        label: Text(isDebugging ? '进入中...' : 'Mask 调试'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
