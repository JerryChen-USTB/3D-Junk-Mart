import 'package:flutter/material.dart';

import '../../core/commerce/commerce_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.repository,
    required this.session,
  });

  final CommerceRepository repository;
  final AppSession session;

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
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
                  Text('消息', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    '和买家、卖家持续沟通，订单状态变化也会同步到这里。',
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
                    const _MessagesInfoCard(
                      icon: Icons.cloud_off_rounded,
                      title: '消息加载失败',
                      subtitle: '请下拉刷新后重试。',
                    )
                  else if (conversations.isEmpty)
                    const _MessagesInfoCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: '还没有会话',
                      subtitle: '从商品详情发起联系后，会话会显示在这里。',
                    )
                  else
                    ...conversations.map(
                      (conversation) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ConversationTile(
                          conversation: conversation,
                          repository: widget.repository,
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

class ConversationDetailPage extends StatefulWidget {
  const ConversationDetailPage({
    super.key,
    required this.repository,
    required this.session,
    required this.conversationId,
  });

  final CommerceRepository repository;
  final AppSession session;
  final String conversationId;

  @override
  State<ConversationDetailPage> createState() => _ConversationDetailPageState();
}

class _ConversationDetailPageState extends State<ConversationDetailPage> {
  final TextEditingController _controller = TextEditingController();
  late Future<Map<String, dynamic>> _detailFuture;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _load();
  }

  @override
  void dispose() {
    _controller.dispose();
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
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
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
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _detailFuture,
          builder: (context, snapshot) {
            final detail = snapshot.data ?? const <String, dynamic>{};
            final conversation =
                (detail['conversation'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final otherUser =
                (conversation['other_user'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final itemPreview =
                (detail['item_preview'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final safetyBanner =
                (detail['safety_banner'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            final messages =
                ((detail['messages'] as List?) ?? const <Object?>[])
                    .whereType<Map>()
                    .map((item) => item.cast<String, dynamic>())
                    .toList(growable: false);

            if (snapshot.connectionState == ConnectionState.waiting &&
                detail.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && detail.isEmpty) {
              return Center(
                child: FilledButton(
                  onPressed: () {
                    _refresh();
                  },
                  child: const Text('重试'),
                ),
              );
            }

            final otherName = otherUser['display_name']?.toString() ?? '对方';
            final otherAvatarUrl = widget.repository.resolveUrl(
              otherUser['avatar_url']?.toString(),
            );
            final itemTitle = itemPreview['title']?.toString() ?? '商品会话';
            final itemSubtitle = itemPreview['subtitle']?.toString() ?? '';
            final itemLocation = itemPreview['location']?.toString() ?? '';
            final itemPrice = _readPrice(itemPreview['price']);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _ConversationHeader(
                    name: otherName,
                    avatarUrl: otherAvatarUrl,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                if (itemPreview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _ConversationItemCard(
                      title: itemTitle,
                      subtitle: itemSubtitle,
                      location: itemLocation,
                      price: itemPrice,
                    ),
                  ),
                if (safetyBanner.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _SafetyBanner(
                      title: safetyBanner['title']?.toString() ?? '交易提醒',
                      body: safetyBanner['body']?.toString() ?? '',
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: messages.isEmpty ? 1 : messages.length,
                      itemBuilder: (context, index) {
                        if (messages.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: _MessagesInfoCard(
                              icon: Icons.chat_outlined,
                              title: '还没有消息',
                              subtitle: '先发送一句问候，和对方开始沟通。',
                            ),
                          );
                        }

                        final message = messages[index];
                        final isMine =
                            message['sender_id']?.toString() ==
                            widget.session.user['id']?.toString();
                        return _MessageBubble(message: message, isMine: isMine);
                      },
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: '输入消息',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _sending ? null : _send,
                          child: Text(_sending ? '发送中' : '发送'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _readPrice(Object? rawPrice) {
    if (rawPrice is! Map) {
      return '面议';
    }
    final price = rawPrice.cast<String, dynamic>();
    final amountMinor = (price['amount_minor'] as num?)?.toInt();
    final currency = price['currency']?.toString().toUpperCase() ?? '';
    if (amountMinor == null) {
      return '面议';
    }
    final symbol = switch (currency) {
      'CNY' => '￥',
      'USD' => '\$',
      'EUR' => '€',
      _ => currency.isEmpty ? '' : '$currency ',
    };
    final amount = amountMinor / 100;
    final formatted = amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '$symbol$formatted';
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.name,
    required this.avatarUrl,
    required this.onBack,
  });

  final String name;
  final String? avatarUrl;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            splashRadius: 22,
          ),
          const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _UserAvatarFallback(name: name),
                  )
                : _UserAvatarFallback(name: name),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '会话详情',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationItemCard extends StatelessWidget {
  const _ConversationItemCard({
    required this.title,
    required this.subtitle,
    required this.location,
    required this.price,
  });

  final String title;
  final String subtitle;
  final String location;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.inventory_2_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      price,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: AppColors.coral),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final Map<String, dynamic> message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final createdAt = message['created_at']?.toString() ?? '';
    final content = message['content_text']?.toString() ?? '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              content.isEmpty ? '暂不支持的消息类型' : content,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _formatTimestamp(createdAt),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) {
      return raw;
    }
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.month}-${date.day} ${date.hour}:$minute';
  }
}

class _UserAvatarFallback extends StatelessWidget {
  const _UserAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first : '聊',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.repository,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final CommerceRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUser =
        (conversation['other_user'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final unreadCount = (conversation['unread_count'] as num?)?.toInt() ?? 0;
    final avatarUrl = repository.resolveUrl(
      otherUser['avatar_url']?.toString(),
    );
    final displayName = otherUser['display_name']?.toString() ?? '对方';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: avatarUrl != null
                    ? Image.network(
                        avatarUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _UserAvatarFallback(name: displayName),
                      )
                    : _UserAvatarFallback(name: displayName),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      conversation['last_message_preview']?.toString() ??
                          '暂无消息',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesInfoCard extends StatelessWidget {
  const _MessagesInfoCard({
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
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
