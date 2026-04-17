import 'package:flutter/material.dart';

import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import 'review_pages.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final CommerceRepository repository;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = widget.repository.fetchOrders(widget.session.accessToken);
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchOrders(widget.session.accessToken);
    setState(() {
      _ordersFuture = future;
    });
    await future;
  }

  void _openOrder(String orderId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailPage(
              session: widget.session,
              repository: widget.repository,
              orderId: orderId,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('订单')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            final orders = snapshot.data ?? const <Map<String, dynamic>>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                orders.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (orders.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('还没有订单')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final order = orders[index];
                final item =
                    (order['item_snapshot'] as Map?)?.cast<String, dynamic>() ??
                    const <String, dynamic>{};
                final totals =
                    (order['totals'] as Map?)?.cast<String, dynamic>() ??
                    const <String, dynamic>{};
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openOrder(order['id']?.toString() ?? ''),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['title']?.toString() ?? '订单商品',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Text(_statusLabel(order['status']?.toString())),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('总价 ${formatMoney(totals['total'])}'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.session,
    required this.repository,
    required this.orderId,
  });

  final AppSession session;
  final CommerceRepository repository;
  final String orderId;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchOrderDetail(
      widget.orderId,
      widget.session.accessToken,
    );
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchOrderDetail(
      widget.orderId,
      widget.session.accessToken,
    );
    setState(() => _future = future);
    await future;
  }

  Future<void> _shipOrder() async {
    final carrierController = TextEditingController(text: '顺丰');
    final trackingController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('录入物流'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: carrierController,
                decoration: const InputDecoration(labelText: '物流公司'),
              ),
              TextField(
                controller: trackingController,
                decoration: const InputDecoration(labelText: '运单号'),
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
              child: const Text('发货'),
            ),
          ],
        ),
      );
      if (confirmed != true || _busy) {
        return;
      }
      setState(() => _busy = true);
      await widget.repository.shipOrder(
        widget.orderId,
        widget.session.accessToken,
        carrierName: carrierController.text.trim(),
        trackingNo: trackingController.text.trim(),
      );
      await _refresh();
    } finally {
      carrierController.dispose();
      trackingController.dispose();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmReceipt() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.confirmReceipt(
        widget.orderId,
        widget.session.accessToken,
      );
      await _refresh();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelOrder() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.cancelOrder(
        widget.orderId,
        widget.session.accessToken,
      );
      await _refresh();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openReview() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ReviewPage(
              session: widget.session,
              repository: widget.repository,
              orderId: widget.orderId,
            ),
          ),
        )
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('订单详情')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final detail = snapshot.data ?? const <String, dynamic>{};
          if (snapshot.connectionState == ConnectionState.waiting &&
              detail.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || detail.isEmpty) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  _refresh();
                },
                child: const Text('重试'),
              ),
            );
          }

          final order =
              (detail['order'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final buyer =
              (order['buyer'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final seller =
              (order['seller'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final item =
              (order['item_snapshot'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final totals =
              (order['totals'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final receipt =
              (detail['receipt'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final shipment =
              (receipt['shipment'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final currentUserId = widget.session.user['id']?.toString();
          final isBuyer = buyer['id']?.toString() == currentUserId;
          final isSeller = seller['id']?.toString() == currentUserId;
          final timeline = ((detail['timeline'] as List?) ?? const <Object?>[])
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _SectionCard(
                title: item['title']?.toString() ?? '订单商品',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('状态：${_statusLabel(order['status']?.toString())}'),
                    const SizedBox(height: 8),
                    Text('总价：${formatMoney(totals['total'])}'),
                    if ((shipment['tracking_no']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '物流：${shipment['carrier_name'] ?? ''} / ${shipment['tracking_no'] ?? ''}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '时间线',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: timeline.isEmpty
                      ? const [Text('暂无状态更新')]
                      : timeline
                            .map(
                              (event) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '${_statusLabel(event['status']?.toString())}  ${event['event_note'] ?? ''}',
                                ),
                              ),
                            )
                            .toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (isSeller &&
                      (order['status'] == 'paid' ||
                          order['status'] == 'reserved'))
                    FilledButton(
                      onPressed: _busy ? null : _shipOrder,
                      child: const Text('卖家发货'),
                    ),
                  if (isBuyer && order['can_confirm_receipt'] == true)
                    FilledButton(
                      onPressed: _busy ? null : _confirmReceipt,
                      child: const Text('确认收货'),
                    ),
                  if (order['status'] == 'paid' ||
                      order['status'] == 'reserved')
                    OutlinedButton(
                      onPressed: _busy ? null : _cancelOrder,
                      child: const Text('取消订单'),
                    ),
                  if (isBuyer && order['status'] == 'completed')
                    OutlinedButton(
                      onPressed: _openReview,
                      child: const Text('去评价'),
                    ),
                ],
              ),
            ],
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

String _statusLabel(String? raw) {
  switch (raw) {
    case 'paid':
      return '已支付';
    case 'reserved':
      return '已锁定';
    case 'shipped':
      return '已发货';
    case 'completed':
      return '已完成';
    case 'cancelled':
      return '已取消';
    default:
      return raw?.isNotEmpty == true ? raw! : '处理中';
  }
}
