// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/commerce/commerce_repository.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../chat/chat_pages.dart';
import '../commerce/account_pages.dart';
import '../commerce/checkout_page.dart';
import '../commerce/order_pages.dart';
import '../commerce/review_pages.dart';
import '../home/home_page.dart';
import '../listings/listing_detail_page.dart';
import '../profile/profile_page.dart';
import '../profile/profile_settings_page.dart';
import '../search/search_page.dart';
import '../sell/sell_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.onSignOut,
    required this.apiClient,
    required this.session,
  });

  final Future<void> Function() onSignOut;
  final ApiClient apiClient;
  final AppSession session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _marketplaceVersion = 0;
  late final ListingsRepository _listingsRepository;
  late final CommerceRepository _commerceRepository;

  @override
  void initState() {
    super.initState();
    _listingsRepository = ListingsRepository(widget.apiClient);
    _commerceRepository = CommerceRepository(widget.apiClient);
  }

  void _selectTab(int index) {
    if (widget.session.isGuest && index >= 2) {
      _promptLoginRequired();
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _promptLoginRequired() async {
    final shouldExitGuest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要登录'),
        content: const Text('游客模式只支持浏览首页、搜索、商品详情和 3D 预览。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
    if (shouldExitGuest == true) {
      await widget.onSignOut();
    }
  }

  Future<void> _openChatForListing(String listingId) async {
    if (widget.session.isGuest) {
      await _promptLoginRequired();
      return;
    }
    final detail = await _commerceRepository.createConversation(
      widget.session.accessToken,
      listingId: listingId,
    );
    final conversation =
        (detail['conversation'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final conversationId = conversation['id']?.toString() ?? '';
    if (!mounted || conversationId.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationDetailPage(
          repository: _commerceRepository,
          session: widget.session,
          conversationId: conversationId,
        ),
      ),
    );
  }

  Future<void> _openCheckoutForListing(String listingId) async {
    if (widget.session.isGuest) {
      await _promptLoginRequired();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPage(
          session: widget.session,
          commerceRepository: _commerceRepository,
          listingsRepository: _listingsRepository,
          listingId: listingId,
        ),
      ),
    );
    _markMarketplaceDirty();
  }

  void _openListingReviews(String listingId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingReviewsPage(
          repository: _commerceRepository,
          listingId: listingId,
        ),
      ),
    );
  }

  void _openOrders() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrdersPage(
          session: widget.session,
          repository: _commerceRepository,
        ),
      ),
    );
  }

  void _openWallet() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletPage(
          session: widget.session,
          repository: _commerceRepository,
        ),
      ),
    );
  }

  void _openMembership() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MembershipPage(
          session: widget.session,
          repository: _commerceRepository,
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(
          session: widget.session,
          repository: _commerceRepository,
        ),
      ),
    );
  }

  void _openAddresses() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddressesPage(
          session: widget.session,
          repository: _commerceRepository,
        ),
      ),
    );
  }

  void _openListingDetail(String listingId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailPage(
          repository: _listingsRepository,
          session: widget.session,
          listingId: listingId,
          onOpenChat: () => _openChatForListing(listingId),
          onOpenOrder: () => _openCheckoutForListing(listingId),
          onOpenReview: () => _openListingReviews(listingId),
        ),
      ),
    );
  }

  void _markMarketplaceDirty() {
    setState(() => _marketplaceVersion += 1);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        key: ValueKey('home-$_marketplaceVersion'),
        repository: _listingsRepository,
        onGoSearch: () => _selectTab(1),
        onOpenListing: _openListingDetail,
      ),
      SearchPage(
        key: ValueKey('search-$_marketplaceVersion'),
        repository: _listingsRepository,
        onGoHome: () => _selectTab(0),
        onOpenListing: _openListingDetail,
      ),
      SellPage(
        apiClient: widget.apiClient,
        accessToken: widget.session.accessToken,
        onGoHome: () => _selectTab(0),
        onOpenListing: _openListingDetail,
        onMarketplaceChanged: _markMarketplaceDirty,
      ),
      MessagesPage(repository: _commerceRepository, session: widget.session),
      ProfilePage(
        session: widget.session,
        apiClient: widget.apiClient,
        onOpenSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProfileSettingsPage(
              session: widget.session,
              apiClient: widget.apiClient,
              accessToken: widget.session.accessToken,
              onSave: () {
                Navigator.of(context).pop();
                _markMarketplaceDirty();
              },
            ),
          ),
        ),
        onSignOut: widget.onSignOut,
        repository: _listingsRepository,
        onOpenListing: _openListingDetail,
        onOpenOrders: _openOrders,
        onOpenWallet: _openWallet,
        onOpenMembership: _openMembership,
        onOpenNotifications: _openNotifications,
        onOpenAddresses: _openAddresses,
        onMarketplaceChanged: _markMarketplaceDirty,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            height: 82,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.88),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.72)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 28,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    label: '首页',
                    icon: Icons.home_rounded,
                    selected: _selectedIndex == 0,
                    onTap: () => _selectTab(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    label: '搜索',
                    icon: Icons.manage_search_rounded,
                    selected: _selectedIndex == 1,
                    onTap: () => _selectTab(1),
                  ),
                ),
                Expanded(
                  child: Transform.translate(
                    offset: const Offset(0, -14),
                    child: GestureDetector(
                      onTap: () => _selectTab(2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: AppColors.primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '发布',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    label: '消息',
                    icon: Icons.chat_bubble_rounded,
                    selected: _selectedIndex == 3,
                    onTap: () => _selectTab(3),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    label: '我的',
                    icon: Icons.person_rounded,
                    selected: _selectedIndex == 4,
                    onTap: () => _selectTab(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.text : AppColors.textMuted;
    return InkResponse(
      onTap: onTap,
      radius: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: foreground, size: selected ? 28 : 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
