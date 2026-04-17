import 'package:flutter/material.dart';

import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import 'order_pages.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.session,
    required this.commerceRepository,
    required this.listingsRepository,
    required this.listingId,
  });

  final AppSession session;
  final CommerceRepository commerceRepository;
  final ListingsRepository listingsRepository;
  final String listingId;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late Future<ListingDetail> _listingFuture;
  late Future<List<Map<String, dynamic>>> _addressesFuture;
  String? _selectedAddressId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _listingFuture = widget.listingsRepository.fetchListingDetail(
      widget.listingId,
    );
    _addressesFuture = _loadAddresses();
  }

  Future<List<Map<String, dynamic>>> _loadAddresses() async {
    final addresses = await widget.commerceRepository.fetchAddresses(
      widget.session.accessToken,
    );
    if (_selectedAddressId == null && addresses.isNotEmpty) {
      _selectedAddressId = addresses.first['id']?.toString();
    }
    return addresses;
  }

  Future<void> _refreshAddresses() async {
    final future = _loadAddresses();
    setState(() {
      _addressesFuture = future;
    });
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

      final address = await widget.commerceRepository.createAddress(
        widget.session.accessToken,
        recipientName: recipientController.text.trim(),
        phone: phoneController.text.trim(),
        regionCode: regionController.text.trim(),
        addressLine1: detailController.text.trim(),
        isDefault: true,
      );
      setState(() => _selectedAddressId = address['id']?.toString());
      await _refreshAddresses();
    } finally {
      recipientController.dispose();
      phoneController.dispose();
      regionController.dispose();
      detailController.dispose();
    }
  }

  Future<void> _submitOrder() async {
    if (_selectedAddressId == null || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await widget.commerceRepository.createOrder(
        widget.session.accessToken,
        listingId: widget.listingId,
        addressId: _selectedAddressId!,
      );
      final orderData =
          (order['order'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final orderId = orderData['id']?.toString() ?? '';
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderSuccessPage(
            session: widget.session,
            repository: widget.commerceRepository,
            orderId: orderId,
          ),
        ),
      );
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
      appBar: AppBar(title: const Text('确认下单')),
      body: FutureBuilder<ListingDetail>(
        future: _listingFuture,
        builder: (context, listingSnapshot) {
          if (listingSnapshot.connectionState == ConnectionState.waiting &&
              !listingSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (listingSnapshot.hasError || listingSnapshot.data == null) {
            return const Center(child: Text('商品信息加载失败'));
          }
          final listing = listingSnapshot.data!;
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _addressesFuture,
            builder: (context, addressSnapshot) {
              final addresses =
                  addressSnapshot.data ?? const <Map<String, dynamic>>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _SectionCard(
                    title: '商品',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(listing.summary.title),
                      subtitle: Text(listing.summary.subtitle),
                      trailing: Text(listing.summary.priceLabel),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: '收货地址',
                    action: TextButton(
                      onPressed: _createAddress,
                      child: const Text('新增'),
                    ),
                    child: addresses.isEmpty
                        ? const Text('还没有地址，请先新增一个收货地址。')
                        : Column(
                            children: addresses
                                .map(
                                  (address) => RadioListTile<String>(
                                    value: address['id']?.toString() ?? '',
                                    groupValue: _selectedAddressId,
                                    onChanged: (value) {
                                      setState(
                                        () => _selectedAddressId = value,
                                      );
                                    },
                                    title: Text(
                                      address['recipient_name']?.toString() ??
                                          '',
                                    ),
                                    subtitle: Text(
                                      '${address['phone'] ?? ''}  ${address['address_line1'] ?? ''}',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
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
            onPressed: _submitting ? null : _submitOrder,
            child: Text(_submitting ? '提交中...' : '提交订单'),
          ),
        ),
      ),
    );
  }
}

class OrderSuccessPage extends StatelessWidget {
  const OrderSuccessPage({
    super.key,
    required this.session,
    required this.repository,
    required this.orderId,
  });

  final AppSession session;
  final CommerceRepository repository;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('下单成功')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 72,
                color: AppColors.mint,
              ),
              const SizedBox(height: 16),
              Text('订单已创建', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('卖家发货后，你可以在订单详情里查看物流并确认收货。'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderDetailPage(
                        session: session,
                        repository: repository,
                        orderId: orderId,
                      ),
                    ),
                  );
                },
                child: const Text('查看订单'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});

  final String title;
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
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
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
