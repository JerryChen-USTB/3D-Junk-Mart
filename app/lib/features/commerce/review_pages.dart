import 'package:flutter/material.dart';

import '../../core/commerce/commerce_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.session,
    required this.repository,
    required this.orderId,
  });

  final AppSession session;
  final CommerceRepository repository;
  final String orderId;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final TextEditingController _contentController = TextEditingController();
  late Future<Map<String, dynamic>> _draftFuture;
  late Future<List<Map<String, dynamic>>> _tagsFuture;
  int _rating = 5;
  final Set<String> _selectedTags = <String>{};
  bool _submitting = false;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _draftFuture = widget.repository.fetchReviewDraft(
      widget.orderId,
      widget.session.accessToken,
    );
    _tagsFuture = widget.repository.fetchReviewTags();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.submitReview(
        widget.session.accessToken,
        orderId: widget.orderId,
        rating: _rating,
        content: _contentController.text.trim(),
        tags: _selectedTags.toList(growable: false),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('订单评价')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _draftFuture,
        builder: (context, draftSnapshot) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _tagsFuture,
            builder: (context, tagsSnapshot) {
              final draft = draftSnapshot.data ?? const <String, dynamic>{};
              final tags = tagsSnapshot.data ?? const <Map<String, dynamic>>[];
              if (!_draftLoaded &&
                  draftSnapshot.connectionState == ConnectionState.done) {
                _contentController.text = draft['content']?.toString() ?? '';
                _rating = (draft['rating'] as num?)?.toInt() ?? _rating;
                final existingTags =
                    ((draft['tags'] as List?) ?? const <Object?>[]).map(
                      (item) => item.toString(),
                    );
                _selectedTags.addAll(existingTags);
                _draftLoaded = true;
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _SectionCard(
                    title: '评分',
                    child: Wrap(
                      spacing: 8,
                      children: List<Widget>.generate(5, (index) {
                        final value = index + 1;
                        return ChoiceChip(
                          label: Text('$value 星'),
                          selected: _rating == value,
                          onSelected: (_) => setState(() => _rating = value),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: '标签',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags
                          .map((tag) {
                            final label = tag['display_name']?.toString() ?? '';
                            final selected = _selectedTags.contains(label);
                            return FilterChip(
                              label: Text(label),
                              selected: selected,
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    _selectedTags.add(label);
                                  } else {
                                    _selectedTags.remove(label);
                                  }
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: '评价内容',
                    child: TextField(
                      controller: _contentController,
                      minLines: 6,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        hintText: '补充一下商品、物流和沟通体验',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? '提交中...' : '提交评价'),
          ),
        ),
      ),
    );
  }
}

class ListingReviewsPage extends StatelessWidget {
  const ListingReviewsPage({
    super.key,
    required this.repository,
    required this.listingId,
  });

  final CommerceRepository repository;
  final String listingId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('商品评价')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.fetchListingReviews(listingId),
        builder: (context, snapshot) {
          final reviews = snapshot.data ?? const <Map<String, dynamic>>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              reviews.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (reviews.isEmpty) {
            return const Center(child: Text('还没有评价'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final review = reviews[index];
              final tags = ((review['tags'] as List?) ?? const <Object?>[])
                  .map((item) => item.toString())
                  .join(' · ');
              return _SectionCard(
                title: '${review['rating'] ?? ''} 星',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tags.isNotEmpty) Text(tags),
                    if ((review['content']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(review['content']?.toString() ?? ''),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
