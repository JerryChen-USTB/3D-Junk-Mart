// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../listings/listing_card.dart';
import '../media/cover_crop_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    required this.apiClient,
    required this.onOpenSettings,
    required this.onSignOut,
    required this.onOpenFavorites,
    required this.onOpenOrders,
    required this.onOpenWallet,
    required this.onOpenMembership,
    required this.onOpenNotifications,
    required this.onOpenAddresses,
    this.repository,
    this.onOpenListing,
    this.onMarketplaceChanged,
  });

  final AppSession session;
  final ApiClient apiClient;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenMembership;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenAddresses;
  final ListingsRepository? repository;
  final ValueChanged<String>? onOpenListing;
  final VoidCallback? onMarketplaceChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<List<ListingSummary>>? _myListingsFuture;
  Future<List<ListingSummary>>? _favoriteListingsFuture;
  Map<String, dynamic>? _userProfile;
  final ListingPreviewController _previewController =
      ListingPreviewController();

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  void _loadListings() {
    if (widget.repository != null) {
      _myListingsFuture = widget.repository!.fetchMyListings(
        widget.session.accessToken,
      );
      _favoriteListingsFuture = widget.repository!.fetchFavoriteListings(
        widget.session.accessToken,
      );
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final env = await widget.apiClient.getJson(
        '/users/me',
        bearerToken: widget.session.accessToken,
      );
      if (mounted) {
        setState(() => _userProfile = env.data);
      }
    } catch (_) {
      // Ignore and fall back to the in-memory session snapshot.
    }
  }

  Future<void> _refresh() async {
    final futures = <Future<void>>[_loadUserProfile()];
    if (widget.repository != null) {
      final listingsFuture = widget.repository!.fetchMyListings(
        widget.session.accessToken,
      );
      final favoritesFuture = widget.repository!.fetchFavoriteListings(
        widget.session.accessToken,
      );
      setState(() {
        _myListingsFuture = listingsFuture;
        _favoriteListingsFuture = favoritesFuture;
      });
      futures.add(listingsFuture.then((_) {}));
      futures.add(favoritesFuture.then((_) {}));
    }
    await Future.wait(futures);
  }

  Future<void> _openListingActions(ListingSummary listing) async {
    if (widget.repository == null) {
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑商品'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除商品'),
              textColor: AppColors.coral,
              iconColor: AppColors.coral,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (action == 'edit') {
      await _editListing(listing);
    } else if (action == 'delete') {
      await _deleteListing(listing);
    }
  }

  Future<void> _editListing(ListingSummary listing) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    try {
      final detail = await repository.fetchListingDetail(listing.id);
      if (!mounted) {
        return;
      }
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _ListingEditorSheet(
          repository: repository,
          bearerToken: widget.session.accessToken,
          listing: listing,
          detail: detail,
        ),
      );
      if (saved == true && mounted) {
        await _refresh();
        if (!mounted) {
          return;
        }
        widget.onMarketplaceChanged?.call();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('商品信息已更新')));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载商品信息失败：$error')));
    }
  }

  Future<void> _deleteListing(ListingSummary listing) async {
    final repository = widget.repository;
    if (repository == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除商品'),
        content: Text('确认删除“${listing.title}”吗？删除后不会再出现在市场列表中。'),
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
    try {
      await repository.deleteListing(
        listingId: listing.id,
        bearerToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      await _refresh();
      if (!mounted) {
        return;
      }
      widget.onMarketplaceChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('商品已删除')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除商品失败：$error')));
    }
  }

  String _field(String key) =>
      _userProfile?[key]?.toString() ??
      widget.session.profile?[key]?.toString() ??
      widget.session.user[key]?.toString() ??
      '';

  String get _displayName {
    final name = _field('display_name');
    return name.isNotEmpty ? name : '用户';
  }

  String get _bio => _field('bio');

  String get _location {
    final location = _field('location');
    return location.isNotEmpty ? location : '未设置所在地';
  }

  String? get _avatarUrl {
    final url = _field('avatar_url');
    if (url.isEmpty) {
      return null;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final host = Uri.parse(widget.apiClient.baseUrl).resolve('/');
    return host.resolve(url).toString();
  }

  String get _sesameLabel {
    final raw =
        _userProfile?['sesame_credit_score'] ??
        widget.session.profile?['sesame_credit_score'] ??
        widget.session.user['sesame_credit_score'];
    final score = (raw as num?)?.toInt() ?? 0;
    if (score >= 700) {
      return '信用极好';
    }
    if (score >= 650) {
      return '信用优秀';
    }
    if (score >= 600) {
      return '信用良好';
    }
    if (score >= 550) {
      return '信用中等';
    }
    if (score > 0) {
      return '信用待提升';
    }
    return '暂未评估';
  }

  String _formatCount(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(1)}万';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toString();
  }

  String get _followingCount => _formatCount(
    _userProfile?['following_count'] ?? widget.session.user['following_count'],
  );

  String get _followerCount => _formatCount(
    _userProfile?['follower_count'] ?? widget.session.user['follower_count'],
  );

  String get _positiveRate {
    final raw =
        _userProfile?['positive_rate'] ?? widget.session.user['positive_rate'];
    if (raw == null) {
      return '-';
    }
    final pct = (raw as num).toDouble();
    return '${pct.toStringAsFixed(0)}%';
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await widget.onSignOut();
    }
  }

  Widget _buildAvatar() {
    if (_avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.network(
          _avatarUrl!,
          width: 76,
          height: 76,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _ProfileAvatarFallback(name: _displayName),
        ),
      );
    }
    return _ProfileAvatarFallback(name: _displayName);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey<String>('profile-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                EditorialRoundIconButton(
                  icon: Icons.settings_rounded,
                  onTap: widget.onOpenSettings,
                ),
                Text('我的', style: Theme.of(context).textTheme.titleLarge),
                EditorialRoundIconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: widget.onOpenNotifications,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAvatar(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            EditorialPill(
                              label: _sesameLabel,
                              backgroundColor: const Color(0xFFE0F7F7),
                              foregroundColor: AppColors.mint,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _location,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_bio.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _bio,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileMetric(
                          value: _followingCount,
                          label: '关注',
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: _followerCount,
                          label: '粉丝',
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: _positiveRate,
                          label: '好评率',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_myListingsFuture != null &&
                _favoriteListingsFuture != null) ...[
              FutureBuilder<List<ListingSummary>>(
                future: _myListingsFuture,
                builder: (context, listingsSnapshot) {
                  return FutureBuilder<List<ListingSummary>>(
                    future: _favoriteListingsFuture,
                    builder: (context, favoritesSnapshot) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的交易',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          _BuyerActionPanel(
                            listingCount:
                                listingsSnapshot.data?.length.toString() ?? '0',
                            favoriteCount:
                                favoritesSnapshot.data?.length.toString() ??
                                '0',
                            onOpenFavorites: widget.onOpenFavorites,
                            onOpenOrders: widget.onOpenOrders,
                            onOpenWallet: widget.onOpenWallet,
                            onOpenMembership: widget.onOpenMembership,
                            onOpenNotifications: widget.onOpenNotifications,
                            onOpenAddresses: widget.onOpenAddresses,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_myListingsFuture != null) ...[
              FutureBuilder<List<ListingSummary>>(
                future: _myListingsFuture,
                builder: (context, snapshot) {
                  final listings = snapshot.data ?? const <ListingSummary>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EditorialSectionHeader(
                        title: '我的商品',
                        actionLabel: '共 ${listings.length} 件',
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          listings.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (listings.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.store_rounded,
                                size: 40,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '还没有发布商品',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '你发布的 3D 商品会显示在这里。',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        )
                      else
                        SizedBox(
                          height: 344,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: listings.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final listing = listings[index];
                              return SizedBox(
                                width: 220,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ListingCard(
                                        listing: listing,
                                        tall: false,
                                        previewController: _previewController,
                                        onTap: () => widget.onOpenListing?.call(
                                          listing.id,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 12,
                                      bottom: 12,
                                      child: Material(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.9,
                                        ),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              _openListingActions(listing),
                                          child: const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: Icon(
                                              Icons.more_horiz_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18FFD83D),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '会员权益',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '解锁更多卖家展示位、优先曝光和专属支持。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.primary.withOpacity(0.82),
                              ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: widget.onOpenMembership,
                          child: const Text('查看会员'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: EditorialImagePlaceholder(
                      label: 'VIP',
                      subtitle: '权益',
                      badge: '会员',
                      height: 86,
                      borderRadius: 22,
                      accentColor: Colors.white.withOpacity(0.34),
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            EditorialSectionHeader(
              title: '我的服务',
              actionLabel: '更多',
              onActionTap: () {},
            ),
            const SizedBox(height: 12),
            const _ServicesPanel(
              tiles: [
                _ServiceTile(icon: Icons.waves_rounded, label: '闲置回收'),
                _ServiceTile(icon: Icons.autorenew_rounded, label: '以旧换新'),
                _ServiceTile(
                  icon: Icons.admin_panel_settings_rounded,
                  label: '安全中心',
                ),
                _ServiceTile(icon: Icons.support_agent_rounded, label: '客服'),
                _ServiceTile(icon: Icons.rate_review_rounded, label: '我的评价'),
                _ServiceTile(icon: Icons.group_add_rounded, label: '邀请好友'),
                _ServiceTile(icon: Icons.local_activity_rounded, label: '优惠券'),
                _ServiceTile(icon: Icons.location_on_rounded, label: '地址管理'),
              ],
            ),
            const SizedBox(height: 16),
            EditorialActionCard(
              title: '个人设置',
              subtitle: '头像、昵称、生日和所在地',
              icon: Icons.person_outline_rounded,
              onTap: widget.onOpenSettings,
            ),
            EditorialActionCard(
              title: '退出登录',
              subtitle: '退出当前账号并返回登录页',
              icon: Icons.logout_rounded,
              onTap: _confirmSignOut,
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteListingsPage extends StatefulWidget {
  const FavoriteListingsPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenListing,
  });

  final AppSession session;
  final ListingsRepository repository;
  final ValueChanged<String> onOpenListing;

  @override
  State<FavoriteListingsPage> createState() => _FavoriteListingsPageState();
}

class _FavoriteListingsPageState extends State<FavoriteListingsPage> {
  late Future<List<ListingSummary>> _future;
  final ListingPreviewController _previewController =
      ListingPreviewController();

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchFavoriteListings(
      widget.session.accessToken,
    );
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchFavoriteListings(
      widget.session.accessToken,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('我的收藏')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ListingSummary>>(
          future: _future,
          builder: (context, snapshot) {
            final listings = snapshot.data ?? const <ListingSummary>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                listings.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (listings.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  _ProfileEmptyCard(
                    icon: Icons.favorite_border_rounded,
                    title: '还没有收藏商品',
                    subtitle: '看到喜欢的商品可以先收藏，后续从这里快速找回。',
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  '共 ${listings.length} 件收藏',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = adaptiveGridCardWidth(
                      constraints.maxWidth,
                    );
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final listing in listings)
                          SizedBox(
                            width: cardWidth,
                            child: ListingCard(
                              listing: listing,
                              tall: false,
                              previewController: _previewController,
                              onTap: () => widget.onOpenListing(listing.id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BuyerActionPanel extends StatelessWidget {
  const _BuyerActionPanel({
    required this.listingCount,
    required this.favoriteCount,
    required this.onOpenFavorites,
    required this.onOpenOrders,
    required this.onOpenWallet,
    required this.onOpenMembership,
    required this.onOpenNotifications,
    required this.onOpenAddresses,
  });

  final String listingCount;
  final String favoriteCount;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenMembership;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenAddresses;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ProfileCountShortcut(
                  value: favoriteCount,
                  label: '我的收藏',
                  icon: Icons.favorite_rounded,
                  color: AppColors.coral,
                  onTap: onOpenFavorites,
                ),
              ),
              Expanded(
                child: _ProfileCountShortcut(
                  value: listingCount,
                  label: '我的商品',
                  icon: Icons.storefront_rounded,
                  color: AppColors.ocean,
                  onTap: null,
                ),
              ),
              Expanded(
                child: _ProfileCountShortcut(
                  value: '3D',
                  label: '展示资产',
                  icon: Icons.view_in_ar_rounded,
                  color: AppColors.mint,
                  onTap: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.surfaceSoft),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProfileIconAction(
                  icon: Icons.receipt_long_rounded,
                  label: '订单',
                  onTap: onOpenOrders,
                ),
              ),
              Expanded(
                child: _ProfileIconAction(
                  icon: Icons.account_balance_wallet_rounded,
                  label: '钱包',
                  onTap: onOpenWallet,
                ),
              ),
              Expanded(
                child: _ProfileIconAction(
                  icon: Icons.workspace_premium_rounded,
                  label: '会员',
                  onTap: onOpenMembership,
                ),
              ),
              Expanded(
                child: _ProfileIconAction(
                  icon: Icons.notifications_active_rounded,
                  label: '通知',
                  onTap: onOpenNotifications,
                ),
              ),
              Expanded(
                child: _ProfileIconAction(
                  icon: Icons.location_on_rounded,
                  label: '地址',
                  onTap: onOpenAddresses,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCountShortcut extends StatelessWidget {
  const _ProfileCountShortcut({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileIconAction extends StatelessWidget {
  const _ProfileIconAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          children: [
            Icon(icon, size: 24, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileEmptyCard extends StatelessWidget {
  const _ProfileEmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatarFallback extends StatelessWidget {
  const _ProfileAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first : '我',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ServicesPanel extends StatelessWidget {
  const _ServicesPanel({required this.tiles});

  final List<_ServiceTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 420 ? 4 : 3;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: tiles,
          ),
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ListingEditorSheet extends StatefulWidget {
  const _ListingEditorSheet({
    required this.repository,
    required this.bearerToken,
    required this.listing,
    required this.detail,
  });

  final ListingsRepository repository;
  final String bearerToken;
  final ListingSummary listing;
  final ListingDetail detail;

  @override
  State<_ListingEditorSheet> createState() => _ListingEditorSheetState();
}

class _ListingEditorSheetState extends State<_ListingEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _locationController;
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedCover;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.listing.title);
    _descriptionController = TextEditingController(
      text: widget.detail.description,
    );
    _priceController = TextEditingController(
      text: (widget.listing.priceMinor / 100).toStringAsFixed(2),
    );
    _locationController = TextEditingController(text: widget.listing.location);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickCover(ImageSource source) async {
    final image = await pickAndCropCoverImage(
      context,
      picker: _picker,
      source: source,
    );
    if (image == null || !mounted) {
      return;
    }
    setState(() {
      _selectedCover = image;
      _error = null;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入商品标题');
      return;
    }
    final priceValue = double.tryParse(_priceController.text.trim());
    if (priceValue == null || priceValue < 0) {
      setState(() => _error = '请输入有效价格');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateListing(
        listingId: widget.listing.id,
        bearerToken: widget.bearerToken,
        title: title,
        description: _descriptionController.text.trim(),
        priceMinor: (priceValue * 100).round(),
        currency: widget.listing.currency,
        locationCity: _locationController.text.trim(),
      );
      if (_selectedCover != null) {
        await widget.repository.uploadListingCover(
          listingId: widget.listing.id,
          bearerToken: widget.bearerToken,
          filePath: _selectedCover!.path,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '保存失败：$error';
        _saving = false;
      });
      return;
    }
    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = _selectedCover != null
        ? Image.file(
            File(_selectedCover!.path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
          )
        : widget.listing.coverImageUrl != null
        ? Image.network(
            widget.listing.coverImageUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 180,
            errorBuilder: (_, _, _) => const _EditorCoverPlaceholder(),
          )
        : const _EditorCoverPlaceholder();

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('编辑商品', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(20), child: cover),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickCover(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('拍摄封面'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _pickCover(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('更换封面'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '商品标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '商品描述'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '价格'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: '所在地区'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.coral),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存修改'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorCoverPlaceholder extends StatelessWidget {
  const _EditorCoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      color: AppColors.surfaceSoft,
      child: const Center(
        child: Icon(Icons.image_outlined, size: 38, color: AppColors.textMuted),
      ),
    );
  }
}
