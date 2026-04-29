import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
import '../listings/listing_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.session,
    required this.onGoSearch,
    required this.onOpenListing,
  });

  final ListingsRepository repository;
  final AppSession session;
  final VoidCallback onGoSearch;
  final ValueChanged<String> onOpenListing;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<_HomeData> _future;
  final ListingPreviewController _previewController = ListingPreviewController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<_HomeData> _load() async {
    final bearerToken =
        widget.session.isGuest ? null : widget.session.accessToken;
    final page = await widget.repository.fetchHomePage(bearerToken: bearerToken);
    final resources =
        (page['resources'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return _HomeData(
      listings: _parseListings(resources['listings']),
      featured3d: _parseListings(resources['featured_3d']),
    );
  }

  List<ListingSummary> _parseListings(Object? raw) {
    if (raw is! List) {
      return const <ListingSummary>[];
    }
    return raw
        .whereType<Map>()
        .map(
          (item) => ListingSummary.fromJson(
            item.cast<String, dynamic>(),
            widget.repository.apiRoot,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final future = _load();
    _previewController.clear();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (snapshot.connectionState == ConnectionState.waiting &&
                data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || data == null) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 80),
                  const CommerceEmptyState(
                    icon: Icons.storefront_outlined,
                    title: '首页加载失败',
                    subtitle: '市场数据暂时不可用，点击重试重新拉取。',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _refresh, child: const Text('重试')),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 128),
              children: [
                _HomeHeader(onGoSearch: widget.onGoSearch),
                const SizedBox(height: 16),
                const _HomePosterCarousel(),
                if (data.featured3d.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                    title: '3D 专区',
                    actionLabel: '查看全部',
                    onTap: widget.onGoSearch,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 286,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final listing = data.featured3d[index];
                        return SizedBox(
                          width: 220,
                          child: _FeaturedListingCard(
                            listing: listing,
                            onTap: () => widget.onOpenListing(listing.id),
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemCount: data.featured3d.length.clamp(0, 8),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionTitle(title: '推荐商品'),
                const SizedBox(height: 12),
                if (data.listings.isEmpty)
                  const CommerceEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: '还没有在售商品',
                    subtitle: '去发布页创建第一件带 3D 预览的二手商品。',
                  )
                else
                  _ListingGrid(
                    listings: data.listings,
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

class _HomeData {
  const _HomeData({
    required this.listings,
    required this.featured3d,
  });

  final List<ListingSummary> listings;
  final List<ListingSummary> featured3d;
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
          child: Icon(Icons.storefront_rounded, color: AppColors.textMuted),
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
                      '搜索商品、卖家、3D 专区',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.tune_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomePosterCarousel extends StatefulWidget {
  const _HomePosterCarousel();

  @override
  State<_HomePosterCarousel> createState() => _HomePosterCarouselState();
}

class _HomePosterCarouselState extends State<_HomePosterCarousel> {
  static const _posters = <String>[
    'assets/home_posters/poster_1.png',
    'assets/home_posters/poster_2.png',
    'assets/home_posters/poster_3.png',
  ];

  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final next = (_index + 1) % _posters.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1672 / 941,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _posters.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                return Image.asset(
                  _posters[index],
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_posters.length, (index) {
                  final active = index == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: active ? 0.92 : 0.52,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.actionLabel,
    this.onTap,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        if ((actionLabel ?? '').isNotEmpty)
          TextButton(onPressed: onTap, child: Text(actionLabel!)),
      ],
    );
  }
}

class _FeaturedListingCard extends StatelessWidget {
  const _FeaturedListingCard({
    required this.listing,
    required this.onTap,
  });

  final ListingSummary listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                child: SizedBox(
                  height: 166,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSoft,
                          image: listing.coverImageUrl == null
                              ? null
                              : DecorationImage(
                                  image: NetworkImage(listing.coverImageUrl!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: listing.coverImageUrl == null
                            ? const Center(
                                child: Icon(
                                  Icons.inventory_2_rounded,
                                  size: 40,
                                  color: AppColors.textMuted,
                                ),
                              )
                            : null,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Color(0x8A000000)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 12,
                        top: 12,
                        child: CommercePill(
                          label: '3D 展示',
                          backgroundColor: Color(0xD9FFFFFF),
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Text(
                          listing.location,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      listing.priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.coral,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (listing.hasKnownCondition || listing.isNegotiable) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (listing.hasKnownCondition)
                            CommercePill(
                              label: listing.conditionLabel,
                              backgroundColor: AppColors.surfaceSoft,
                              foregroundColor: AppColors.primary,
                            ),
                          if (listing.isNegotiable)
                            const CommercePill(
                              label: '可议价',
                              backgroundColor: Color(0xFFFFF3D8),
                              foregroundColor: AppColors.warning,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
