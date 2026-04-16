// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/listings/listings_repository.dart';
import '../../core/session/app_session.dart';
import '../chat/chat_pages.dart';
import '../home/home_page.dart';
import '../listings/listing_detail_page.dart';
import '../profile/profile_page.dart';
import '../profile/profile_settings_page.dart';
import '../search/search_page.dart';
import '../sell/sell_page.dart';
import '../../theme/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _listingsRepository = ListingsRepository(widget.apiClient);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('功能开发中，敬请期待'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openListingDetail(String listingId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListingDetailPage(
          repository: _listingsRepository,
          listingId: listingId,
          onOpenChat: _showComingSoon,
          onOpenOrder: _showComingSoon,
          onOpenReview: _showComingSoon,
        ),
      ),
    );
  }

  void _markMarketplaceDirty() {
    setState(() {
      _marketplaceVersion += 1;
    });
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
      const MessagesPage(),
      ProfilePage(
        key: ValueKey('profile-$_marketplaceVersion'),
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
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33FFD83D),
                                  blurRadius: 22,
                                  offset: Offset(0, 8),
                                ),
                              ],
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
