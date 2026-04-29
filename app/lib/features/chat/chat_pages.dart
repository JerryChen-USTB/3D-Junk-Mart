import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
import '../commerce/checkout_page.dart';
import '../listings/listing_detail_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.repository,
    required this.session,
    this.listingsRepository,
  });

  final CommerceRepository repository;
  final AppSession session;
  final ListingsRepository? listingsRepository;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late Future<List<Map<String, dynamic>>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = widget.repository.fetchConversations(
      widget.session.accessToken,
    );
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchConversations(
      widget.session.accessToken,
    );
    setState(() {
      _conversationsFuture = future;
    });
    await future;
  }

  void _openConversation(String conversationId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationDetailPage(
              repository: widget.repository,
              session: widget.session,
              conversationId: conversationId,
              listingsRepository: widget.listingsRepository,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _conversationsFuture,
            builder: (context, snapshot) {
              final conversations =
                  snapshot.data ?? const <Map<String, dynamic>>[];
              if (_useModernMessagesLayout()) {
                return _MessagesContent(
                  conversations: conversations,
                  isLoading:
                      snapshot.connectionState == ConnectionState.waiting,
                  hasError: snapshot.hasError,
                  resolveUrl: widget.repository.resolveUrl,
                  onClearUnread: () async {
                    final unreadConversations = conversations.where(
                      (conversation) =>
                          ((conversation['unread_count'] as num?)?.toInt() ??
                              0) >
                          0,
                    );
                    for (final conversation in unreadConversations) {
                      final conversationId =
                          conversation['id']?.toString() ?? '';
                      if (conversationId.isEmpty) {
                        continue;
                      }
                      await widget.repository.markConversationRead(
                        conversationId,
                        widget.session.accessToken,
                      );
                    }
                    await _refresh();
                  },
                  onOpenConversation: _openConversation,
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
                  Text('消息', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    '和买家、卖家持续沟通，最近会话都会汇总在这里。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      conversations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError && conversations.isEmpty)
                    const CommerceEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: '消息加载失败',
                      subtitle: '下拉刷新后重试。',
                    )
                  else if (conversations.isEmpty)
                    const CommerceEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '还没有会话',
                      subtitle: '从商品详情联系卖家后，会话会显示在这里。',
                    )
                  else
                    ...conversations.map(
                      (conversation) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ConversationTile(
                          conversation: conversation,
                          onTap: () => _openConversation(
                            conversation['id']?.toString() ?? '',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _useModernMessagesLayout() => true;

class _MessagesContent extends StatelessWidget {
  const _MessagesContent({
    required this.conversations,
    required this.isLoading,
    required this.hasError,
    required this.resolveUrl,
    required this.onClearUnread,
    required this.onOpenConversation,
  });

  final List<Map<String, dynamic>> conversations;
  final bool isLoading;
  final bool hasError;
  final String? Function(String?) resolveUrl;
  final Future<void> Function() onClearUnread;
  final ValueChanged<String> onOpenConversation;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '消息',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            TextButton.icon(
              onPressed:
                  conversations.any(
                    (conversation) =>
                        ((conversation['unread_count'] as num?)?.toInt() ?? 0) >
                        0,
                  )
                  ? onClearUnread
                  : null,
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text('清除未读'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                backgroundColor: AppColors.surfaceSoft.withValues(alpha: 0.55),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_horiz_rounded),
              color: AppColors.text,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _MessageShortcutRow(),
        const SizedBox(height: 18),
        if (isLoading && conversations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (hasError && conversations.isEmpty)
          const CommerceEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '消息加载失败',
            subtitle: '下拉刷新后重试。',
          )
        else if (conversations.isEmpty)
          const CommerceEmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: '还没有会话',
            subtitle: '从商品详情联系卖家后，会话会显示在这里。',
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                for (var index = 0; index < conversations.length; index++) ...[
                  _ModernConversationTile(
                    conversation: conversations[index],
                    resolveUrl: resolveUrl,
                    onTap: () => onOpenConversation(
                      conversations[index]['id']?.toString() ?? '',
                    ),
                  ),
                  if (index != conversations.length - 1)
                    const Divider(
                      height: 1,
                      indent: 82,
                      endIndent: 16,
                      color: AppColors.surfaceSoft,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageShortcutRow extends StatelessWidget {
  const _MessageShortcutRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      _MessageShortcut(
        label: '客服',
        icon: Icons.support_agent_rounded,
        color: Color(0xFFFF5A66),
      ),
      _MessageShortcut(
        label: '物流',
        icon: Icons.local_shipping_outlined,
        color: Color(0xFF4FB3F6),
      ),
      _MessageShortcut(
        label: '提醒',
        icon: Icons.notifications_none_rounded,
        color: Color(0xFFF5A623),
      ),
      _MessageShortcut(
        label: '优惠',
        icon: Icons.percent_rounded,
        color: Color(0xFFFF7A59),
      ),
      _MessageShortcut(
        label: '互动',
        icon: Icons.forum_outlined,
        color: Color(0xFF9B7BFF),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: item,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _MessageShortcut extends StatelessWidget {
  const _MessageShortcut({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ModernConversationTile extends StatelessWidget {
  const _ModernConversationTile({
    required this.conversation,
    required this.resolveUrl,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final String? Function(String?) resolveUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUser =
        (conversation['other_user'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final name = otherUser['display_name']?.toString() ?? '对方';
    final listingTitle = conversation['listing_title']?.toString() ?? '商品会话';
    final lastMessage =
        conversation['last_message_preview']?.toString().trim() ?? '';
    final unreadCount = (conversation['unread_count'] as num?)?.toInt() ?? 0;
    final avatarUrl = resolveUrl(otherUser['avatar_url']?.toString());
    final timeLabel = _compactConversationTime(
      conversation['updated_at']?.toString(),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _ConversationAvatar(name: name, imageUrl: avatarUrl),
                  if (unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -4,
                      child: _UnreadBadge(count: unreadCount),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '商品',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            listingTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      lastMessage.isEmpty ? '暂无消息' : lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: lastMessage.isEmpty
                            ? AppColors.textMuted
                            : AppColors.text,
                        fontWeight: unreadCount > 0
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.name, required this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        image: imageUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              ),
      ),
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              initial,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.coral,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

String _compactConversationTime(String? raw) {
  if (raw == null || raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }
  final local = parsed.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final minute = local.minute.toString().padLeft(2, '0');
  if (date == today) {
    return '${local.hour}:$minute';
  }
  if (date == today.subtract(const Duration(days: 1))) {
    return '昨天';
  }
  return '${local.month}-${local.day.toString().padLeft(2, '0')}';
}

class ConversationDetailPage extends StatefulWidget {
  const ConversationDetailPage({
    super.key,
    required this.repository,
    required this.session,
    required this.conversationId,
    this.listingsRepository,
  });

  final CommerceRepository repository;
  final AppSession session;
  final String conversationId;
  final ListingsRepository? listingsRepository;

  @override
  State<ConversationDetailPage> createState() => _ConversationDetailPageState();
}

class _ConversationDetailPageState extends State<ConversationDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Future<Map<String, dynamic>> _detailFuture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _load();
    _detailFuture.then((_) {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final detail = await widget.repository.fetchConversationDetail(
      widget.conversationId,
      widget.session.accessToken,
    );
    await widget.repository.markConversationRead(
      widget.conversationId,
      widget.session.accessToken,
    );
    return detail;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _detailFuture = future;
    });
    await future;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.sendConversationMessage(
        widget.conversationId,
        widget.session.accessToken,
        contentText: text,
      );
      _controller.clear();
      await _refresh();
    } catch (error) {
      _showChatError(error, fallback: '消息发送失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _createOffer() async {
    final priceController = TextEditingController();
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发起议价'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '出价金额（元）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '补充说明'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('发送'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      final value = double.tryParse(priceController.text.trim());
      if (value == null || value <= 0) {
        _showChatError('请输入有效出价');
        return;
      }
      try {
        await widget.repository.createConversationOffer(
          widget.conversationId,
          widget.session.accessToken,
          amountMinor: (value * 100).round(),
          note: noteController.text.trim(),
        );
        await _refresh();
      } catch (error) {
        _showChatError(error, fallback: '议价发送失败，请稍后重试');
      }
    } finally {
      priceController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _acceptOffer(String offerId) async {
    try {
      await widget.repository.acceptConversationOffer(
        widget.conversationId,
        offerId,
        widget.session.accessToken,
      );
      await _refresh();
    } catch (error) {
      _showChatError(error, fallback: '接受议价失败，请稍后重试');
    }
  }

  Future<void> _rejectOffer(String offerId) async {
    try {
      await widget.repository.rejectConversationOffer(
        widget.conversationId,
        offerId,
        widget.session.accessToken,
      );
      await _refresh();
    } catch (error) {
      _showChatError(error, fallback: '拒绝议价失败，请稍后重试');
    }
  }

  void _showChatError(Object error, {String fallback = '操作失败，请稍后重试'}) {
    if (!mounted) {
      return;
    }
    final message = error is ApiException && error.message.trim().isNotEmpty
        ? error.message.trim()
        : error.toString().trim().isNotEmpty &&
              !error.toString().contains('Exception')
        ? error.toString().trim()
        : fallback;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? _acceptedOfferFromDetail(
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> messages,
  ) {
    final direct =
        (detail['accepted_offer'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (direct['status']?.toString() == 'accepted') {
      return direct;
    }
    final active =
        (detail['active_offer'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (active['status']?.toString() == 'accepted') {
      return active;
    }
    for (final message in messages.reversed) {
      final offer =
          (message['offer'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (offer['status']?.toString() == 'accepted') {
        return offer;
      }
    }
    return null;
  }

  String _listingIdFromDetail(
    Map<String, dynamic> detail,
    Map<String, dynamic> conversation, [
    Map<String, dynamic>? offer,
  ]) {
    final itemPreview =
        (detail['item_preview'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return offer?['listing_id']?.toString() ??
        itemPreview['id']?.toString() ??
        conversation['listing_id']?.toString() ??
        '';
  }

  int? _offerAmountMinor(Map<String, dynamic> offer) {
    final amount =
        (offer['amount'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return (amount['amount_minor'] as num?)?.toInt();
  }

  String? _acceptedOfferOrderStateLabel(
    Map<String, dynamic> offer,
    Map<String, dynamic> relatedOrder,
  ) {
    final offerId = offer['id']?.toString() ?? '';
    final orderId = offer['order_id']?.toString() ?? '';
    final relatedOrderId = relatedOrder['id']?.toString() ?? '';
    final orderOfferId = relatedOrder['offer_id']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      if (relatedOrderId.isEmpty || relatedOrderId != orderId) {
        return '已生成订单';
      }
      return _chatOrderStateLabel(relatedOrder['status']?.toString());
    }
    final hasMatchedRelatedOrder =
        offerId.isNotEmpty &&
        orderOfferId.isNotEmpty &&
        offerId == orderOfferId;
    if (!hasMatchedRelatedOrder) {
      return null;
    }
    return _chatOrderStateLabel(relatedOrder['status']?.toString());
  }

  String _chatOrderStateLabel(String? status) {
    switch (status) {
      case 'pending_payment':
        return '待支付';
      case 'awaiting_shipment':
        return '待发货';
      case 'shipped':
        return '已发货';
      case 'completed':
        return '已完成';
      case 'refund_requested':
        return '退款中';
      case 'refunded':
        return '已退款';
      case 'cancelled':
        return '订单已取消';
      case 'disputed':
        return '纠纷中';
    }
    return '已生成订单';
  }

  bool _currentUserCanCheckoutAcceptedOffer(
    Map<String, dynamic> detail,
    Map<String, dynamic> conversation,
    String currentUserId,
  ) {
    if (currentUserId.isEmpty) {
      return false;
    }
    final role = conversation['role']?.toString() ?? '';
    if (role == 'buyer') {
      return true;
    }
    if (role == 'seller') {
      return false;
    }
    final buyerId = conversation['buyer_id']?.toString() ?? '';
    final sellerId = conversation['seller_id']?.toString() ?? '';
    if (buyerId.isNotEmpty || sellerId.isNotEmpty) {
      return currentUserId == buyerId;
    }

    final itemPreview =
        (detail['item_preview'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final seller =
        (itemPreview['seller'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final itemSellerId = seller['id']?.toString() ?? '';
    return itemSellerId.isEmpty || itemSellerId != currentUserId;
  }

  void _openListingDetail(Map<String, dynamic> detail) {
    final repository = widget.listingsRepository;
    final conversation =
        (detail['conversation'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final listingId = _listingIdFromDetail(detail, conversation);
    if (repository == null || listingId.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailPage(
          repository: repository,
          session: widget.session,
          listingId: listingId,
          onOpenChat: () => Navigator.of(context).pop(),
          onOpenOrder: () => _openCheckoutForListing(listingId),
          onOpenReview: () {},
        ),
      ),
    );
  }

  Future<void> _openCheckoutForListing(String listingId) async {
    final repository = widget.listingsRepository;
    if (repository == null || listingId.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPage(
          session: widget.session,
          commerceRepository: widget.repository,
          listingsRepository: repository,
          listingId: listingId,
          conversationId: widget.conversationId,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openCheckoutForOffer(
    Map<String, dynamic> detail,
    Map<String, dynamic> offer,
  ) async {
    final repository = widget.listingsRepository;
    final conversation =
        (detail['conversation'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final listingId = _listingIdFromDetail(detail, conversation, offer);
    final offerId = offer['id']?.toString() ?? '';
    final offerPriceMinor = _offerAmountMinor(offer);
    if (repository == null ||
        listingId.isEmpty ||
        offerId.isEmpty ||
        offerPriceMinor == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPage(
          session: widget.session,
          commerceRepository: widget.repository,
          listingsRepository: repository,
          listingId: listingId,
          conversationId: widget.conversationId,
          offerId: offerId,
          offerPriceMinor: offerPriceMinor,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _detailFuture,
      builder: (context, snapshot) {
        final detail = snapshot.data ?? const <String, dynamic>{};
        if (snapshot.connectionState == ConnectionState.waiting &&
            detail.isEmpty) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError && detail.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: FilledButton(onPressed: _refresh, child: const Text('重试')),
            ),
          );
        }

        final conversation =
            (detail['conversation'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final otherUser =
            (conversation['other_user'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final messages = ((detail['messages'] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(growable: false);
        final currentUserId = widget.session.user['id']?.toString() ?? '';
        final acceptedOffer = _acceptedOfferFromDetail(detail, messages);
        final relatedOrder =
            (detail['related_order'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final canCheckoutAcceptedOffer = _currentUserCanCheckoutAcceptedOffer(
          detail,
          conversation,
          currentUserId,
        );

        return Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _ConversationHeader(
                    name: otherUser['display_name']?.toString() ?? '对方',
                    subtitle: conversation['listing_title']?.toString() ?? '',
                    onBack: () => Navigator.of(context).pop(),
                    onOpenListing: widget.listingsRepository == null
                        ? null
                        : () => _openListingDetail(detail),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      itemCount: messages.isEmpty ? 1 : messages.length,
                      itemBuilder: (context, index) {
                        if (messages.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 88),
                            child: _ConversationEmptyState(),
                          );
                        }

                        final message = messages[index];
                        final isMine =
                            message['sender_id']?.toString() == currentUserId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MessageBubble(
                            message: message,
                            isMine: isMine,
                            currentUserId: currentUserId,
                            onAcceptOffer: _acceptOffer,
                            onRejectOffer: _rejectOffer,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.surfaceRaised),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (acceptedOffer != null) ...[
                          _AcceptedOfferCheckoutCard(
                            offer: acceptedOffer,
                            orderStateLabel: _acceptedOfferOrderStateLabel(
                              acceptedOffer,
                              relatedOrder,
                            ),
                            canCheckout: canCheckoutAcceptedOffer,
                            onCheckout: widget.listingsRepository == null
                                ? null
                                : () => _openCheckoutForOffer(
                                    detail,
                                    acceptedOffer,
                                  ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        ActionChip(
                          label: const Text('议价'),
                          onPressed: _sending ? null : _createOffer,
                          avatar: const Icon(
                            Icons.local_offer_outlined,
                            size: 16,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSoft,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: TextField(
                                  controller: _controller,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendText(),
                                  decoration: const InputDecoration(
                                    hintText: '发送消息',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 92,
                              child: FilledButton(
                                onPressed: _sending ? null : _sendText,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                child: Text(_sending ? '发送中' : '发送'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUser =
        (conversation['other_user'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final unreadCount = (conversation['unread_count'] as num?)?.toInt() ?? 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: CommerceCard(
          title: otherUser['display_name']?.toString() ?? '对方',
          subtitle: conversation['listing_title']?.toString() ?? '商品会话',
          action: unreadCount > 0
              ? CommercePill(
                  label: unreadCount > 99 ? '99+' : '$unreadCount',
                  backgroundColor: const Color(0xFFFFE1D9),
                  foregroundColor: AppColors.coral,
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conversation['last_message_preview']?.toString() ?? '暂无消息',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                conversation['updated_at']?.toString() ?? '',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcceptedOfferCheckoutCard extends StatelessWidget {
  const _AcceptedOfferCheckoutCard({
    required this.offer,
    required this.orderStateLabel,
    required this.canCheckout,
    required this.onCheckout,
  });

  final Map<String, dynamic> offer;
  final String? orderStateLabel;
  final bool canCheckout;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final amount =
        (offer['amount'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final amountLabel = formatMoney(amount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accentDeep.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.handshake_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '议价已成交',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  amountLabel,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.coral,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _AcceptedOfferAction(
            orderStateLabel: orderStateLabel,
            canCheckout: canCheckout,
            onCheckout: onCheckout,
          ),
        ],
      ),
    );
  }
}

class _AcceptedOfferAction extends StatelessWidget {
  const _AcceptedOfferAction({
    required this.orderStateLabel,
    required this.canCheckout,
    required this.onCheckout,
  });

  final String? orderStateLabel;
  final bool canCheckout;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final stateLabel = orderStateLabel;
    if (stateLabel != null) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(84, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(stateLabel),
      );
    }
    if (canCheckout) {
      return FilledButton(
        onPressed: onCheckout,
        style: FilledButton.styleFrom(
          minimumSize: const Size(84, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: const Text('去下单'),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '等待买家下单',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.name,
    required this.subtitle,
    required this.onBack,
    this.onOpenListing,
  });

  final String name;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onOpenListing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceRaised)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '查看商品',
            onPressed: onOpenListing,
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
        ],
      ),
    );
  }
}

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text('还没有消息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '发送第一条消息开始聊天。',
              textAlign: TextAlign.center,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.currentUserId,
    required this.onAcceptOffer,
    required this.onRejectOffer,
  });

  final Map<String, dynamic> message;
  final bool isMine;
  final String currentUserId;
  final ValueChanged<String> onAcceptOffer;
  final ValueChanged<String> onRejectOffer;

  @override
  Widget build(BuildContext context) {
    final type = message['message_type']?.toString() ?? 'text';
    if (type == 'system') {
      return Center(
        child: CommercePill(
          label: message['content_text']?.toString() ?? '系统消息',
          backgroundColor: AppColors.surfaceSoft,
          foregroundColor: AppColors.textMuted,
        ),
      );
    }

    if (type == 'offer') {
      final offer =
          (message['offer'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final proposerId = offer['proposer_id']?.toString() ?? '';
      final status = offer['status']?.toString() ?? 'active';
      final amountLabel = formatMoney(offer['amount']);
      final note = offer['note']?.toString() ?? '';
      final canRespond = status == 'active' && proposerId != currentUserId;
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: CommerceCard(
            backgroundColor: isMine
                ? const Color(0xFFFFF3D8)
                : AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proposerId == currentUserId ? '我发起了议价' : '对方向你发起了议价',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  amountLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: AppColors.coral),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    note,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 10),
                CommercePill(
                  label: _offerStatusLabel(status),
                  backgroundColor: status == 'accepted'
                      ? const Color(0xFFE8F7F0)
                      : status == 'rejected'
                      ? const Color(0xFFFFE1D9)
                      : AppColors.surfaceSoft,
                  foregroundColor: status == 'accepted'
                      ? AppColors.success
                      : status == 'rejected'
                      ? AppColors.coral
                      : AppColors.primary,
                ),
                if (canRespond) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () =>
                            onAcceptOffer(offer['id']?.toString() ?? ''),
                        child: const Text('接受'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            onRejectOffer(offer['id']?.toString() ?? ''),
                        child: const Text('拒绝'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 6),
            bottomRight: Radius.circular(isMine ? 6 : 18),
          ),
        ),
        child: Text(
          message['content_text']?.toString() ?? '',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isMine ? Colors.white : AppColors.text,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

String _offerStatusLabel(String status) {
  switch (status) {
    case 'accepted':
      return '已接受';
    case 'rejected':
      return '已拒绝';
    case 'cancelled':
      return '已失效';
    default:
      return '待处理';
  }
}
