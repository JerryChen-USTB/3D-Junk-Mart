import 'package:flutter/material.dart';

import '../services/api_client.dart';
import 'publish_page.dart';
import 'task_library_page.dart';
import 'viewer_page.dart';

class DeveloperHubPage extends StatelessWidget {
  const DeveloperHubPage({super.key, required this.apiBaseUrl});

  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final client = ApiClient(apiBaseUrl);

    return Scaffold(
      appBar: AppBar(title: const Text('开发者入口')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '当前调试入口',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('后端地址：$apiBaseUrl'),
                  const SizedBox(height: 16),
                  const Text(
                    '这里保留了目前用于 3DGS 流水线联调的原始页面，方便继续按现有方式测试上传、任务状态、Mask 调试和 viewer 缓存。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PublishPage()),
              );
            },
            icon: const Icon(Icons.science_outlined),
            label: const Text('打开原始 MVP 调试页'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskLibraryPage(client: client),
                ),
              );
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('打开任务库'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ViewerPage(
                    viewerUrl: client.viewerCacheUrl,
                    taskTitle: '模型缓存管理',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.storage_outlined),
            label: const Text('打开模型缓存管理'),
          ),
        ],
      ),
    );
  }
}
