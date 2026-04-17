import 'dart:math' as math;

class ListingSummary {
  const ListingSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.priceMinor,
    required this.currency,
    required this.originalPriceLabel,
    required this.location,
    required this.badges,
    required this.coverImageUrl,
    required this.sellerId,
    required this.sellerName,
    required this.sellerAvatarUrl,
    required this.status,
    this.viewerUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String priceLabel;
  final int priceMinor;
  final String currency;
  final String originalPriceLabel;
  final String location;
  final List<String> badges;
  final String? coverImageUrl;
  final String sellerId;
  final String sellerName;
  final String? sellerAvatarUrl;
  final String status;
  final String? viewerUrl;

  bool get has3dBadge =>
      badges.any((badge) => badge.toLowerCase().contains('3d'));

  factory ListingSummary.fromJson(Map<String, dynamic> json, Uri apiRoot) {
    final coverMedia =
        (json['cover_media'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final seller =
        (json['seller'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return ListingSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名商品',
      subtitle: json['subtitle']?.toString() ?? '',
      priceLabel: formatMoney(json['price']),
      priceMinor: _moneyAmountMinor(json['price']),
      currency: _moneyCurrency(json['price']),
      originalPriceLabel: formatMoney(json['original_price']),
      location:
          _firstNonEmptyString(<Object?>[
            json['location'],
            json['location_city'],
            seller['location'],
          ]) ??
          '未知地区',
      badges: _readStringList(json['badges']),
      coverImageUrl: _resolveUrl(
        coverMedia['thumbnail_url']?.toString() ??
            coverMedia['url']?.toString(),
        apiRoot,
      ),
      sellerId: seller['id']?.toString() ?? '',
      sellerName: seller['display_name']?.toString() ?? '卖家',
      sellerAvatarUrl: _resolveUrl(seller['avatar_url']?.toString(), apiRoot),
      status: json['status']?.toString() ?? 'unknown',
      viewerUrl: _resolveUrl(json['viewer_url']?.toString(), apiRoot),
    );
  }
}

class ListingDetail {
  const ListingDetail({
    required this.summary,
    required this.description,
    required this.sellerBio,
    required this.sellerLocation,
    required this.sellerScore,
    required this.preview3d,
    required this.specs,
    required this.actions,
  });

  final ListingSummary summary;
  final String description;
  final String sellerBio;
  final String sellerLocation;
  final int? sellerScore;
  final ListingPreview3d preview3d;
  final List<ListingSpec> specs;
  final List<ListingAction> actions;

  factory ListingDetail.fromJson(Map<String, dynamic> json, Uri apiRoot) {
    final resources =
        (json['resources'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final listing =
        (resources['listing'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final seller =
        (resources['seller'] as Map?)?.cast<String, dynamic>() ??
        (listing['seller'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final payload =
        (resources['listing_payload'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return ListingDetail(
      summary: ListingSummary.fromJson(listing, apiRoot),
      description:
          payload['description']?.toString() ??
          listing['subtitle']?.toString() ??
          '暂无商品描述。',
      sellerBio: seller['bio']?.toString() ?? '卖家暂未填写简介。',
      sellerLocation:
          _firstNonEmptyString(<Object?>[
            seller['location'],
            listing['location'],
            listing['location_city'],
          ]) ??
          '未知地区',
      sellerScore: (seller['sesame_credit_score'] as num?)?.toInt(),
      preview3d: ListingPreview3d.fromJson(
        (resources['preview_3d'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        apiRoot,
      ),
      specs: ((resources['specs'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => ListingSpec.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      actions: ((resources['actions'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => ListingAction.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class ListingPreview3d {
  const ListingPreview3d({
    required this.previewStatus,
    required this.statusMessage,
    required this.isReady,
    required this.viewerUrl,
    required this.modelUrl,
    required this.coverImageUrl,
    required this.placeholderTitle,
    required this.placeholderSubtitle,
    required this.placeholderBadges,
  });

  final String previewStatus;
  final String? statusMessage;
  final bool isReady;
  final String? viewerUrl;
  final String? modelUrl;
  final String? coverImageUrl;
  final String placeholderTitle;
  final String placeholderSubtitle;
  final List<String> placeholderBadges;

  bool get hasRenderableSource =>
      effectiveViewerUrl != null || (modelUrl != null && modelUrl!.isNotEmpty);

  String? get effectiveViewerUrl {
    if (viewerUrl != null && viewerUrl!.isNotEmpty) {
      return viewerUrl;
    }
    if (modelUrl == null || modelUrl!.isEmpty) {
      return null;
    }

    final modelUri = Uri.parse(modelUrl!);
    final viewerUri = modelUri.replace(
      path: '/viewer/index.html',
      queryParameters: <String, String>{'model': modelUrl!},
    );
    return viewerUri.toString();
  }

  factory ListingPreview3d.fromJson(Map<String, dynamic> json, Uri apiRoot) {
    final coverMedia =
        (json['cover_media'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final placeholder =
        (json['placeholder'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return ListingPreview3d(
      previewStatus: json['preview_status']?.toString() ?? 'pending',
      statusMessage: json['status_message']?.toString(),
      isReady: json['is_ready'] == true,
      viewerUrl: _resolveUrl(json['viewer_url']?.toString(), apiRoot),
      modelUrl: _resolveUrl(
        json['model_sog_url']?.toString() ??
            json['model_ply_url']?.toString() ??
            json['model_url']?.toString(),
        apiRoot,
      ),
      coverImageUrl: _resolveUrl(
        coverMedia['thumbnail_url']?.toString() ??
            coverMedia['url']?.toString(),
        apiRoot,
      ),
      placeholderTitle: placeholder['title']?.toString() ?? '3D 商品预览',
      placeholderSubtitle: placeholder['subtitle']?.toString() ?? '3D 模型暂未就绪。',
      placeholderBadges: _readStringList(placeholder['badges']),
    );
  }
}

class ListingSpec {
  const ListingSpec({required this.label, required this.value});

  final String label;
  final String value;

  factory ListingSpec.fromJson(Map<String, dynamic> json) {
    return ListingSpec(
      label: json['spec_key']?.toString() ?? '参数',
      value: json['spec_value']?.toString() ?? '-',
    );
  }
}

class ListingAction {
  const ListingAction({
    required this.key,
    required this.title,
    required this.enabled,
  });

  final String key;
  final String title;
  final bool enabled;

  factory ListingAction.fromJson(Map<String, dynamic> json) {
    return ListingAction(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      enabled: json['enabled'] != false,
    );
  }
}

String? _resolveUrl(String? raw, Uri apiRoot) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return apiRoot.resolve(raw).toString();
}

String? _firstNonEmptyString(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

List<String> _readStringList(Object? raw) {
  if (raw is! List) {
    return const <String>[];
  }
  return raw.map((item) => item.toString()).toList(growable: false);
}

String formatMoney(Object? rawPrice) {
  if (rawPrice is! Map) {
    return '面议';
  }

  final price = rawPrice.cast<String, dynamic>();
  final currency = price['currency']?.toString() ?? '';
  final amountMinor = (price['amount_minor'] as num?)?.toInt();
  if (amountMinor == null) {
    return '面议';
  }

  final symbol = switch (currency.toUpperCase()) {
    'CNY' => '￥',
    'USD' => '\$',
    'EUR' => '€',
    _ => '${currency.toUpperCase()} ',
  };
  final amount = amountMinor / 100;
  final formatted = amount % 1 == 0
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return '$symbol$formatted';
}

int _moneyAmountMinor(Object? rawPrice) {
  if (rawPrice is! Map) {
    return 0;
  }
  return (rawPrice['amount_minor'] as num?)?.toInt() ?? 0;
}

String _moneyCurrency(Object? rawPrice) {
  if (rawPrice is! Map) {
    return 'CNY';
  }
  final currency = rawPrice['currency']?.toString().trim() ?? '';
  return currency.isEmpty ? 'CNY' : currency;
}

double adaptiveGridCardWidth(double maxWidth) {
  const minCardWidth = 168.0;
  final columns = math.max(1, (maxWidth / minCardWidth).floor());
  final spacing = columns > 1 ? (columns - 1) * 12.0 : 0.0;
  return (maxWidth - spacing) / columns;
}
