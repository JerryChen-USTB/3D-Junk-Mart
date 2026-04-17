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
  final TextEditingController _queryController = TextEditingController();
  final ListingPreviewController _previewController = ListingPreviewController();
  List<ListingSummary> _results = const <ListingSummary>[];
  bool _loading = true;
  String? _errorMessage;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _performSearch(initial: true);
  }

  @override
  void dispose() {
    _previewController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _performSearch({bool initial = false}) async {
    if (!initial) {
      FocusScope.of(context).unfocus();
    }
    _previewController.clear();
    final query = _queryController.text.trim();
    setState(() {
      _loading = true;
      _errorMessage = null;
      _activeQuery = query;
    });

    try {
      final results = await widget.repository.fetchListings(
        limit: 20,
        query: query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const <ListingSummary>[];
        _loading = false;
        _errorMessage = initial ? '商品加载失败，请稍后重试。' : '搜索失败，请重试。';
      });
      debugPrint('Search failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _performSearch(),
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
                        const Icon(
                          Icons.search_rounded,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _performSearch(),
                            decoration: const InputDecoration(
                              hintText: '搜索商品标题、描述或地区',
                              filled: false,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      _performSearch();
                    },
                    child: const Text('搜索'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchSummaryCard(
              query: _activeQuery.isEmpty ? '全部商品' : _activeQuery,
              count: _results.length,
            ),
            const SizedBox(height: 16),
            EditorialSectionHeader(
              title: '搜索结果',
              actionLabel: '${_results.length} 件',
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              _SearchEmptyState(title: '加载失败', message: _errorMessage!)
            else if (_results.isEmpty)
              const _SearchEmptyState(
                title: '没有找到匹配商品',
                message: '可以尝试更短的关键词，或者返回首页看看最新商品。',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = adaptiveGridCardWidth(constraints.maxWidth);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List<Widget>.generate(_results.length, (index) {
                      final listing = _results[index];
                      return SizedBox(
                        width: cardWidth,
                        child: ListingCard(
                          listing: listing,
                          tall: index.isOdd,
                          previewController: _previewController,
                          onTap: () => widget.onOpenListing(listing.id),
                        ),
                      );
                    }),
                  );
                },
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前市场里共有 $count 件匹配商品。',
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
  const _SearchEmptyState({required this.title, required this.message});

  final String title;
  final String message;

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
          const Icon(
            Icons.search_off_rounded,
            size: 44,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
