import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../viewer/viewer_page.dart';

class ListingDetailPage extends StatefulWidget {
  const ListingDetailPage({
    super.key,
    required this.repository,
    required this.listingId,
    required this.onOpenChat,
    required this.onOpenOrder,
    required this.onOpenReview,
  });

  final ListingsRepository repository;
  final String listingId;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenOrder;
  final VoidCallback onOpenReview;

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  late Future<ListingDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.repository.fetchListingDetail(widget.listingId);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchListingDetail(widget.listingId);
    setState(() {
      _detailFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<ListingDetail>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || snapshot.data == null) {
              return _DetailErrorState(
                onBack: () => Navigator.pop(context),
                onRetry: _refresh,
              );
            }

            final detail = snapshot.data!;

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
                children: [
                  EditorialScreenHeader(
                    title: 'Listing detail',
                    onBack: () => Navigator.pop(context),
                    trailing: EditorialRoundIconButton(
                      icon: Icons.share_rounded,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailHero(detail: detail),
                  const SizedBox(height: 16),
                  _PriceSummary(detail: detail),
                  const SizedBox(height: 16),
                  _SellerSummary(detail: detail, onOpenChat: widget.onOpenChat),
                  if (detail.specs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SpecsSection(specs: detail.specs),
                  ],
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Description',
                    child: Text(
                      detail.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: '3D preview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.preview3d.isReady
                              ? 'The model is ready and can be explored directly inside the product page.'
                              : detail.preview3d.statusMessage ??
                                  'The 3D model is still preparing, so the app shows the cover and status first.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final badge in detail.preview3d.placeholderBadges)
                              EditorialPill(
                                label: badge,
                                backgroundColor: AppColors.surfaceSoft,
                                foregroundColor: AppColors.text,
                              ),
                            EditorialPill(
                              label: detail.preview3d.previewStatus,
                              backgroundColor: const Color(0xFFE0F7F7),
                              foregroundColor: AppColors.mint,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 24,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                if (compact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: widget.onOpenOrder,
                        child: const Text('Buy now'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.onOpenChat,
                              child: const Text('Contact'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.onOpenReview,
                              child: const Text('Reviews'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onOpenChat,
                        child: const Text('Contact'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onOpenReview,
                        child: const Text('Reviews'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.onOpenOrder,
                        child: const Text('Buy now'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.detail});

  final ListingDetail detail;

  @override
  Widget build(BuildContext context) {
    final viewerUrl = detail.preview3d.effectiveViewerUrl;

    return Container(
      height: 270,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: viewerUrl != null
          ? Stack(
              children: [
                ViewerFrame(
                  viewerUrl: viewerUrl,
                  showLoadingBar: true,
                  additionalQueryParameters: const <String, String>{
                    'readonly': '1',
                    'embed': '1',
                    'autoplay': '1',
                    'minimal': '1',
                  },
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: EditorialPill(
                    label: detail.preview3d.isReady ? '3D ready' : '3D preview',
                    backgroundColor: Colors.black.withValues(alpha: 0.52),
                    foregroundColor: Colors.white,
                    icon: Icons.view_in_ar_rounded,
                  ),
                ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF4E5C4B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                if (detail.preview3d.coverImageUrl != null)
                  Image.network(
                    detail.preview3d.coverImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.54),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const Center(
                  child: Icon(
                    Icons.view_in_ar_rounded,
                    color: Colors.white,
                    size: 68,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.preview3d.placeholderTitle,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail.preview3d.placeholderSubtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({required this.detail});

  final ListingDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                detail.summary.priceLabel,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.coral,
                    ),
              ),
              if (detail.summary.originalPriceLabel != 'Negotiable')
                Text(
                  detail.summary.originalPriceLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                ),
              if (detail.summary.has3dBadge)
                EditorialPill(
                  label: '3D enabled',
                  backgroundColor: const Color(0xFFE4F5EE),
                  foregroundColor: AppColors.mint,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            detail.summary.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (detail.summary.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail.summary.subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _SellerSummary extends StatelessWidget {
  const _SellerSummary({required this.detail, required this.onOpenChat});

  final ListingDetail detail;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.person_rounded, color: AppColors.textMuted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      detail.summary.sellerName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (detail.sellerScore != null)
                      EditorialPill(
                        label: 'Score ${detail.sellerScore}',
                        backgroundColor: const Color(0xFFE0F7F7),
                        foregroundColor: AppColors.mint,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  detail.sellerBio,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        detail.sellerLocation,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: onOpenChat, child: const Text('Contact')),
        ],
      ),
    );
  }
}

class _SpecsSection extends StatelessWidget {
  const _SpecsSection({required this.specs});

  final List<ListingSpec> specs;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: specs.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final spec = specs[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(spec.label, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Text(
                spec.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({required this.onBack, required this.onRetry});

  final VoidCallback onBack;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.coral),
            const SizedBox(height: 12),
            Text(
              'Failed to load listing detail',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Please retry after checking the backend response.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: onBack, child: const Text('Back')),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
