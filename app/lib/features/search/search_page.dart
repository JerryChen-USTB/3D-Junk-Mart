import 'package:flutter/material.dart';

import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
import '../listings/listing_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    required this.session,
    required this.onGoHome,
    required this.onOpenListing,
  });

  final ListingsRepository repository;
  final AppSession session;
  final VoidCallback onGoHome;
  final ValueChanged<String> onOpenListing;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _queryController = TextEditingController();
  final ListingPreviewController _previewController = ListingPreviewController();

  List<ListingSummary> _results = const <ListingSummary>[];
  List<String> _suggestions = const <String>[];
  List<String> _recentQueries = const <String>[];
  Map<String, dynamic> _facets = const <String, dynamic>{};
  bool _loading = true;
  String? _errorMessage;
  String _sort = 'latest';
  String? _priceBucket;
  String? _conditionLevel;
  bool _only3d = false;
  bool _onlyNegotiable = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _performSearch(initial: true);
  }

  @override
  void dispose() {
    _previewController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final suggestions = await widget.repository.fetchSearchSuggestions();
      final facets = await widget.repository.fetchSearchFacets();
      if (!mounted) {
        return;
      }
      setState(() {
        _suggestions =
            ((suggestions['suggestions'] as List?) ?? const <Object?>[])
                .map((item) => item.toString())
                .toList(growable: false);
        _recentQueries =
            ((suggestions['recent_queries'] as List?) ?? const <Object?>[])
                .map((item) => item.toString())
                .toList(growable: false);
        _facets = facets;
      });
    } catch (_) {
      // Search metadata is optional; the listing query still needs to work.
    }
  }

  Future<void> _performSearch({bool initial = false, String? forcedQuery}) async {
    if (!initial) {
      FocusScope.of(context).unfocus();
    }
    _previewController.clear();

    final query = (forcedQuery ?? _queryController.text).trim();
    if (forcedQuery != null) {
      _queryController.text = forcedQuery;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await widget.repository.fetchListings(
        limit: 24,
        query: query,
        sort: _sort,
        priceBucket: _priceBucket,
        conditionLevel: _conditionLevel,
        only3d: _only3d,
        onlyNegotiable: _onlyNegotiable,
        bearerToken: widget.session.isGuest ? null : widget.session.accessToken,
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

  Future<void> _applyFilter(VoidCallback update) async {
    setState(update);
    await _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final priceBuckets = _facetOptions(_facets['price_buckets']);
    final conditionLevels = _facetOptions(_facets['condition_levels']);
    final sortOptions = _facetOptions(_facets['sort_options']);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _performSearch(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 128),
          children: [
            _SearchHeader(
              controller: _queryController,
              onBack: widget.onGoHome,
              onSearch: () => _performSearch(),
            ),
            const SizedBox(height: 12),
            _SearchFilterPanel(
              sort: _sort,
              priceBucket: _priceBucket,
              conditionLevel: _conditionLevel,
              only3d: _only3d,
              onlyNegotiable: _onlyNegotiable,
              sortOptions: sortOptions,
              priceBuckets: priceBuckets,
              conditionLevels: conditionLevels,
              onSortChanged: (value) => _applyFilter(() => _sort = value),
              onPriceChanged: (value) => _applyFilter(
                () => _priceBucket = value.isEmpty ? null : value,
              ),
              onConditionChanged: (value) => _applyFilter(
                () => _conditionLevel = value.isEmpty ? null : value,
              ),
              onOnly3dChanged: (value) {
                _applyFilter(() => _only3d = value == 'yes');
              },
              onOnlyNegotiableChanged: (value) {
                _applyFilter(() => _onlyNegotiable = value == 'yes');
              },
            ),
            if (_suggestions.isNotEmpty || _recentQueries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SearchTags(
                suggestions: _suggestions,
                recentQueries: _recentQueries,
                onTap: (value) => _performSearch(forcedQuery: value),
              ),
            ],
            const SizedBox(height: 18),
            _ResultHeader(count: _results.length),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              CommerceEmptyState(
                icon: Icons.search_off_rounded,
                title: '加载失败',
                subtitle: _errorMessage!,
              )
            else if (_results.isEmpty)
              const CommerceEmptyState(
                icon: Icons.search_off_rounded,
                title: '没有匹配商品',
                subtitle: '试试更短的关键词，或调整筛选条件后重新搜索。',
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

List<_FilterOption> _facetOptions(Object? raw) {
  return ((raw as List?) ?? const <Object?>[])
      .whereType<Map>()
      .map((item) {
        final data = item.cast<String, dynamic>();
        return _FilterOption(
          id: data['id']?.toString() ?? '',
          label: data['label']?.toString() ?? '',
        );
      })
      .where((option) => option.id.isNotEmpty && option.label.isNotEmpty)
      .toList(growable: false);
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.onBack,
    required this.onSearch,
  });

  final TextEditingController controller;
  final VoidCallback onBack;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            padding: EdgeInsets.zero,
            iconSize: 30,
            color: AppColors.text,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => onSearch(),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: '搜索商品',
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          height: 44,
          child: FilledButton(
            onPressed: onSearch,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              textStyle: Theme.of(context).textTheme.labelLarge,
            ),
            child: const Text('搜索'),
          ),
        ),
      ],
    );
  }
}

class _SearchFilterPanel extends StatelessWidget {
  const _SearchFilterPanel({
    required this.sort,
    required this.priceBucket,
    required this.conditionLevel,
    required this.only3d,
    required this.onlyNegotiable,
    required this.sortOptions,
    required this.priceBuckets,
    required this.conditionLevels,
    required this.onSortChanged,
    required this.onPriceChanged,
    required this.onConditionChanged,
    required this.onOnly3dChanged,
    required this.onOnlyNegotiableChanged,
  });

  final String sort;
  final String? priceBucket;
  final String? conditionLevel;
  final bool only3d;
  final bool onlyNegotiable;
  final List<_FilterOption> sortOptions;
  final List<_FilterOption> priceBuckets;
  final List<_FilterOption> conditionLevels;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onConditionChanged;
  final ValueChanged<String> onOnly3dChanged;
  final ValueChanged<String> onOnlyNegotiableChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveSortOptions = sortOptions.isEmpty
        ? const <_FilterOption>[
            _FilterOption(id: 'latest', label: '最新上新'),
            _FilterOption(id: 'popular', label: '人气优先'),
            _FilterOption(id: 'price_asc', label: '价格从低到高'),
            _FilterOption(id: 'price_desc', label: '价格从高到低'),
          ]
        : sortOptions;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _FilterDropdown(
            value: sort,
            items: effectiveSortOptions,
            onChanged: onSortChanged,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            value: priceBucket ?? '',
            items: [
              const _FilterOption(id: '', label: '全部价格'),
              ...priceBuckets,
            ],
            onChanged: onPriceChanged,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            value: conditionLevel ?? '',
            items: [
              const _FilterOption(id: '', label: '全部成色'),
              ...conditionLevels,
            ],
            onChanged: onConditionChanged,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            value: only3d ? 'yes' : 'all',
            items: const [
              _FilterOption(id: 'all', label: '全部商品'),
              _FilterOption(id: 'yes', label: '仅看 3D'),
            ],
            onChanged: onOnly3dChanged,
          ),
          const SizedBox(width: 8),
          _FilterDropdown(
            value: onlyNegotiable ? 'yes' : 'all',
            items: const [
              _FilterOption(id: 'all', label: '全部商品'),
              _FilterOption(id: 'yes', label: '仅可议价'),
            ],
            onChanged: onOnlyNegotiableChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<_FilterOption> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = items.firstWhere(
      (item) => item.id == value,
      orElse: () => items.first,
    );

    return PopupMenuButton<String>(
      initialValue: selected.id,
      onSelected: onChanged,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => items
          .map(
            (item) => PopupMenuItem<String>(
              value: item.id,
              child: Row(
                children: [
                  Expanded(child: Text(item.label)),
                  if (item.id == selected.id)
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.accentDeep,
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        height: 42,
        constraints: const BoxConstraints(minWidth: 86, maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _SearchTags extends StatelessWidget {
  const _SearchTags({
    required this.suggestions,
    required this.recentQueries,
    required this.onTap,
  });

  final List<String> suggestions;
  final List<String> recentQueries;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final tags = {
      ...suggestions.take(6),
      ...recentQueries.take(4),
    }.toList(growable: false);

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = tags[index];
          return ActionChip(
            label: Text(tag),
            onPressed: () => onTap(tag),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('搜索结果', style: Theme.of(context).textTheme.headlineSmall),
        ),
        Text(
          '$count 件',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
