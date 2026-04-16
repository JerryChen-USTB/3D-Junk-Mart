import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../reconstructions/reconstruction_publish_flow_page.dart';
import '../reconstructions/reconstruction_task_library_page.dart';

class SellPage extends StatelessWidget {
  const SellPage({
    super.key,
    required this.apiClient,
    required this.onGoHome,
    required this.onOpenListing,
    this.accessToken,
    this.onMarketplaceChanged,
  });

  final ApiClient apiClient;
  final String? accessToken;
  final VoidCallback onGoHome;
  final ValueChanged<String> onOpenListing;
  final VoidCallback? onMarketplaceChanged;

  Uri get _serviceRoot => Uri.parse(apiClient.baseUrl).resolve('/');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
        children: [
          EditorialScreenHeader(
            title: 'Sell in 3D',
            onBack: onGoHome,
            trailing: Text(
              '3DGS',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capture once,\npublish in 3D.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  '这里接入的是完整的 3DGS 工作流：上传视频、远程训练、Mask 标注、Viewer 校准、发布到 marketplace。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    EditorialPill(label: 'Remote trainer', filled: true),
                    EditorialPill(label: 'Mask preview'),
                    EditorialPill(label: 'Viewer calibration'),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReconstructionPublishFlowPage(
                          apiClient: apiClient,
                          accessToken: accessToken,
                          onMarketplaceChanged: onMarketplaceChanged,
                          onOpenListing: onOpenListing,
                        ),
                      ),
                    );
                  },
                  child: const Text('Start 3DGS Flow'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          EditorialActionCard(
            title: 'Task Library',
            subtitle:
                'Resume a task, inspect status, reopen viewer, or jump to a published listing',
            icon: Icons.inventory_2_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReconstructionTaskLibraryPage(
                    apiClient: apiClient,
                    accessToken: accessToken,
                    onMarketplaceChanged: onMarketplaceChanged,
                    onOpenListing: onOpenListing,
                  ),
                ),
              );
            },
          ),
          EditorialActionCard(
            title: 'Backend Route',
            subtitle:
                'Flutter -> ${_serviceRoot.host}:8000/api/v1/reconstructions -> trainer_service',
            icon: Icons.route_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('当前 API Base: ${apiClient.baseUrl}')),
              );
            },
          ),
          EditorialActionCard(
            title: 'What Publish Does',
            subtitle:
                'After the task is ready, publish will also sync a real marketplace listing',
            icon: Icons.storefront_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('发布后会生成/更新 listing，并回写 listing_id 到任务。'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
