import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';
import '../listings/listing_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    required this.onGoHome,
    required this.onOpenListing,
  });

  final ListingsRepository repository;
  final VoidCallback onGoHome;
  final ValueChanged<String> onOpenListing;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController(text: '3D');
  late Future<List<ListingSummary>> _listingsFuture;

  @override
  void initState() {
    super.initState();
    _listingsFuture = widget.repository.fetchListings(limit: 20);
    _queryController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchListings(limit: 20);
    setState(() {
      _listingsFuture = future;
    });
    await future;
  }

  List<ListingSummary> _filter(List<ListingSummary> items) {
    final keyword = _queryController.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      return items;
    }
    return items.where((listing) {
      final haystack = [
        listing.title,
        listing.subtitle,
        listing.location,
        listing.sellerName,
        ...listing.badges,
      ].join(' ').toLowerCase();
      return haystack.contains(keyword);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<ListingSummary>>(
        future: _listingsFuture,
        builder: (context, snapshot) {
          final filtered = _filter(snapshot.data ?? const <ListingSummary>[]);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 128),
              children: [
                Row(
                  children: [
                    EditorialRoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: widget.onGoHome,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded, color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _queryController,
                                decoration: const InputDecoration(
                                  hintText: 'Search title, seller, location, or 3D tag',
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const CircleAvatar(
                      radius: 21,
                      backgroundColor: AppColors.surface,
                      child: Icon(Icons.tune_rounded, color: AppColors.text),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: const [
                      _SearchFilterChip(label: 'All', selected: true),
                      _SearchFilterChip(label: '3D-ready'),
                      _SearchFilterChip(label: 'Latest'),
                      _SearchFilterChip(label: 'Price'),
                      _SearchFilterChip(
                        label: 'Filters',
                        icon: Icons.filter_list_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SearchSummaryCard(
                  query: _queryController.text.trim().isEmpty
                      ? 'All listings'
                      : _queryController.text.trim(),
                  count: filtered.length,
                ),
                const SizedBox(height: 16),
                EditorialSectionHeader(
                  title: 'Search results',
                  actionLabel: '${filtered.length} items',
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError && filtered.isEmpty)
                  _SearchErrorPanel(onRetry: _refresh)
                else if (filtered.isEmpty)
                  const _SearchEmptyState()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = adaptiveGridCardWidth(constraints.maxWidth);
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List<Widget>.generate(filtered.length, (index) {
                          final listing = filtered[index];
                          return SizedBox(
                            width: cardWidth,
                            child: ListingCard(
                              listing: listing,
                              tall: index % 3 == 1,
                              onTap: () => widget.onOpenListing(listing.id),
                            ),
                          );
                        }),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchFilterChip extends StatelessWidget {
  const _SearchFilterChip({
    required this.label,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppColors.accent : AppColors.surface;
    final foreground = selected ? AppColors.primary : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSummaryCard extends StatelessWidget {
  const _SearchSummaryCard({required this.query, required this.count});

  final String query;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 62,
            height: 62,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Icon(
                Icons.view_in_ar_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  query,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Found $count matching listings across titles, sellers, locations, and 3D tags.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        height: 1.4,
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

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('No matching listings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Try a shorter keyword, or search for 3D to focus on visualized items.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SearchErrorPanel extends StatelessWidget {
  const _SearchErrorPanel({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.coral),
          const SizedBox(height: 12),
          Text('Search failed to load', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Try again in a moment, or return to the home feed.',
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
