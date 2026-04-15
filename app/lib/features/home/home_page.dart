import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../listings/listing_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onGoSearch,
    required this.onOpenListing,
    required this.onOpenOrder,
    required this.onOpenChat,
    required this.onOpenReview,
    required this.onOpenSuccess,
  });

  final ListingsRepository repository;
  final VoidCallback onGoSearch;
  final ValueChanged<String> onOpenListing;
  final VoidCallback onOpenOrder;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenSuccess;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<ListingSummary>> _listingsFuture;

  @override
  void initState() {
    super.initState();
    _listingsFuture = widget.repository.fetchListings(limit: 12);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchListings(limit: 12);
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
                  title: '3D resale\nmarketplace',
                  subtitle:
                      'Browse second-hand goods that can grow into richer 3D product experiences.',
                  badge: 'Junk Mart',
                ),
                const SizedBox(height: 18),
                EditorialSectionHeader(
                  title: 'Recommended listings',
                  actionLabel: '${listings.length} items',
                  onActionTap: widget.onGoSearch,
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    listings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError && listings.isEmpty)
                  _ErrorPanel(onRetry: _refresh)
                else
                  _ListingGrid(
                    listings: listings,
                    onOpenListing: widget.onOpenListing,
                  ),
                const SizedBox(height: 20),
                EditorialSectionHeader(
                  title: 'Quick actions',
                  actionLabel: 'Demo',
                ),
                const SizedBox(height: 12),
                EditorialActionCard(
                  title: 'Order detail',
                  subtitle: 'Review shipping, payment, and receipt confirmation flows',
                  icon: Icons.local_shipping_rounded,
                  onTap: widget.onOpenOrder,
                ),
                EditorialActionCard(
                  title: 'Chat thread',
                  subtitle: 'Continue the buyer and seller conversation',
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: widget.onOpenChat,
                ),
                EditorialActionCard(
                  title: 'Review flow',
                  subtitle: 'Open the rating, tag, and text review experience',
                  icon: Icons.rate_review_rounded,
                  onTap: widget.onOpenReview,
                ),
                EditorialActionCard(
                  title: 'Payment success',
                  subtitle: 'Preview the completion state after checkout',
                  icon: Icons.verified_rounded,
                  onTap: widget.onOpenSuccess,
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
                      'Search 3D-ready listings',
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
          child: Icon(Icons.notifications_none_rounded, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _ListingGrid extends StatelessWidget {
  const _ListingGrid({
    required this.listings,
    required this.onOpenListing,
  });

  final List<ListingSummary> listings;
  final ValueChanged<String> onOpenListing;

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
          Text('Failed to load listings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'The backend listing feed is unstable right now, so we retry directly against the server.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reload')),
        ],
      ),
    );
  }
}
