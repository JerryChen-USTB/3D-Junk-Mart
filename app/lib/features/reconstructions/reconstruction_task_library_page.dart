import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/reconstructions/reconstruction_models.dart';
import '../../core/reconstructions/reconstructions_repository.dart';
import '../viewer/viewer_page.dart';
import 'reconstruction_publish_flow_page.dart';
import 'reconstruction_task_status_page.dart';

enum _TaskFilter {
  all('全部', null),
  active(
    '进行中',
    'uploaded,queued,preprocessing,awaiting_mask_prompt,awaiting_mask_confirmation,masking,training,exporting',
  ),
  ready('可发布', 'ready'),
  published('已发布', 'ready'),
  failed('失败', 'failed,cancelled');

  const _TaskFilter(this.label, this.statusQuery);

  final String label;
  final String? statusQuery;
}

class ReconstructionTaskLibraryPage extends StatefulWidget {
  const ReconstructionTaskLibraryPage({
    super.key,
    required this.apiClient,
    this.accessToken,
    this.onMarketplaceChanged,
    this.onOpenListing,
  });

  final ApiClient apiClient;
  final String? accessToken;
  final VoidCallback? onMarketplaceChanged;
  final ValueChanged<String>? onOpenListing;

  @override
  State<ReconstructionTaskLibraryPage> createState() =>
      _ReconstructionTaskLibraryPageState();
}

class _ReconstructionTaskLibraryPageState
    extends State<ReconstructionTaskLibraryPage> {
  late final ReconstructionsRepository _repository;
  _TaskFilter _filter = _TaskFilter.all;
  bool _isLoading = true;
  String? _errorMessage;
  List<ReconstructionTask> _tasks = const <ReconstructionTask>[];

  @override
  void initState() {
    super.initState();
    _repository = ReconstructionsRepository(widget.apiClient);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final tasks = await _repository.fetchTasks(
        status: _filter.statusQuery,
        bearerToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = _filter == _TaskFilter.published
            ? tasks.where((item) => item.isPublished).toList(growable: false)
            : tasks;
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

  Future<void> _openFlow(ReconstructionTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReconstructionPublishFlowPage(
          apiClient: widget.apiClient,
          accessToken: widget.accessToken,
          initialTaskId: task.taskId,
          onMarketplaceChanged: widget.onMarketplaceChanged,
          onOpenListing: widget.onOpenListing,
        ),
      ),
    );
    await _loadTasks();
  }

  Future<void> _openStatus(ReconstructionTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReconstructionTaskStatusPage(
          repository: _repository,
          initialTask: task,
          accessToken: widget.accessToken,
        ),
      ),
    );
    await _loadTasks();
  }

  Future<void> _openViewer(ReconstructionTask task) async {
    if (!task.canOpenViewer || task.viewerUrl == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewerPage(
          viewerUrl: task.viewerUrl!,
          title: task.title.isEmpty ? '3D 模型' : task.title,
        ),
      ),
    );
    await _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3DGS 任务库'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadTasks,
            icon: const Icon(Icons.refresh_rounded),
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
                  children: _TaskFilter.values
                      .map((filter) {
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
                      })
                      .toList(growable: false),
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
        children: [Text(_errorMessage!)],
      );
    }
    if (_tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [Text('当前筛选条件下没有任务。')],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _tasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = _tasks[index];
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
                const SizedBox(height: 8),
                Text(task.statusMessage ?? '当前进度 ${task.progress}%'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _openFlow(task),
                      child: const Text('继续工作流'),
                    ),
                    OutlinedButton(
                      onPressed: () => _openStatus(task),
                      child: const Text('任务状态'),
                    ),
                    if (task.canOpenViewer)
                      OutlinedButton(
                        onPressed: () => _openViewer(task),
                        child: const Text('打开 Viewer'),
                      ),
                    if (task.hasPublishedListing &&
                        widget.onOpenListing != null)
                      OutlinedButton(
                        onPressed: () => widget.onOpenListing!(task.listingId!),
                        child: const Text('打开 Listing'),
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
