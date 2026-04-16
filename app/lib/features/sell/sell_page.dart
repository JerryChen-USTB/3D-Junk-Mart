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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
        children: [
          EditorialScreenHeader(
            title: '发布 3D 商品',
            onBack: onGoHome,
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
                  '拍一段视频，\n发布 3D 商品。',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  '拍摄商品环绕视频，自动生成 3D 展示模型，发布到市场。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    EditorialPill(label: '智能建模', filled: true),
                    EditorialPill(label: '背景去除'),
                    EditorialPill(label: '展示校准'),
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
                  child: const Text('开始创建 3D 商品'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          EditorialActionCard(
            title: '任务管理',
            subtitle:
                '查看建模进度、继续未完成的任务、或查看已发布的商品',
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
        ],
      ),
    );
  }
}
