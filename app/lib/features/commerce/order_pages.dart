import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
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
  String _statusFilter = 'all';

  static const _tabs = <({String key, String label})>[
    (key: 'all', label: '全部'),
    (key: 'pending_payment', label: '待支付'),
    (key: 'awaiting_shipment', label: '待发货'),
    (key: 'shipped', label: '待收货'),
    (key: 'completed', label: '已完成'),
    (key: 'aftersale', label: '售后'),
  ];

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

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> orders) {
    if (_statusFilter == 'all') {
      return orders;
    }
    if (_statusFilter == 'aftersale') {
      return orders
          .where(
            (order) =>
                (order['aftersale_status']?.toString() ?? 'none') != 'none',
          )
          .toList(growable: false);
    }
    return orders
        .where((order) => order['status']?.toString() == _statusFilter)
        .toList(growable: false);
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
      appBar: AppBar(title: const Text('订单中心')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            final orders = snapshot.data ?? const <Map<String, dynamic>>[];
            final visibleOrders = _applyFilter(orders);
            if (snapshot.connectionState == ConnectionState.waiting &&
                orders.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const CommerceStatusBanner(
                  title: '交易中心',
                  subtitle: '在这里查看待支付、待发货、待收货与售后进度。',
                  tone: 'neutral',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final tab = _tabs[index];
                      final selected = _statusFilter == tab.key;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(tab.label),
                        onSelected: (_) {
                          setState(() {
                            _statusFilter = tab.key;
                          });
                        },
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemCount: _tabs.length,
                  ),
                ),
                const SizedBox(height: 16),
                if (visibleOrders.isEmpty)
                  const CommerceEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: '还没有订单',
                    subtitle: '完成下单后，订单会按状态分组展示在这里。',
                  )
                else
                  ...visibleOrders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OrderListCard(
                        order: order,
                        onTap: () => _openOrder(order['id']?.toString() ?? ''),
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
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _handleAction(String key, Map<String, dynamic> detail) async {
    if (_busy) {
      return;
    }
    switch (key) {
      case 'review':
        _openReview();
        return;
      case 'track_shipment':
        final shipment =
            ((detail['receipt'] as Map?)?.cast<String, dynamic>()['shipment']
                    as Map?)
                ?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final trackingNo = shipment['tracking_no']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trackingNo.isEmpty ? '当前暂无物流单号' : '物流单号：$trackingNo'),
          ),
        );
        return;
      case 'contact_peer':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请前往消息页联系对方')));
        return;
    }

    setState(() => _busy = true);
    String? successMessage;
    try {
      switch (key) {
        case 'mock_pay':
          await widget.repository.mockPayOrder(
            widget.orderId,
            widget.session.accessToken,
          );
          successMessage = '支付已确认，订单进入待发货';
          break;
        case 'ship_order':
          final shipInfo = await _collectShipInfo();
          if (shipInfo == null) {
            return;
          }
          await widget.repository.shipOrder(
            widget.orderId,
            widget.session.accessToken,
            carrierName: shipInfo.$1,
            trackingNo: shipInfo.$2,
          );
          successMessage = '发货信息已提交';
          break;
        case 'confirm_receipt':
          await widget.repository.confirmReceipt(
            widget.orderId,
            widget.session.accessToken,
          );
          successMessage = '已确认收货，交易完成';
          break;
        case 'cancel_order':
          final confirmed = await _confirm('确认取消订单？');
          if (confirmed != true) {
            return;
          }
          await widget.repository.cancelOrder(
            widget.orderId,
            widget.session.accessToken,
          );
          successMessage = '订单已取消';
          break;
        case 'request_refund':
          final reason = await _collectText(
            title: '申请退款',
            hintText: '填写退款原因，卖家会在订单页处理',
          );
          if (reason == null || reason.trim().isEmpty) {
            return;
          }
          await widget.repository.requestRefund(
            widget.orderId,
            widget.session.accessToken,
            reason: reason.trim(),
          );
          successMessage = '退款申请已提交';
          break;
        case 'approve_refund':
          await widget.repository.approveRefund(
            widget.orderId,
            widget.session.accessToken,
            resolutionNote: '卖家同意退款',
          );
          successMessage = '已同意退款';
          break;
        case 'reject_refund':
          final note = await _collectText(
            title: '拒绝退款',
            hintText: '填写拒绝原因，订单将进入纠纷处理中',
          );
          if (note == null || note.trim().isEmpty) {
            return;
          }
          await widget.repository.rejectRefund(
            widget.orderId,
            widget.session.accessToken,
            resolutionNote: note.trim(),
          );
          successMessage = '已拒绝退款，订单进入纠纷';
          break;
        case 'open_dispute':
          final reason = await _collectText(
            title: '发起纠纷',
            hintText: '补充争议原因，平台将进入介入状态',
          );
          if (reason == null || reason.trim().isEmpty) {
            return;
          }
          await widget.repository.disputeOrder(
            widget.orderId,
            widget.session.accessToken,
            reason: reason.trim(),
          );
          successMessage = '已发起纠纷';
          break;
      }
      await _refresh();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_actionErrorMessage(key, error))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _actionErrorMessage(String key, ApiException error) {
    if (key == 'cancel_order' && error.statusCode == 409) {
      return '已支付订单不能直接取消，请申请退款。';
    }
    if (error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    return '操作失败，请稍后重试';
  }

  Future<(String, String)?> _collectShipInfo() async {
    return showDialog<(String, String)?>(
      context: context,
      builder: (context) => const _ShipInfoDialog(),
    );
  }

  Future<bool?> _confirm(String title) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<String?> _collectText({
    required String title,
    required String hintText,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextInputDialog(title: title, hintText: hintText),
    );
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
              child: FilledButton(onPressed: _refresh, child: const Text('重试')),
            );
          }

          final order =
              (detail['order'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final item =
              (order['item_snapshot'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final buyer =
              (order['buyer'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final seller =
              (order['seller'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final totals =
              (order['totals'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final address =
              (order['address'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final receipt =
              (detail['receipt'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final payment =
              (receipt['payment'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final shipment =
              (receipt['shipment'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final statusCard =
              (detail['status_card'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final aftersale =
              (detail['aftersale'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final timeline = ((detail['timeline'] as List?) ?? const <Object?>[])
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
            children: [
              CommerceStatusBanner(
                title:
                    statusCard['title']?.toString() ??
                    order['status_label']?.toString() ??
                    '订单状态',
                subtitle: statusCard['subtitle']?.toString() ?? '',
                tone: statusCard['tone']?.toString() ?? 'neutral',
              ),
              const SizedBox(height: 16),
              CommerceCard(
                title: '订单信息',
                subtitle:
                    '订单号 ${order['order_no']?.toString() ?? widget.orderId}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OrderSummaryRow(
                      item: item,
                      totalLabel: formatMoney(totals['total']),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CommercePill(
                          label: order['status_label']?.toString() ?? '处理中',
                          backgroundColor: AppColors.surfaceSoft,
                          foregroundColor: AppColors.primary,
                        ),
                        CommercePill(
                          label:
                              '支付 ${_paymentStatusLabel(order['payment_status'])}',
                          backgroundColor: const Color(0xFFE8F7F0),
                          foregroundColor: AppColors.success,
                        ),
                        CommercePill(
                          label:
                              '履约 ${_shippingStatusLabel(order['shipping_status'])}',
                          backgroundColor: const Color(0xFFE8EEF7),
                          foregroundColor: AppColors.ocean,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommerceCard(
                title: '买卖双方',
                child: Column(
                  children: [
                    _PartyRow(
                      icon: Icons.shopping_bag_outlined,
                      title: '买家',
                      name: buyer['display_name']?.toString() ?? '买家',
                    ),
                    const Divider(height: 24),
                    _PartyRow(
                      icon: Icons.storefront_outlined,
                      title: '卖家',
                      name: seller['display_name']?.toString() ?? '卖家',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommerceCard(
                title: '收货信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${address['receiver_name'] ?? ''}  ${address['phone'] ?? ''}'
                          .trim(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${address['region'] ?? ''} ${address['detail'] ?? ''} ${address['detail2'] ?? ''}'
                          .trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommerceCard(
                title: '支付信息',
                child: Column(
                  children: [
                    CommerceKeyValueRow(
                      label: '支付方式',
                      value: payment['payment_method']?.toString() ?? 'mock',
                    ),
                    CommerceKeyValueRow(
                      label: '支付状态',
                      value: _paymentStatusLabel(payment['status']),
                    ),
                    CommerceKeyValueRow(
                      label: '商品金额',
                      value: formatMoney(totals['subtotal']),
                    ),
                    CommerceKeyValueRow(
                      label: '运费',
                      value: formatMoney(totals['shipping']),
                    ),
                    CommerceKeyValueRow(
                      label: '优惠',
                      value: formatMoney(totals['discount']),
                    ),
                    const Divider(height: 24),
                    CommerceKeyValueRow(
                      label: '实付款',
                      value: formatMoney(totals['total']),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CommerceCard(
                title: '物流信息',
                child: shipment['id'] == null
                    ? const Text('当前暂无物流信息')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CommerceKeyValueRow(
                            label: '物流公司',
                            value: shipment['carrier_name']?.toString() ?? '-',
                          ),
                          CommerceKeyValueRow(
                            label: '运单号',
                            value: shipment['tracking_no']?.toString() ?? '-',
                          ),
                          if (((shipment['events'] as List?) ?? const [])
                              .isNotEmpty) ...[
                            const Divider(height: 24),
                            ...(((shipment['events'] as List?) ?? const [])
                                .whereType<Map>()
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _TimelineBullet(
                                      title: _shipmentEventLabel(
                                        item['event_text'],
                                      ),
                                      subtitle: _formatOrderDateTime(
                                        item['occurred_at'],
                                      ),
                                    ),
                                  ),
                                )),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              if ((aftersale['status']?.toString() ?? 'none') != 'none')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CommerceCard(
                    title: '售后处理',
                    child: Column(
                      children: [
                        CommerceKeyValueRow(
                          label: '售后状态',
                          value: _aftersaleStatusLabel(aftersale['status']),
                        ),
                        if ((aftersale['reason']?.toString() ?? '').isNotEmpty)
                          CommerceKeyValueRow(
                            label: '原因',
                            value: aftersale['reason']?.toString() ?? '',
                          ),
                        if ((aftersale['resolution_note']?.toString() ?? '')
                            .isNotEmpty)
                          CommerceKeyValueRow(
                            label: '处理说明',
                            value:
                                aftersale['resolution_note']?.toString() ?? '',
                          ),
                      ],
                    ),
                  ),
                ),
              CommerceCard(
                title: '时间轴',
                child: timeline.isEmpty
                    ? const Text('暂无时间轴记录')
                    : Column(
                        children: timeline
                            .map(
                              (event) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _TimelineBullet(
                                  title: _timelineTitle(event),
                                  subtitle: _timelineSubtitle(event),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          if (detail == null) {
            return const SizedBox.shrink();
          }
          final actions = ((detail['action_bar'] as List?) ?? const <Object?>[])
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .where((item) => item['enabled'] != false)
              .where((item) => _actionMatchesOrderState(item, detail))
              .toList(growable: false);
          if (actions.isEmpty) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              decoration: const BoxDecoration(color: AppColors.surface),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions
                    .map((action) {
                      final key = action['key']?.toString() ?? '';
                      final primary = action['style']?.toString() == 'primary';
                      final title = action['title']?.toString() ?? '操作';
                      if (primary) {
                        return FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _handleAction(key, detail),
                          child: Text(title),
                        );
                      }
                      return OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _handleAction(key, detail),
                        child: Text(title),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShipInfoDialog extends StatefulWidget {
  const _ShipInfoDialog();

  @override
  State<_ShipInfoDialog> createState() => _ShipInfoDialogState();
}

class _ShipInfoDialogState extends State<_ShipInfoDialog> {
  final TextEditingController _carrierController = TextEditingController(
    text: '顺丰',
  );
  final TextEditingController _trackingController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _carrierController.dispose();
    _trackingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('录入物流'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _carrierController,
            decoration: const InputDecoration(labelText: '物流公司'),
          ),
          TextField(
            controller: _trackingController,
            decoration: const InputDecoration(labelText: '运单号'),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final carrier = _carrierController.text.trim();
            final trackingNo = _trackingController.text.trim();
            if (carrier.isEmpty || trackingNo.isEmpty) {
              setState(() => _errorText = '请填写物流公司和运单号');
              return;
            }
            Navigator.of(context).pop((carrier, trackingNo));
          },
          child: const Text('发货'),
        ),
      ],
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.hintText});

  final String title;
  final String hintText;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('提交'),
        ),
      ],
    );
  }
}

String _paymentStatusLabel(Object? value) {
  switch (value?.toString()) {
    case 'pending':
      return '待支付';
    case 'paid':
      return '已支付';
    case 'refunding':
      return '退款中';
    case 'refunded':
      return '已退款';
  }
  return value?.toString().isNotEmpty == true ? value.toString() : '-';
}

bool _actionMatchesOrderState(
  Map<String, dynamic> action,
  Map<String, dynamic> detail,
) {
  final key = action['key']?.toString() ?? '';
  final order =
      (detail['order'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final status = order['status']?.toString() ?? '';
  switch (key) {
    case 'mock_pay':
    case 'cancel_order':
      return status == 'pending_payment';
    case 'request_refund':
      return status == 'awaiting_shipment' || status == 'shipped';
    case 'ship_order':
      return status == 'awaiting_shipment';
    case 'approve_refund':
    case 'reject_refund':
      return status == 'refund_requested';
    case 'track_shipment':
    case 'confirm_receipt':
      return status == 'shipped';
    case 'review':
      return status == 'completed';
  }
  return true;
}

String _shippingStatusLabel(Object? value) {
  switch (value?.toString()) {
    case 'pending':
      return '待处理';
    case 'awaiting_shipment':
      return '待发货';
    case 'shipped':
      return '已发货';
    case 'delivered':
      return '已送达';
    case 'cancelled':
      return '已取消';
  }
  return value?.toString().isNotEmpty == true ? value.toString() : '-';
}

String _aftersaleStatusLabel(Object? value) {
  switch (value?.toString()) {
    case 'none':
      return '无售后';
    case 'refund_requested':
      return '退款申请中';
    case 'refunded':
      return '已退款';
    case 'disputed':
      return '纠纷处理中';
  }
  return value?.toString().isNotEmpty == true ? value.toString() : '-';
}

String _timelineTitle(Map<String, dynamic> event) {
  switch (event['status']?.toString()) {
    case 'pending_payment':
      return '订单已创建';
    case 'awaiting_shipment':
      return '支付成功';
    case 'shipped':
      return '卖家已发货';
    case 'completed':
      return '交易完成';
    case 'cancelled':
      return '订单已取消';
    case 'refund_requested':
      return '已申请退款';
    case 'refunded':
      return '退款完成';
    case 'disputed':
      return '纠纷处理中';
    case 'reviewed':
      return '已评价';
  }
  return '订单状态更新';
}

String _timelineSubtitle(Map<String, dynamic> event) {
  final timeLabel = _formatOrderDateTime(event['occurred_at']);
  final note = _timelineNote(event);
  if (note.isEmpty) {
    return timeLabel;
  }
  if (timeLabel.isEmpty) {
    return note;
  }
  return '$timeLabel  $note';
}

String _timelineNote(Map<String, dynamic> event) {
  final status = event['status']?.toString() ?? '';
  final note = event['event_note']?.toString().trim() ?? '';
  switch (status) {
    case 'pending_payment':
      return '订单已提交，等待完成模拟支付。';
    case 'awaiting_shipment':
      return '模拟支付已完成，等待卖家发货。';
    case 'shipped':
      return '卖家已填写物流信息。';
    case 'completed':
      return '买家已确认收货，交易完成。';
    case 'cancelled':
      return '订单已取消，商品恢复可购买。';
    case 'refund_requested':
      if (note.isEmpty ||
          note == 'Buyer requested a refund.' ||
          note == '买家已提交退款申请，等待卖家处理。') {
        return '买家已提交退款申请，等待卖家处理。';
      }
      return '退款原因：$note';
    case 'refunded':
      return '卖家同意退款，款项已退回买家账户。';
    case 'disputed':
      if (note.isEmpty ||
          note == 'Seller rejected the refund request.' ||
          note == '卖家拒绝退款，订单进入纠纷处理。') {
        return '卖家拒绝退款，订单进入纠纷处理。';
      }
      return '纠纷原因：$note';
    case 'reviewed':
      return '买家已完成评价。';
  }
  return _eventNoteLabel(note);
}

String _eventNoteLabel(String note) {
  switch (note) {
    case 'Order created and waiting for mock payment.':
      return '订单已提交，等待完成模拟支付。';
    case 'Mock payment confirmed.':
      return '模拟支付已完成，等待卖家发货。';
    case 'Seller shipped the order.':
      return '卖家已发货，物流信息已生成。';
    case 'Buyer confirmed receipt.':
      return '买家已确认收货，交易完成。';
    case 'Order cancelled before shipment.':
      return '订单已取消，商品恢复可购买。';
    case 'Seller approved the refund.':
      return '卖家同意退款，款项已退回买家账户。';
    case 'Buyer submitted a review.':
      return '买家已完成评价。';
  }
  return note;
}

String _shipmentEventLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  switch (text) {
    case 'Seller marked the order as shipped.':
      return '卖家已填写物流信息';
    case 'Buyer confirmed receipt.':
      return '买家已确认收货';
  }
  return text.isNotEmpty ? text : '物流状态更新';
}

String _formatOrderDateTime(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  return '${local.year}年${_twoDigits(local.month)}月'
      '${_twoDigits(local.day)}日 ${_twoDigits(local.hour)}:'
      '${_twoDigits(local.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _OrderListCard extends StatelessWidget {
  const _OrderListCard({required this.order, required this.onTap});

  final Map<String, dynamic> order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item =
        (order['item_snapshot'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final totals =
        (order['totals'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final address =
        (order['address'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: CommerceCard(
          title: item['title']?.toString() ?? '订单商品',
          subtitle:
              '订单号 ${order['order_no']?.toString() ?? order['id']?.toString() ?? ''}',
          action: CommercePill(
            label: order['status_label']?.toString() ?? '处理中',
            backgroundColor: const Color(0xFFFFF3D8),
            foregroundColor: AppColors.warning,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((order['role']?.toString() ?? '').isNotEmpty)
                    CommercePill(
                      label: order['role']?.toString() == 'seller'
                          ? '卖家视角'
                          : '买家视角',
                    ),
                  CommercePill(
                    label: '支付 ${_paymentStatusLabel(order['payment_status'])}',
                    backgroundColor: const Color(0xFFE8F7F0),
                    foregroundColor: AppColors.success,
                  ),
                  CommercePill(
                    label:
                        '售后 ${_aftersaleStatusLabel(order['aftersale_status'])}',
                    backgroundColor: const Color(0xFFE8EEF7),
                    foregroundColor: AppColors.ocean,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '实付款 ${formatMoney(totals['total'])}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${address['region'] ?? ''} ${address['detail'] ?? ''}'.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

class _OrderSummaryRow extends StatelessWidget {
  const _OrderSummaryRow({required this.item, required this.totalLabel});

  final Map<String, dynamic> item;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['title']?.toString() ?? '订单商品',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                item['subtitle']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          totalLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.coral,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PartyRow extends StatelessWidget {
  const _PartyRow({
    required this.icon,
    required this.title,
    required this.name,
  });

  final IconData icon;
  final String title;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(name, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineBullet extends StatelessWidget {
  const _TimelineBullet({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
