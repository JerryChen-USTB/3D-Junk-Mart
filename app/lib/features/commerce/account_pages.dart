import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';

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
              CommerceCard(
                title: '账户余额',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _minorToMoney(account['available_minor']),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: AppColors.coral,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '冻结金额 ${_minorToMoney(account['held_minor'])}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (transactions.isEmpty)
                const CommerceEmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '还没有资金流水',
                  subtitle: '模拟支付、退款和会员升级记录会展示在这里。',
                )
              else
                ...transactions.map(
                  (tx) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CommerceCard(
                      title: _transactionTitle(
                        tx['transaction_type']?.toString(),
                      ),
                      subtitle: tx['created_at']?.toString(),
                      child: Text(
                        formatMoney(tx['amount']),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                  CommerceCard(
                    title: '当前会员',
                    child: Text(
                      currentPlan['title']?.toString() ?? '未开通',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plans.isEmpty)
                    const CommerceEmptyState(
                      icon: Icons.workspace_premium_outlined,
                      title: '暂无会员方案',
                      subtitle: '稍后再来查看新的会员权益。',
                    )
                  else
                    ...plans.map(
                      (plan) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CommerceCard(
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
    this.onOpenOrder,
    this.onOpenConversation,
    this.onOpenListing,
  });

  final AppSession session;
  final CommerceRepository repository;
  final ValueChanged<String>? onOpenOrder;
  final ValueChanged<String>? onOpenConversation;
  final ValueChanged<String>? onOpenListing;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _category = 'all';

  static const _tabs = <({String key, String label})>[
    (key: 'all', label: '全部'),
    (key: 'order', label: '订单'),
    (key: 'message', label: '消息'),
    (key: 'system', label: '系统'),
  ];

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchNotifications(widget.session.accessToken);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchNotifications(
      widget.session.accessToken,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _readAll() async {
    await widget.repository.readAllNotifications(widget.session.accessToken);
    await _refresh();
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> items) {
    if (_category == 'all') {
      return items;
    }
    return items
        .where((item) => item['category']?.toString() == _category)
        .toList(growable: false);
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isNotEmpty) {
      await widget.repository.readNotification(id, widget.session.accessToken);
    }
    if (!mounted) {
      return;
    }
    final target = item['cta_target']?.toString() ?? '';
    final entityType = item['entity_type']?.toString() ?? '';
    final entityId = item['entity_id']?.toString() ?? '';
    String resolvedType;
    String resolvedId;
    if (target.contains(':')) {
      final parts = target.split(':');
      resolvedType = parts.first;
      resolvedId = parts.length > 1 ? parts.last : entityId;
    } else {
      resolvedType = entityType;
      resolvedId = entityId;
    }

    if (resolvedType == 'order' && resolvedId.isNotEmpty) {
      widget.onOpenOrder?.call(resolvedId);
    } else if (resolvedType == 'conversation' && resolvedId.isNotEmpty) {
      widget.onOpenConversation?.call(resolvedId);
    } else if (resolvedType == 'listing' && resolvedId.isNotEmpty) {
      widget.onOpenListing?.call(resolvedId);
    }
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
          final items = _filter(
            snapshot.data ?? const <Map<String, dynamic>>[],
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    return ChoiceChip(
                      label: Text(tab.label),
                      selected: _category == tab.key,
                      onSelected: (_) {
                        setState(() {
                          _category = tab.key;
                        });
                      },
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemCount: _tabs.length,
                ),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const CommerceEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: '还没有通知',
                  subtitle: '订单进度、聊天消息和系统提醒会聚合在这里。',
                )
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _NotificationCard(
                      item: item,
                      onTap: () => _openNotification(item),
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
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _upsertAddress([Map<String, dynamic>? current]) async {
    final labelController = TextEditingController(
      text: current?['label']?.toString() ?? '家',
    );
    final recipientController = TextEditingController(
      text: current?['recipient_name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: current?['phone']?.toString() ?? '',
    );
    final regionController = TextEditingController(
      text: current?['region_code']?.toString() ?? '',
    );
    final detail1Controller = TextEditingController(
      text: current?['address_line1']?.toString() ?? '',
    );
    final detail2Controller = TextEditingController(
      text: current?['address_line2']?.toString() ?? '',
    );
    bool isDefault = current?['is_default'] == true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => AlertDialog(
            title: Text(current == null ? '新增地址' : '编辑地址'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: '地址标签'),
                  ),
                  TextField(
                    controller: recipientController,
                    decoration: const InputDecoration(labelText: '收货人'),
                  ),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '手机号'),
                  ),
                  TextField(
                    controller: regionController,
                    decoration: const InputDecoration(labelText: '地区'),
                  ),
                  TextField(
                    controller: detail1Controller,
                    decoration: const InputDecoration(labelText: '详细地址'),
                  ),
                  TextField(
                    controller: detail2Controller,
                    decoration: const InputDecoration(labelText: '补充说明'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: isDefault,
                    title: const Text('设为默认地址'),
                    onChanged: (value) {
                      setSheetState(() {
                        isDefault = value;
                      });
                    },
                  ),
                ],
              ),
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
        ),
      );
      if (confirmed != true) {
        return;
      }

      final recipient = recipientController.text.trim();
      final phone = phoneController.text.trim();
      final region = regionController.text.trim();
      final detail = detail1Controller.text.trim();
      if (recipient.isEmpty ||
          phone.isEmpty ||
          region.isEmpty ||
          detail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请填写收货人、手机号、地区和详细地址')));
        }
        return;
      }

      try {
        if (current == null) {
          await widget.repository.createAddress(
            widget.session.accessToken,
            label: labelController.text.trim(),
            recipientName: recipient,
            phone: phone,
            regionCode: region,
            addressLine1: detail,
            addressLine2: detail2Controller.text.trim(),
            isDefault: isDefault,
          );
        } else {
          await widget.repository.updateAddress(
            current['id']?.toString() ?? '',
            widget.session.accessToken,
            label: labelController.text.trim(),
            recipientName: recipient,
            phone: phone,
            regionCode: region,
            addressLine1: detail,
            addressLine2: detail2Controller.text.trim(),
            isDefault: isDefault,
          );
        }
        await _refresh();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_accountErrorMessage(error, '地址保存失败，请稍后重试')),
            ),
          );
        }
      }
    } finally {
      labelController.dispose();
      recipientController.dispose();
      phoneController.dispose();
      regionController.dispose();
      detail1Controller.dispose();
      detail2Controller.dispose();
    }
  }

  Future<void> _setDefault(Map<String, dynamic> item) async {
    try {
      await widget.repository.updateAddress(
        item['id']?.toString() ?? '',
        widget.session.accessToken,
        isDefault: true,
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_accountErrorMessage(error, '设置默认地址失败'))),
        );
      }
    }
  }

  Future<void> _deleteAddress(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除地址'),
        content: const Text('删除后该地址将无法在下单时选择。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.repository.deleteAddress(
        item['id']?.toString() ?? '',
        widget.session.accessToken,
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_accountErrorMessage(error, '删除地址失败'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('地址管理'),
        actions: [
          TextButton(onPressed: _upsertAddress, child: const Text('新增')),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                CommerceEmptyState(
                  icon: Icons.location_on_outlined,
                  title: '还没有地址',
                  subtitle: '补充收货地址后，下单时可以直接选择并保存为地址快照。',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return _AddressCard(
                item: item,
                onEdit: () => _upsertAddress(item),
                onDelete: () => _deleteAddress(item),
                onSetDefault: item['is_default'] == true
                    ? null
                    : () => _setDefault(item),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = item['read_state']?.toString() != 'read';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: CommerceCard(
          title: item['title']?.toString() ?? '通知',
          subtitle: item['created_at']?.toString(),
          action: unread
              ? const CommercePill(
                  label: '未读',
                  backgroundColor: Color(0xFFFFF3D8),
                  foregroundColor: AppColors.warning,
                )
              : const CommercePill(
                  label: '已读',
                  backgroundColor: Color(0xFFE8F7F0),
                  foregroundColor: AppColors.success,
                ),
          backgroundColor: unread ? const Color(0xFFFFFCF2) : AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['body']?.toString() ?? '',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CommercePill(
                    label: _categoryLabel(item['category']?.toString()),
                    backgroundColor: AppColors.surfaceSoft,
                    foregroundColor: AppColors.primary,
                  ),
                  const Spacer(),
                  Text(
                    item['cta_action']?.toString() ?? '查看详情',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: AppColors.ocean),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppColors.ocean,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;

  @override
  Widget build(BuildContext context) {
    return CommerceCard(
      title: item['recipient_name']?.toString() ?? '收货人',
      subtitle: item['phone']?.toString(),
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if ((item['label']?.toString() ?? '').isNotEmpty)
            CommercePill(
              label: item['label']!.toString(),
              backgroundColor: AppColors.surfaceRaised,
              foregroundColor: AppColors.primary,
            ),
          if (item['is_default'] == true)
            const CommercePill(
              label: '默认地址',
              backgroundColor: Color(0xFFE8F7F0),
              foregroundColor: AppColors.success,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['full_address']?.toString() ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onEdit, child: const Text('编辑')),
              if (onSetDefault != null)
                OutlinedButton(
                  onPressed: onSetDefault,
                  child: const Text('设为默认'),
                ),
              OutlinedButton(onPressed: onDelete, child: const Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

String _minorToMoney(Object? amountMinor) {
  final amount = (amountMinor as num?)?.toInt() ?? 0;
  return formatMoney(<String, dynamic>{
    'amount_minor': amount,
    'currency': 'CNY',
  });
}

String _accountErrorMessage(Object error, String fallback) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  return fallback;
}

String _transactionTitle(String? type) {
  switch (type) {
    case 'purchase':
      return '模拟支付';
    case 'refund':
      return '退款到账';
    case 'incoming_hold':
      return '卖家待结算';
    case 'refund_out':
      return '卖家退款支出';
    case 'membership':
      return '会员升级';
    default:
      return '资金变动';
  }
}

String _categoryLabel(String? category) {
  switch (category) {
    case 'order':
      return '订单';
    case 'message':
      return '消息';
    default:
      return '系统';
  }
}
