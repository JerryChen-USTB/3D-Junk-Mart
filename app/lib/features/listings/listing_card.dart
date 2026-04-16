import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/listings/listing_models.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.tall = false,
  });

  final ListingSummary listing;
  final VoidCallback onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final topHeight = tall ? 198.0 : 168.0;
    final hasViewer = listing.viewerUrl != null && listing.viewerUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasViewer)
                _ViewerCover(
                  viewerUrl: listing.viewerUrl!,
                  badge: listing.badges.isNotEmpty
                      ? listing.badges.first
                      : '3D 展示',
                  height: topHeight,
                )
              else
                _ListingCover(
                  imageUrl: listing.coverImageUrl,
                  title: listing.title,
                  subtitle: listing.location,
                  badge: listing.badges.isNotEmpty
                      ? listing.badges.first
                      : listing.has3dBadge
                      ? '3D'
                      : '在售',
                  height: topHeight,
                  highlight3d: listing.has3dBadge,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        height: 1.3,
                      ),
                    ),
                    if (listing.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        listing.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: AppColors.coral,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        if (listing.has3dBadge)
                          EditorialPill(
                            label: '3D',
                            backgroundColor: const Color(0xFFE4F5EE),
                            foregroundColor: AppColors.mint,
                            icon: Icons.view_in_ar_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            listing.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            listing.sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ],
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

class _ViewerCover extends StatefulWidget {
  const _ViewerCover({
    required this.viewerUrl,
    required this.badge,
    required this.height,
  });

  final String viewerUrl;
  final String badge;
  final double height;

  @override
  State<_ViewerCover> createState() => _ViewerCoverState();
}

class _ViewerCoverState extends State<_ViewerCover> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A1A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Hide all UI and reduce render quality for embed mode.
            _controller.runJavaScript('''
              document.body.classList.add('embed');
              var selectors = ['.hud', '.animation-panel', '#minimal-reset-view', '.overlay'];
              selectors.forEach(function(sel) {
                var els = document.querySelectorAll(sel);
                els.forEach(function(el) { el.style.display = 'none'; });
              });

              // Lower canvas resolution for card performance.
              var canvas = document.querySelector('canvas');
              if (canvas) {
                var dpr = Math.min(window.devicePixelRatio, 1.0);
                canvas.width  = canvas.clientWidth  * dpr;
                canvas.height = canvas.clientHeight * dpr;
              }
            ''');
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(_embedUrl(widget.viewerUrl));
  }

  /// Append `embed=1` so the viewer hides all UI controls via CSS too.
  static Uri _embedUrl(String url) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters);
    params['embed'] = '1';
    return uri.replace(queryParameters: params);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dark background behind the viewer.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF141414), Color(0xFF3F463C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // WebView with eager gesture recognizer to prevent scroll conflicts.
            WebViewWidget(
              controller: _controller,
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            // Loading spinner.
            if (_loading)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white54,
                  ),
                ),
              ),
            // Badge overlay — use IgnorePointer so touches pass through.
            Positioned(
              left: 14,
              top: 14,
              child: IgnorePointer(
                child: EditorialPill(
                  label: widget.badge,
                  backgroundColor: Colors.white.withValues(alpha: 0.74),
                  foregroundColor: AppColors.primary,
                ),
              ),
            ),
            // 3D icon watermark — use IgnorePointer.
            Positioned(
              right: 10,
              bottom: 10,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.view_in_ar_rounded,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ListingHeroBanner extends StatelessWidget {
  const ListingHeroBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 236,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD34D), Color(0xFFF5E8AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24FFD83D),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 18,
            child: EditorialPill(
              label: badge,
              backgroundColor: Colors.white.withValues(alpha: 0.64),
              foregroundColor: AppColors.primary,
            ),
          ),
          Positioned(
            left: 18,
            top: 66,
            right: 140,
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.primary,
                height: 0.98,
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 140,
            bottom: 18,
            child: Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.primary.withValues(alpha: 0.8),
                height: 1.45,
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 18,
            bottom: 18,
            child: Container(
              width: 122,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.white.withValues(alpha: 0.26),
              ),
              child: const Icon(
                Icons.view_in_ar_rounded,
                size: 56,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCover extends StatelessWidget {
  const _ListingCover({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.height,
    required this.highlight3d,
  });

  final String? imageUrl;
  final String title;
  final String subtitle;
  final String badge;
  final double height;
  final bool highlight3d;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: highlight3d
                      ? const [Color(0xFF141414), Color(0xFF3F463C)]
                      : const [Color(0xFFF4E0A6), Color(0xFFE7D3A4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (imageUrl != null && imageUrl!.isNotEmpty)
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.04),
                    Colors.black.withValues(alpha: 0.38),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 14,
              child: EditorialPill(
                label: badge,
                backgroundColor: Colors.white.withValues(alpha: 0.74),
                foregroundColor: AppColors.primary,
              ),
            ),
            if (highlight3d)
              const Center(
                child: Icon(
                  Icons.view_in_ar_rounded,
                  size: 54,
                  color: Colors.white,
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
