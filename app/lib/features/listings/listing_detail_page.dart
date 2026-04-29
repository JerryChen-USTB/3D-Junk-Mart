import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
import '../viewer/viewer_page.dart';

class ListingDetailPage extends StatefulWidget {
  const ListingDetailPage({
    super.key,
    required this.repository,
    required this.session,
    required this.listingId,
    required this.onOpenChat,
    required this.onOpenOrder,
    required this.onOpenReview,
  });

  final ListingsRepository repository;
  final AppSession session;
  final String listingId;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenOrder;
  final VoidCallback onOpenReview;

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  late Future<ListingDetail> _detailFuture;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _load();
  }

  Future<ListingDetail> _load() {
    return widget.repository.fetchListingDetail(
      widget.listingId,
      bearerToken: widget.session.isGuest ? null : widget.session.accessToken,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _detailFuture = future;
    });
    await future;
  }

  Future<void> _toggleFavorite(ListingDetail detail) async {
    if (widget.session.isGuest || _favoriteBusy) {
      return;
    }
    setState(() => _favoriteBusy = true);
    try {
      await widget.repository.toggleFavorite(
        listingId: detail.summary.id,
        bearerToken: widget.session.accessToken,
        isFavorited: detail.summary.isFavorited,
      );
      await _refresh();
    } finally {
      if (mounted) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ListingDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Center(
                child: FilledButton(
                  onPressed: _refresh,
                  child: const Text('重试'),
                ),
              ),
            ),
          );
        }

        final detail = snapshot.data!;
        final currentUserId = widget.session.user['id']?.toString() ?? '';
        final isOwner =
            detail.summary.sellerId.isNotEmpty &&
            detail.summary.sellerId == currentUserId;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 136),
                children: [
                  _DetailHeader(
                    isFavorited: detail.summary.isFavorited,
                    favoriteBusy: _favoriteBusy,
                    canFavorite: !isOwner && !widget.session.isGuest,
                    onBack: () => Navigator.of(context).pop(),
                    onFavorite: () => _toggleFavorite(detail),
                  ),
                  const SizedBox(height: 16),
                  _DetailHero(detail: detail),
                  const SizedBox(height: 16),
                  _PriceSummary(detail: detail),
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '交易信息',
                    child: Column(
                      children: [
                        CommerceKeyValueRow(
                          label: '商品成色',
                          value: detail.transactionInfo.conditionLabel,
                        ),
                        CommerceKeyValueRow(
                          label: '运费',
                          value: detail.transactionInfo.shippingFeeLabel,
                        ),
                        CommerceKeyValueRow(
                          label: '发货承诺',
                          value: detail.transactionInfo.shippingPromise,
                        ),
                        CommerceKeyValueRow(
                          label: '议价',
                          value:
                              detail.transactionInfo.isNegotiable ? '支持议价' : '一口价',
                        ),
                        CommerceKeyValueRow(
                          label: '收藏人数',
                          value: '${detail.transactionInfo.favoriteCount}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '瑕疵与说明',
                    child: Text(
                      detail.transactionInfo.defectNotes,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (detail.servicePromises.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CommerceCard(
                        title: '平台服务',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: detail.servicePromises
                              .map(
                                (item) => CommercePill(
                                  label: item,
                                  backgroundColor: AppColors.surfaceSoft,
                                  foregroundColor: AppColors.primary,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                  _SellerSummary(
                    detail: detail,
                    isOwner: isOwner,
                    onOpenChat: widget.onOpenChat,
                  ),
                  if (detail.specs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    CommerceCard(
                      title: '商品参数',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: detail.specs
                            .map(
                              (spec) => Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSoft,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      spec.label,
                                      style: Theme.of(context).textTheme.labelMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      spec.value,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '商品描述',
                    child: Text(
                      detail.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: isOwner
              ? null
              : SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    decoration: const BoxDecoration(color: AppColors.surface),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.onOpenChat,
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('联系卖家'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.onOpenOrder,
                            child: Text(
                              detail.transactionInfo.isNegotiable
                                  ? '立即下单'
                                  : '直接购买',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.isFavorited,
    required this.favoriteBusy,
    required this.canFavorite,
    required this.onBack,
    required this.onFavorite,
  });

  final bool isFavorited;
  final bool favoriteBusy;
  final bool canFavorite;
  final VoidCallback onBack;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Spacer(),
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.share_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: canFavorite && !favoriteBusy ? onFavorite : null,
          icon: Icon(
            isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
        ),
      ],
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
      height: 292,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(30),
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
                  child: CommercePill(
                    label: detail.preview3d.isReady ? '3D 已就绪' : '3D 预览',
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
                const DecoratedBox(
                  decoration: BoxDecoration(
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
                        Colors.black.withValues(alpha: 0.58),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
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
                          color: Colors.white70,
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
    return CommerceCard(
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
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: AppColors.coral),
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
                const CommercePill(
                  label: '3D 展示',
                  backgroundColor: Color(0xFFE4F5EE),
                  foregroundColor: AppColors.mint,
                ),
              if (detail.transactionInfo.isNegotiable)
                const CommercePill(
                  label: '支持议价',
                  backgroundColor: Color(0xFFFFF3D8),
                  foregroundColor: AppColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(detail.summary.title, style: Theme.of(context).textTheme.headlineSmall),
          if (detail.summary.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detail.summary.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CommercePill(
                label: detail.transactionInfo.conditionLabel,
                backgroundColor: AppColors.surfaceSoft,
                foregroundColor: AppColors.primary,
              ),
              CommercePill(
                label: detail.summary.shippingPromise,
                backgroundColor: const Color(0xFFE8EEF7),
                foregroundColor: AppColors.ocean,
              ),
              CommercePill(
                label: detail.summary.location,
                backgroundColor: const Color(0xFFFFF3D8),
                foregroundColor: AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SellerSummary extends StatelessWidget {
  const _SellerSummary({
    required this.detail,
    required this.isOwner,
    required this.onOpenChat,
  });

  final ListingDetail detail;
  final bool isOwner;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final trust = detail.summary.sellerTrust;
    return CommerceCard(
      title: '卖家信息',
      subtitle: detail.sellerLocation,
      action: isOwner
          ? const CommercePill(
              label: '我的商品',
              backgroundColor: Color(0xFFFFF3D8),
              foregroundColor: AppColors.warning,
            )
          : TextButton(onPressed: onOpenChat, child: const Text('联系')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.surfaceSoft,
                backgroundImage: detail.summary.sellerAvatarUrl == null
                    ? null
                    : NetworkImage(detail.summary.sellerAvatarUrl!),
                child: detail.summary.sellerAvatarUrl == null
                    ? const Icon(Icons.person_rounded, color: AppColors.textMuted)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.summary.sellerName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail.sellerBio,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CommercePill(
                label: '芝麻分 ${trust.sesameScore}',
                backgroundColor: const Color(0xFFE8F7F0),
                foregroundColor: AppColors.success,
              ),
              CommercePill(
                label: '成交 ${trust.soldCount}',
                backgroundColor: AppColors.surfaceSoft,
                foregroundColor: AppColors.primary,
              ),
              CommercePill(
                label: '关注 ${trust.followersCount}',
                backgroundColor: const Color(0xFFE8EEF7),
                foregroundColor: AppColors.ocean,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
