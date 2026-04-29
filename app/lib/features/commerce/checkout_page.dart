import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listing_models.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/commerce_widgets.dart';
import 'order_pages.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.session,
    required this.commerceRepository,
    required this.listingsRepository,
    required this.listingId,
    this.conversationId,
    this.offerId,
    this.offerPriceMinor,
  });

  final AppSession session;
  final CommerceRepository commerceRepository;
  final ListingsRepository listingsRepository;
  final String listingId;
  final String? conversationId;
  final String? offerId;
  final int? offerPriceMinor;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late Future<ListingDetail> _listingFuture;
  late Future<List<Map<String, dynamic>>> _addressesFuture;
  final TextEditingController _buyerNoteController = TextEditingController();
  String? _selectedAddressId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _listingFuture = widget.listingsRepository.fetchListingDetail(
      widget.listingId,
      bearerToken: widget.session.accessToken,
    );
    _addressesFuture = _loadAddresses();
  }

  @override
  void dispose() {
    _buyerNoteController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadAddresses() async {
    final addresses = await widget.commerceRepository.fetchAddresses(
      widget.session.accessToken,
    );
    if (_selectedAddressId == null && addresses.isNotEmpty) {
      final defaultAddress = addresses.firstWhere(
        (item) => item['is_default'] == true,
        orElse: () => addresses.first,
      );
      _selectedAddressId = defaultAddress['id']?.toString();
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
    final labelController = TextEditingController(text: '家');
    final recipientController = TextEditingController();
    final phoneController = TextEditingController();
    final regionController = TextEditingController(text: '上海');
    final detailController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('新增地址'),
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
                  controller: detailController,
                  decoration: const InputDecoration(labelText: '详细地址'),
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
      );
      if (confirmed != true) {
        return;
      }

      final recipient = recipientController.text.trim();
      final phone = phoneController.text.trim();
      final region = regionController.text.trim();
      final detail = detailController.text.trim();
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
        final address = await widget.commerceRepository.createAddress(
          widget.session.accessToken,
          label: labelController.text.trim(),
          recipientName: recipient,
          phone: phone,
          regionCode: region,
          addressLine1: detail,
          isDefault: true,
        );
        setState(() {
          _selectedAddressId = address['id']?.toString();
        });
        await _refreshAddresses();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _checkoutErrorMessage(error, fallback: '地址保存失败，请稍后重试'),
              ),
            ),
          );
        }
      }
    } finally {
      labelController.dispose();
      recipientController.dispose();
      phoneController.dispose();
      regionController.dispose();
      detailController.dispose();
    }
  }

  Future<void> _submitOrder(ListingDetail listing) async {
    if (_selectedAddressId == null || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await widget.commerceRepository.createOrder(
        widget.session.accessToken,
        listingId: widget.listingId,
        addressId: _selectedAddressId!,
        offerId: widget.offerId,
        conversationId: widget.conversationId,
        buyerNote: _buyerNoteController.text.trim(),
      );
      final orderData =
          (order['order'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final orderId = orderData['id']?.toString() ?? '';
      if (!mounted || orderId.isEmpty) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MockPaymentPage(
            session: widget.session,
            repository: widget.commerceRepository,
            orderId: orderId,
            listingTitle: listing.summary.title,
            amountMinor: widget.offerPriceMinor ?? listing.summary.priceMinor,
            shippingMinor: listing.transactionInfo.shippingFeeMinor,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _checkoutErrorMessage(error, fallback: '订单提交失败，请稍后重试'),
            ),
          ),
        );
      }
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
      appBar: AppBar(title: const Text('确认订单')),
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
          final goodsMinor =
              widget.offerPriceMinor ?? listing.summary.priceMinor;
          final shippingMinor = listing.transactionInfo.shippingFeeMinor;
          final totalMinor = goodsMinor + shippingMinor;

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _addressesFuture,
            builder: (context, addressSnapshot) {
              final addresses =
                  addressSnapshot.data ?? const <Map<String, dynamic>>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                children: [
                  if (widget.offerId != null && widget.offerId!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CommerceStatusBanner(
                        title: '议价成交价下单',
                        subtitle: '当前订单将按聊天中已接受的议价金额结算，提交后进入模拟支付确认。',
                        tone: 'warning',
                      ),
                    ),
                  CommerceCard(
                    title: '收货地址',
                    subtitle: '请选择一个收货地址，订单会保存地址快照。',
                    action: TextButton(
                      onPressed: _createAddress,
                      child: const Text('新增'),
                    ),
                    child: addresses.isEmpty
                        ? const CommerceEmptyState(
                            icon: Icons.location_on_outlined,
                            title: '还没有地址',
                            subtitle: '先补充一个收货地址，再继续提交订单。',
                          )
                        : Column(
                            children: addresses
                                .map(
                                  (address) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _AddressOptionTile(
                                      address: address,
                                      selected:
                                          _selectedAddressId ==
                                          address['id']?.toString(),
                                      onTap: () {
                                        setState(() {
                                          _selectedAddressId = address['id']
                                              ?.toString();
                                        });
                                      },
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '商品信息',
                    subtitle: '下单后将锁定该商品的当前价格快照。',
                    child: _CheckoutListingCard(
                      listing: listing,
                      goodsPriceLabel: _moneyLabel(goodsMinor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '支付与备注',
                    subtitle: '本项目不接真实支付，支付流程将由模拟支付完成。',
                    child: Column(
                      children: [
                        const _CheckoutStaticRow(
                          icon: Icons.account_balance_wallet_outlined,
                          title: '支付方式',
                          subtitle: '模拟支付 · 平台担保',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _buyerNoteController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: '给卖家留言，例如收货时间或沟通补充',
                            filled: true,
                            fillColor: AppColors.surfaceSoft,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CommerceCard(
                    title: '金额明细',
                    child: Column(
                      children: [
                        CommerceKeyValueRow(
                          label: '商品总额',
                          value: _moneyLabel(goodsMinor),
                        ),
                        CommerceKeyValueRow(
                          label: '运费',
                          value: _moneyLabel(shippingMinor),
                        ),
                        if (widget.offerId != null &&
                            widget.offerId!.isNotEmpty &&
                            listing.summary.priceMinor > goodsMinor)
                          CommerceKeyValueRow(
                            label: '议价优惠',
                            value:
                                '-${_moneyLabel(listing.summary.priceMinor - goodsMinor)}',
                          ),
                        const Divider(height: 24),
                        CommerceKeyValueRow(
                          label: '应付总额',
                          value: _moneyLabel(totalMinor),
                          emphasize: true,
                        ),
                      ],
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
        child: FutureBuilder<ListingDetail>(
          future: _listingFuture,
          builder: (context, snapshot) {
            final detail = snapshot.data;
            final disabled =
                _submitting || _selectedAddressId == null || detail == null;
            final amountMinor = detail == null
                ? 0
                : (widget.offerPriceMinor ?? detail.summary.priceMinor) +
                      detail.transactionInfo.shippingFeeMinor;
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(color: AppColors.surface),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '待支付',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _moneyLabel(amountMinor),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(color: AppColors.coral),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 156,
                    child: FilledButton(
                      onPressed: disabled ? null : () => _submitOrder(detail),
                      child: Text(_submitting ? '提交中...' : '提交订单'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _moneyLabel(int amountMinor) => formatMoney(<String, dynamic>{
    'amount_minor': amountMinor,
    'currency': 'CNY',
  });
}

class MockPaymentPage extends StatefulWidget {
  const MockPaymentPage({
    super.key,
    required this.session,
    required this.repository,
    required this.orderId,
    required this.listingTitle,
    required this.amountMinor,
    required this.shippingMinor,
  });

  final AppSession session;
  final CommerceRepository repository;
  final String orderId;
  final String listingTitle;
  final int amountMinor;
  final int shippingMinor;

  @override
  State<MockPaymentPage> createState() => _MockPaymentPageState();
}

class _MockPaymentPageState extends State<MockPaymentPage> {
  bool _paying = false;

  Future<void> _confirmMockPay() async {
    if (_paying) {
      return;
    }
    setState(() => _paying = true);
    try {
      await widget.repository.mockPayOrder(
        widget.orderId,
        widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderDetailPage(
            session: widget.session,
            repository: widget.repository,
            orderId: widget.orderId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _checkoutErrorMessage(error, fallback: '模拟支付失败，请稍后重试'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _paying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMinor = widget.amountMinor + widget.shippingMinor;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('模拟支付')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CommerceStatusBanner(
            title: '订单已创建',
            subtitle: '现在进入模拟支付，支付后订单会转为待发货状态。',
            tone: 'warning',
          ),
          const SizedBox(height: 16),
          CommerceCard(
            title: '支付确认',
            subtitle: '这一步只模拟支付结果，不接入真实付款。',
            child: Column(
              children: [
                CommerceKeyValueRow(label: '订单编号', value: widget.orderId),
                CommerceKeyValueRow(label: '商品', value: widget.listingTitle),
                CommerceKeyValueRow(
                  label: '商品金额',
                  value: formatMoney(<String, dynamic>{
                    'amount_minor': widget.amountMinor,
                    'currency': 'CNY',
                  }),
                ),
                CommerceKeyValueRow(
                  label: '运费',
                  value: formatMoney(<String, dynamic>{
                    'amount_minor': widget.shippingMinor,
                    'currency': 'CNY',
                  }),
                ),
                const Divider(height: 24),
                CommerceKeyValueRow(
                  label: '应付总额',
                  value: formatMoney(<String, dynamic>{
                    'amount_minor': totalMinor,
                    'currency': 'CNY',
                  }),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton(
            onPressed: _paying ? null : _confirmMockPay,
            child: Text(_paying ? '支付中...' : '确认模拟支付'),
          ),
        ),
      ),
    );
  }
}

String _checkoutErrorMessage(Object error, {required String fallback}) {
  if (error is ApiException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }
  return fallback;
}

class _CheckoutListingCard extends StatelessWidget {
  const _CheckoutListingCard({
    required this.listing,
    required this.goodsPriceLabel,
  });

  final ListingDetail listing;
  final String goodsPriceLabel;

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
            image: listing.summary.coverImageUrl == null
                ? null
                : DecorationImage(
                    image: NetworkImage(listing.summary.coverImageUrl!),
                    fit: BoxFit.cover,
                  ),
          ),
          child: listing.summary.coverImageUrl == null
              ? const Icon(
                  Icons.inventory_2_rounded,
                  color: AppColors.textMuted,
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                listing.summary.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                listing.transactionInfo.conditionLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CommercePill(
                    label: listing.summary.shippingPromise,
                    backgroundColor: AppColors.surfaceSoft,
                    foregroundColor: AppColors.primary,
                  ),
                  if (listing.transactionInfo.isNegotiable)
                    const CommercePill(
                      label: '支持议价',
                      backgroundColor: Color(0xFFFFF3D8),
                      foregroundColor: AppColors.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          goodsPriceLabel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.coral,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AddressOptionTile extends StatelessWidget {
  const _AddressOptionTile({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF6DE) : AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.warning : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          address['recipient_name']?.toString() ?? '收货人',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          address['phone']?.toString() ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (address['is_default'] == true)
                          const CommercePill(
                            label: '默认',
                            backgroundColor: Color(0xFFE8F7F0),
                            foregroundColor: AppColors.success,
                          ),
                        if ((address['label']?.toString() ?? '').isNotEmpty)
                          CommercePill(
                            label: address['label']!.toString(),
                            backgroundColor: AppColors.surfaceRaised,
                            foregroundColor: AppColors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      address['full_address']?.toString() ??
                          address['address_line1']?.toString() ??
                          '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.45,
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

class _CheckoutStaticRow extends StatelessWidget {
  const _CheckoutStaticRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
