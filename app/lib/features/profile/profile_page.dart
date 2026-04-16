// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../listings/listing_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    required this.apiClient,
    required this.onOpenSettings,
    required this.onSignOut,
    this.repository,
    this.onOpenListing,
  });

  final AppSession session;
  final ApiClient apiClient;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;
  final ListingsRepository? repository;
  final ValueChanged<String>? onOpenListing;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<List<ListingSummary>>? _myListingsFuture;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadUserProfile();
  }

  void _loadListings() {
    if (widget.repository != null) {
      _myListingsFuture = widget.repository!.fetchListings(limit: 50);
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
      // Silently fail — fall back to session data.
    }
  }

  Future<void> _refresh() async {
    final futures = <Future<void>>[_loadUserProfile()];
    if (widget.repository != null) {
      final future = widget.repository!.fetchListings(limit: 50);
      setState(() => _myListingsFuture = future);
      futures.add(future.then((_) {}));
    }
    await Future.wait(futures);
  }

  // --- Helpers: prefer fetched _userProfile, fall back to session ---

  String _field(String key) =>
      _userProfile?[key]?.toString() ??
      widget.session.profile?[key]?.toString() ??
      widget.session.user[key]?.toString() ??
      '';

  String get _displayName {
    final n = _field('display_name');
    return n.isNotEmpty ? n : '用户';
  }

  String get _bio => _field('bio');

  String? get _avatarUrl {
    final url = _field('avatar_url');
    return url.isNotEmpty ? url : null;
  }

  String get _sesameLabel {
    final raw = _userProfile?['sesame_credit_score'] ??
        widget.session.profile?['sesame_credit_score'] ??
        widget.session.user['sesame_credit_score'];
    final score = (raw as num?)?.toInt() ?? 0;
    if (score >= 700) return '信用: 极好';
    if (score >= 650) return '信用: 优秀';
    if (score >= 600) return '信用: 良好';
    if (score >= 550) return '信用: 中等';
    if (score >   0) return '信用: 较差';
    return '信用: 未评估';
  }

  String _formatCount(Object? raw) {
    final n = (raw as num?)?.toInt() ?? 0;
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String get _followingCount =>
      _formatCount(_userProfile?['following_count'] ??
          widget.session.user['following_count']);

  String get _followerCount =>
      _formatCount(_userProfile?['follower_count'] ??
          widget.session.user['follower_count']);

  String get _positiveRate {
    final raw = _userProfile?['positive_rate'] ??
        widget.session.user['positive_rate'];
    if (raw == null) return '-';
    final pct = (raw as num).toDouble();
    return '${pct.toStringAsFixed(0)}%';
  }

  /// Build full avatar URL from relative path.
  String? get _fullAvatarUrl {
    final url = _avatarUrl;
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    // Relative path like /storage/avatars/xxx.jpg → prepend base.
    final base = widget.apiClient.baseUrl;
    // baseUrl ends with /api/v1, go up to host.
    final hostEnd = base.indexOf('/api');
    final host = hostEnd > 0 ? base.substring(0, hostEnd) : base;
    return '$host$url';
  }

  Widget _buildPlaceholderAvatar() {
    return SizedBox(
      width: 100,
      height: 100,
      child: EditorialImagePlaceholder(
        label: _displayName,
        subtitle: _bio.isNotEmpty ? _bio : 'Profile',
        badge: 'My page',
        height: 100,
        borderRadius: 28,
        accentColor: AppColors.accent,
      ),
    );
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
                Text('Profile', style: Theme.of(context).textTheme.titleLarge),
                EditorialRoundIconButton(
                  icon: Icons.qr_code_scanner_rounded,
                  onTap: () {},
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar — show real image or placeholder.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: _fullAvatarUrl != null
                        ? Image.network(
                            _fullAvatarUrl!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildPlaceholderAvatar(),
                          )
                        : _buildPlaceholderAvatar(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_bio.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _bio,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: EditorialPill(
                            label: _sesameLabel,
                            backgroundColor: const Color(0xFFE0F7F7),
                            foregroundColor: AppColors.mint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          children: [
                            _ProfileMetric(value: _followingCount, label: 'Following'),
                            _ProfileMetric(value: _followerCount, label: 'Followers'),
                            _ProfileMetric(value: _positiveRate, label: 'Positive'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // --- Dynamic my listings section ---
            if (_myListingsFuture != null) ...[
              FutureBuilder<List<ListingSummary>>(
                future: _myListingsFuture,
                builder: (context, snapshot) {
                  final listings = snapshot.data ?? const <ListingSummary>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EditorialSectionHeader(
                        title: 'My listings',
                        actionLabel: 'Live ${listings.length}',
                        onActionTap: () {},
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
                              const Icon(Icons.store_rounded,
                                  size: 40, color: AppColors.textMuted),
                              const SizedBox(height: 10),
                              Text('No listings yet',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
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
                          height: 340,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: listings.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final listing = listings[index];
                              return SizedBox(
                                width: 220,
                                child: ListingCard(
                                  listing: listing,
                                  tall: false,
                                  onTap: () => widget.onOpenListing
                                      ?.call(listing.id),
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
            // --- VIP banner ---
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
                          'VIP 会员',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '解锁专属卖家权益',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.primary.withOpacity(0.82),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {},
                          child: const Text('立即开通'),
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
                      subtitle: 'Benefits',
                      badge: 'Club',
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
            _ServicesPanel(
              tiles: const [
                _ServiceTile(icon: Icons.waves_rounded, label: '闲鱼塘'),
                _ServiceTile(icon: Icons.autorenew_rounded, label: '以旧换新'),
                _ServiceTile(
                  icon: Icons.admin_panel_settings_rounded,
                  label: '安全中心',
                ),
                _ServiceTile(icon: Icons.support_agent_rounded, label: '客服'),
                _ServiceTile(
                  icon: Icons.rate_review_rounded,
                  label: '我的评价',
                ),
                _ServiceTile(
                  icon: Icons.group_add_rounded,
                  label: '邀请好友',
                ),
                _ServiceTile(
                  icon: Icons.local_activity_rounded,
                  label: '优惠券',
                ),
                _ServiceTile(icon: Icons.location_on_rounded, label: '地址'),
              ],
            ),
            const SizedBox(height: 16),
            EditorialActionCard(
              title: '个人设置',
              subtitle: '头像、昵称、生日、地址',
              icon: Icons.person_outline_rounded,
              onTap: widget.onOpenSettings,
            ),
            EditorialActionCard(
              title: '退出登录',
              subtitle: '返回登录页面',
              icon: Icons.logout_rounded,
              onTap: () async {
                await widget.onSignOut();
              },
            ),
          ],
        ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
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
