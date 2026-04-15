import 'package:flutter/material.dart';

import '../models/reconstruction_task.dart';
import '../services/api_client.dart';
import 'developer_hub_page.dart';
import 'product_detail_page.dart';
import 'seller_publish_flow_page.dart';
import 'viewer_page.dart';

class MarketplaceShellPage extends StatefulWidget {
  const MarketplaceShellPage({super.key});

  static const defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  @override
  State<MarketplaceShellPage> createState() => _MarketplaceShellPageState();
}

class _MarketplaceShellPageState extends State<MarketplaceShellPage> {
  int _selectedIndex = 0;
  int _reloadToken = 0;
  String _apiBaseUrl = MarketplaceShellPage.defaultApiBaseUrl;

  Future<void> _openPublishFlow({String? taskId}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerPublishFlowPage(
          apiBaseUrl: _apiBaseUrl,
          initialTaskId: taskId,
        ),
      ),
    );
    setState(() {
      _reloadToken++;
    });
  }

  void _updateApiBaseUrl(String value) {
    setState(() {
      _apiBaseUrl = value;
      _reloadToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _selectedIndex == 0
        ? _HomeTab(key: ValueKey('home_$_reloadToken'), apiBaseUrl: _apiBaseUrl)
        : _MyTab(
            key: ValueKey('my_$_reloadToken'),
            apiBaseUrl: _apiBaseUrl,
            onApiBaseUrlChanged: _updateApiBaseUrl,
            onOpenDraft: _openPublishFlow,
          );

    return Scaffold(
      body: SafeArea(child: body),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _openPublishFlow,
        child: const Icon(Icons.add_box_outlined),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: _BottomTabButton(
                  label: '首页',
                  icon: Icons.home_outlined,
                  selected: _selectedIndex == 0,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),
              ),
              const SizedBox(width: 72),
              Expanded(
                child: _BottomTabButton(
                  label: '我的',
                  icon: Icons.person_outline,
                  selected: _selectedIndex == 1,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({super.key, required this.apiBaseUrl});

  final String apiBaseUrl;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late ApiClient _client;
  bool _isLoading = true;
  String? _errorMessage;
  List<ReconstructionTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _client = ApiClient(widget.apiBaseUrl);
    _loadTasks();
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _client = ApiClient(widget.apiBaseUrl);
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await _client.fetchTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks.where((task) => task.isPublished).toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '加载首页商品失败：$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openProduct(ReconstructionTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProductDetailPage(apiBaseUrl: widget.apiBaseUrl, initialTask: task),
      ),
    );
    await _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.secondaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '3D 闲置好物',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  '这里模拟买家首页。已发布的 3D 商品会自动出现在列表中，点击后可以进入带内嵌 viewer 的商品详情页。',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    Chip(label: Text('3D 旋转查看')),
                    Chip(label: Text('自动环绕动画')),
                    Chip(label: Text('Flutter + WebView')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricCard(label: '已发布商品', value: '${_tasks.length}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: '当前后端',
                  value: widget.apiBaseUrl.replaceFirst('http://', ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '3D 商品列表',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (_tasks.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '还没有已发布的 3D 商品。',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('先点击底部中央按钮走完发布流程，确认发布后，这里会立即出现新的商品卡片。'),
                  ],
                ),
              ),
            )
          else
            ..._tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProductListCard(
                  task: task,
                  onTap: () => _openProduct(task),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyTab extends StatefulWidget {
  const _MyTab({
    super.key,
    required this.apiBaseUrl,
    required this.onApiBaseUrlChanged,
    required this.onOpenDraft,
  });

  final String apiBaseUrl;
  final ValueChanged<String> onApiBaseUrlChanged;
  final Future<void> Function({String? taskId}) onOpenDraft;

  @override
  State<_MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<_MyTab> {
  late ApiClient _client;
  late TextEditingController _apiController;
  bool _isLoading = true;
  bool _isDeleting = false;
  String? _errorMessage;
  List<ReconstructionTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _client = ApiClient(widget.apiBaseUrl);
    _apiController = TextEditingController(text: widget.apiBaseUrl);
    _loadTasks();
  }

  @override
  void didUpdateWidget(covariant _MyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _client = ApiClient(widget.apiBaseUrl);
      _apiController.text = widget.apiBaseUrl;
      _loadTasks();
    }
  }

  @override
  void dispose() {
    _apiController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await _client.fetchTasks();
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
        _errorMessage = '加载商品管理列表失败：$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openDeveloperHub() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeveloperHubPage(apiBaseUrl: widget.apiBaseUrl),
      ),
    );
    await _loadTasks();
  }

  Future<void> _deleteTask(ReconstructionTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除商品'),
        content: Text('确认删除“${task.title}”吗？这会移除任务记录和本地模型文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await _client.deleteTask(task.taskId);
      if (!mounted) {
        return;
      }
      await _loadTasks();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '删除商品失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  int get _publishedCount => _tasks.where((task) => task.isPublished).length;
  int get _draftCount => _tasks.where((task) => !task.isPublished).length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '我的',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('这里集中展示卖家的 3D 商品管理、后端切换和开发者入口。'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricCard(label: '已发布', value: '$_publishedCount'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(label: '草稿 / 处理中', value: '$_draftCount'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '后端地址',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiController,
                    decoration: const InputDecoration(
                      labelText: 'API Base URL',
                      helperText: '模拟器默认 http://10.0.2.2:8000；真机请改成电脑局域网 IP',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        widget.onApiBaseUrlChanged(_apiController.text.trim()),
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: const Text('应用后端地址'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '开发者入口',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '保留当前原始 MVP 调试方式，便于继续调试上传、任务状态、Masking 和 viewer 缓存。',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openDeveloperHub,
                    icon: const Icon(Icons.developer_mode_outlined),
                    label: const Text('打开开发者入口'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '3D 商品管理',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (_tasks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('还没有任何商品草稿，点击底部中央按钮开始发布。'),
              ),
            )
          else
            ..._tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SellerTaskCard(
                  task: task,
                  isDeleting: _isDeleting,
                  onOpenDraft: () => widget.onOpenDraft(taskId: task.taskId),
                  onOpenBuyerPage: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailPage(
                          apiBaseUrl: widget.apiBaseUrl,
                          initialTask: task,
                        ),
                      ),
                    );
                    await _loadTasks();
                  },
                  onEditViewer: task.canOpenViewer
                      ? () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ViewerPage(
                                viewerUrl: task.viewerUrl!,
                                taskTitle: '继续编辑：${task.title}',
                              ),
                            ),
                          );
                        }
                      : null,
                  onDelete: task.isPipelineActive || task.needsMaskInteraction
                      ? null
                      : () => _deleteTask(task),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? Theme.of(context).colorScheme.primary : null,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ProductListCard extends StatelessWidget {
  const _ProductListCard({required this.task, required this.onTap});

  final ReconstructionTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Chip(label: Text('3D')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '¥ ${task.price.isEmpty ? '--' : task.price}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                task.description.isEmpty ? '卖家还没有补充商品描述。' : task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('内嵌 viewer')),
                  Chip(label: Text('自动展示动画')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerTaskCard extends StatelessWidget {
  const _SellerTaskCard({
    required this.task,
    required this.isDeleting,
    required this.onOpenDraft,
    required this.onOpenBuyerPage,
    required this.onDelete,
    this.onEditViewer,
  });

  final ReconstructionTask task;
  final bool isDeleting;
  final VoidCallback onOpenDraft;
  final VoidCallback onOpenBuyerPage;
  final VoidCallback? onEditViewer;
  final VoidCallback? onDelete;

  String _statusText() {
    if (task.isPublished) {
      return '已发布';
    }
    switch (task.status) {
      case 'uploaded':
        return '待配置';
      case 'queued':
        return '等待启动';
      case 'preprocessing':
        return '预处理中';
      case 'awaiting_mask_prompt':
      case 'awaiting_mask_confirmation':
        return '等待 Mask 交互';
      case 'training':
        return '训练中';
      case 'exporting':
        return '导出中';
      case 'ready':
        return '待发布';
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
                      Text('¥ ${task.price.isEmpty ? '--' : task.price}'),
                    ],
                  ),
                ),
                Chip(label: Text(_statusText())),
              ],
            ),
            if (task.statusMessage != null &&
                task.statusMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.statusMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: onOpenDraft,
                  child: Text(task.isPublished ? '重新进入发布流' : '继续发布'),
                ),
                if (onEditViewer != null)
                  OutlinedButton.icon(
                    onPressed: onEditViewer,
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: const Text('进入 viewer 编辑'),
                  ),
                if (task.isPublished)
                  OutlinedButton.icon(
                    onPressed: onOpenBuyerPage,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('查看买家页'),
                  ),
                OutlinedButton.icon(
                  onPressed: isDeleting ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(isDeleting ? '删除中...' : '删除商品'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
