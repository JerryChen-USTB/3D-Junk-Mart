import 'package:flutter/material.dart';

import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final CommerceRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('钱包')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: repository.fetchWallet(session.accessToken),
        builder: (context, snapshot) {
          final data = snapshot.data ?? const <String, dynamic>{};
          final account =
              (data['account'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final transactions =
              ((data['transactions'] as List?) ?? const <Object?>[])
                  .whereType<Map>()
                  .map((item) => item.cast<String, dynamic>())
                  .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: '余额',
                child: Text(
                  '可用 ${_minorToMoney(account['available_minor'])} / 冻结 ${_minorToMoney(account['held_minor'])}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              if (transactions.isEmpty)
                const _EmptyCard(
                  title: '还没有流水',
                  subtitle: '充值、退款和会员升级记录会显示在这里。',
                )
              else
                ...transactions.map(
                  (tx) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SectionCard(
                      title: _transactionTitle(
                        tx['transaction_type']?.toString(),
                      ),
                      subtitle: tx['created_at']?.toString(),
                      child: Text(formatMoney(tx['amount'])),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MembershipPage extends StatelessWidget {
  const MembershipPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final CommerceRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('会员中心')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.fetchMembershipPlans(),
        builder: (context, plansSnapshot) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: repository.fetchMembershipCurrent(session.accessToken),
            builder: (context, currentSnapshot) {
              final plans =
                  plansSnapshot.data ?? const <Map<String, dynamic>>[];
              final current = currentSnapshot.data ?? const <String, dynamic>{};
              final currentPlan =
                  (current['plan'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{};

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    title: '当前会员',
                    child: Text(
                      currentPlan['title']?.toString() ?? '未开通',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plans.isEmpty)
                    const _EmptyCard(
                      title: '暂无可用会员方案',
                      subtitle: '稍后再来查看新的会员权益。',
                    )
                  else
                    ...plans.map(
                      (plan) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SectionCard(
                          title: plan['title']?.toString() ?? '会员方案',
                          subtitle: plan['description']?.toString(),
                          action: FilledButton(
                            onPressed: () async {
                              await repository.upgradeMembership(
                                session.accessToken,
                                planKey: plan['plan_key']?.toString() ?? '',
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text('升级'),
                          ),
                          child: Text(
                            formatMoney(plan['price']),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final CommerceRepository repository;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchNotifications(widget.session.accessToken);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchNotifications(
      widget.session.accessToken,
    );
    setState(() => _future = future);
    await future;
  }

  Future<void> _readAll() async {
    await widget.repository.readAllNotifications(widget.session.accessToken);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('通知'),
        actions: [TextButton(onPressed: _readAll, child: const Text('全部已读'))],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(child: Text('还没有通知'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return _SectionCard(
                title: item['title']?.toString() ?? '通知',
                subtitle: item['created_at']?.toString(),
                child: Text(item['body']?.toString() ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}

class AddressesPage extends StatefulWidget {
  const AddressesPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final CommerceRepository repository;

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchAddresses(widget.session.accessToken);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchAddresses(widget.session.accessToken);
    setState(() => _future = future);
    await future;
  }

  Future<void> _createAddress() async {
    final recipientController = TextEditingController();
    final phoneController = TextEditingController();
    final regionController = TextEditingController(text: '上海');
    final detailController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新增地址'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: recipientController,
                decoration: const InputDecoration(labelText: '收件人'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: '手机号'),
              ),
              TextField(
                controller: regionController,
                decoration: const InputDecoration(labelText: '地区'),
              ),
              TextField(
                controller: detailController,
                decoration: const InputDecoration(labelText: '详细地址'),
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
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }

      await widget.repository.createAddress(
        widget.session.accessToken,
        recipientName: recipientController.text.trim(),
        phone: phoneController.text.trim(),
        regionCode: regionController.text.trim(),
        addressLine1: detailController.text.trim(),
        isDefault: true,
      );
      await _refresh();
    } finally {
      recipientController.dispose();
      phoneController.dispose();
      regionController.dispose();
      detailController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('地址管理'),
        actions: [
          TextButton(onPressed: _createAddress, child: const Text('新增')),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(child: Text('还没有地址'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final line2 = item['address_line2']?.toString() ?? '';
              return _SectionCard(
                title: item['recipient_name']?.toString() ?? '收件人',
                subtitle: item['phone']?.toString(),
                child: Text(
                  '${item['region_code'] ?? ''} ${item['address_line1'] ?? ''} ${line2.trim()}'
                      .trim(),
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
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

String _minorToMoney(Object? raw) {
  final value = (raw as num?)?.toInt() ?? 0;
  return '￥${(value / 100).toStringAsFixed(2)}';
}

String _transactionTitle(String? type) {
  switch (type) {
    case 'membership_upgrade':
      return '会员升级';
    case 'refund':
      return '退款';
    case 'purchase':
      return '支付';
    default:
      return '资金变动';
  }
}
