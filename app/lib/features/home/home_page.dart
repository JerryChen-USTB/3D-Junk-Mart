import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../theme/app_colors.dart';
import '../listings/listing_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onGoSearch,
    required this.onOpenListing,
  });

  final ListingsRepository repository;
  final VoidCallback onGoSearch;
  final ValueChanged<String> onOpenListing;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<ListingSummary>> _listingsFuture;
  final ListingPreviewController _previewController = ListingPreviewController();

  @override
  void initState() {
    super.initState();
    _listingsFuture = widget.repository.fetchListings(limit: 12);
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchListings(limit: 12);
    _previewController.clear();
    setState(() {
      _listingsFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ListingSummary>>(
          future: _listingsFuture,
          builder: (context, snapshot) {
            final listings = snapshot.data ?? const <ListingSummary>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 128),
              children: [
                _HomeHeader(onGoSearch: widget.onGoSearch),
                const SizedBox(height: 16),
                const ListingHeroBanner(
                  title: '3D 二手商城',
                  subtitle: '浏览二手好物，支持 3D 展示，所见即所得。',
                  badge: 'Junk Mart',
                ),
                const SizedBox(height: 18),
                Text('推荐商品', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    listings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError && listings.isEmpty)
                  _ErrorPanel(onRetry: _refresh)
                else if (listings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 36,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '还没有商品',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '去“发布”页创建你的第一个 3D 商品吧。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  _ListingGrid(
                    listings: listings,
                    onOpenListing: widget.onOpenListing,
                    previewController: _previewController,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onGoSearch});

  final VoidCallback onGoSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 21,
          backgroundColor: AppColors.surface,
          child: Icon(Icons.person_rounded, color: AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onGoSearch,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '搜索 3D 商品',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.view_in_ar_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 21,
          backgroundColor: AppColors.surface,
          child: Icon(
            Icons.notifications_none_rounded,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ListingGrid extends StatelessWidget {
  const _ListingGrid({
    required this.listings,
    required this.onOpenListing,
    required this.previewController,
  });

  final List<ListingSummary> listings;
  final ValueChanged<String> onOpenListing;
  final ListingPreviewController previewController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = adaptiveGridCardWidth(constraints.maxWidth);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List<Widget>.generate(listings.length, (index) {
            final listing = listings[index];
            return SizedBox(
              width: cardWidth,
              child: ListingCard(
                listing: listing,
                tall: index.isOdd,
                previewController: previewController,
                onTap: () => onOpenListing(listing.id),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.coral),
          const SizedBox(height: 10),
          Text('商品加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '市场列表暂时不可用，请直接重试。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              onRetry();
            },
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}
