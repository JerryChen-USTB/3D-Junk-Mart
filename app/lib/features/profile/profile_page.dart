// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

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
    required this.onOpenOrder,
    required this.onOpenReview,
    required this.onOpenSuccess,
    required this.onOpenSettings,
    required this.onSignOut,
    this.repository,
    this.onOpenListing,
  });

  final AppSession session;
  final VoidCallback onOpenOrder;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenSuccess;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;
  final ListingsRepository? repository;
  final ValueChanged<String>? onOpenListing;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<List<ListingSummary>>? _myListingsFuture;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  void _loadListings() {
    if (widget.repository != null) {
      _myListingsFuture = widget.repository!.fetchListings(limit: 50);
    }
  }

  Future<void> _refresh() async {
    if (widget.repository == null) return;
    final future = widget.repository!.fetchListings(limit: 50);
    setState(() {
      _myListingsFuture = future;
    });
    await future;
  }

  // --- Helpers to read session data ---

  String get _displayName =>
      widget.session.profile?['display_name']?.toString() ??
      widget.session.user['display_name']?.toString() ??
      '用户';

  String get _bio =>
      widget.session.profile?['bio']?.toString() ??
      widget.session.user['bio']?.toString() ??
      '';

  String get _sesameLabel {
    final score =
        (widget.session.profile?['sesame_credit_score'] as num?)?.toInt() ??
        (widget.session.user['sesame_credit_score'] as num?)?.toInt() ??
        0;
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
      _formatCount(widget.session.user['following_count']);

  String get _followerCount =>
      _formatCount(widget.session.user['follower_count']);

  String get _positiveRate {
    final raw = widget.session.user['positive_rate'];
    if (raw == null) return '-';
    final pct = (raw as num).toDouble();
    return '${pct.toStringAsFixed(0)}%';
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
                  SizedBox(
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
                                'Your published 3DGS products will appear here.',
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
                          'VIP membership',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Unlock exclusive seller benefits',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.primary.withOpacity(0.82),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: widget.onOpenSuccess,
                          child: const Text('Upgrade now'),
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
              title: 'My services',
              actionLabel: 'Tools',
              onActionTap: () {},
            ),
            const SizedBox(height: 12),
            _ServicesPanel(
              tiles: const [
                _ServiceTile(icon: Icons.waves_rounded, label: 'Fish pond'),
                _ServiceTile(icon: Icons.autorenew_rounded, label: 'Old for new'),
                _ServiceTile(
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Safety center',
                ),
                _ServiceTile(icon: Icons.support_agent_rounded, label: 'Support'),
                _ServiceTile(
                  icon: Icons.rate_review_rounded,
                  label: 'My reviews',
                ),
                _ServiceTile(
                  icon: Icons.group_add_rounded,
                  label: 'Invite friends',
                ),
                _ServiceTile(
                  icon: Icons.local_activity_rounded,
                  label: 'Vouchers',
                ),
                _ServiceTile(icon: Icons.location_on_rounded, label: 'Address'),
              ],
            ),
            const SizedBox(height: 16),
            EditorialActionCard(
              title: 'Profile settings',
              subtitle: 'Avatar, nickname, age, and location',
              icon: Icons.person_outline_rounded,
              onTap: widget.onOpenSettings,
            ),
            EditorialActionCard(
              title: 'Order timeline',
              subtitle: 'Review logistics and payment breakdown',
              icon: Icons.local_shipping_rounded,
              onTap: widget.onOpenOrder,
            ),
            EditorialActionCard(
              title: 'Leave a review',
              subtitle: 'Open the post-review flow',
              icon: Icons.rate_review_rounded,
              onTap: widget.onOpenReview,
            ),
            EditorialActionCard(
              title: 'Success flow',
              subtitle: 'Preview wallet confirmation and recommendations',
              icon: Icons.verified_rounded,
              onTap: widget.onOpenSuccess,
            ),
            EditorialActionCard(
              title: 'Sign out',
              subtitle: 'Return to the authentication screen',
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
