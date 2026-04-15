import 'package:flutter/material.dart';

import '../models/reconstruction_task.dart';
import '../services/api_client.dart';
import 'viewer_page.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.apiBaseUrl,
    required this.initialTask,
  });

  final String apiBaseUrl;
  final ReconstructionTask initialTask;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late final ApiClient _client;
  late ReconstructionTask _task;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(widget.apiBaseUrl);
    _task = widget.initialTask;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });

    try {
      final latest = await _client.fetchTask(_task.taskId);
      if (!mounted) {
        return;
      }
      setState(() {
        _task = latest;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '刷新商品详情失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_task.title.isEmpty ? '3D 商品详情' : _task.title),
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新商品',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _task.canOpenViewer
                  ? ViewerFrame(
                      viewerUrl: _task.viewerUrl!,
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
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '3D 模型暂不可用，请稍后再试。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  Card(
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
                                  _task.title,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  _task.isPublished ? '3D 在售' : '草稿商品',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '¥ ${_task.price.isEmpty ? '--' : _task.price}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _task.description.isEmpty
                                ? '卖家还没有补充商品描述。'
                                : _task.description,
                          ),
                          const SizedBox(height: 16),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('3D 实景查看')),
                              Chip(label: Text('环绕动画预览')),
                              Chip(label: Text('移动端 WebView')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '查看说明',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('1. 页面打开后会自动播放商品的 360° 展示动画。'),
                          const SizedBox(height: 6),
                          const Text('2. 你可以像拖动视频封面一样拖动画面，自由查看细节。'),
                          const SizedBox(height: 6),
                          const Text('3. 这里只保留“查看视角”的交互，不提供坐标或相机编辑能力。'),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
