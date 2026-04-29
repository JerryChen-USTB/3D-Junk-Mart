import 'dart:math' as math;

class ListingSummary {
  const ListingSummary({
    required this.id,
    required this.categoryId,
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
    required this.conditionLevel,
    required this.conditionLabel,
    required this.shippingFeeMinor,
    required this.shippingFeeLabel,
    required this.shippingPromise,
    required this.isNegotiable,
    required this.isFavorited,
    required this.favoriteCount,
    required this.has3dPreview,
    required this.sellerTrust,
    this.viewerUrl,
  });

  final String id;
  final String categoryId;
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
  final String conditionLevel;
  final String conditionLabel;
  final int shippingFeeMinor;
  final String shippingFeeLabel;
  final String shippingPromise;
  final bool isNegotiable;
  final bool isFavorited;
  final int favoriteCount;
  final bool has3dPreview;
  final ListingSellerTrust sellerTrust;
  final String? viewerUrl;

  bool get has3dBadge =>
      has3dPreview ||
      badges.any((badge) => badge.toLowerCase().contains('3d'));

  bool get isLive => status == 'live';

  bool get hasKnownCondition => conditionLabel != _unknownConditionLabel;

  factory ListingSummary.fromJson(Map<String, dynamic> json, Uri apiRoot) {
    final coverMedia =
        (json['cover_media'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final seller =
        (json['seller'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return ListingSummary(
      id: json['id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled listing',
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
          'Unknown location',
      badges: _readStringList(json['badges']),
      coverImageUrl: _resolveUrl(
        coverMedia['thumbnail_url']?.toString() ??
            coverMedia['url']?.toString(),
        apiRoot,
      ),
      sellerId: seller['id']?.toString() ?? '',
      sellerName: seller['display_name']?.toString() ?? 'Seller',
      sellerAvatarUrl: _resolveUrl(seller['avatar_url']?.toString(), apiRoot),
      status: json['status']?.toString() ?? 'unknown',
      conditionLevel: json['condition_level']?.toString() ?? '',
      conditionLabel: _normalizeConditionLabel(
        level: json['condition_level']?.toString(),
        label: json['condition_label']?.toString(),
      ),
      shippingFeeMinor: _moneyAmountMinor(json['shipping_fee']),
      shippingFeeLabel: formatMoney(json['shipping_fee']),
      shippingPromise: json['shipping_promise']?.toString() ?? '',
      isNegotiable: json['is_negotiable'] == true,
      isFavorited: json['is_favorited'] == true,
      favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0,
      has3dPreview: json['has_3d_preview'] == true,
      sellerTrust: ListingSellerTrust.fromJson(
        (json['seller_trust'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      viewerUrl: _resolveUrl(json['viewer_url']?.toString(), apiRoot),
    );
  }
}

class ListingSellerTrust {
  const ListingSellerTrust({
    required this.soldCount,
    required this.followersCount,
    required this.positiveRate,
    required this.sesameScore,
    required this.vipLevel,
  });

  final int soldCount;
  final int followersCount;
  final double? positiveRate;
  final int sesameScore;
  final String vipLevel;

  factory ListingSellerTrust.fromJson(Map<String, dynamic> json) {
    return ListingSellerTrust(
      soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      positiveRate: (json['positive_rate'] as num?)?.toDouble(),
      sesameScore: (json['sesame_credit_score'] as num?)?.toInt() ?? 0,
      vipLevel: json['vip_level']?.toString() ?? 'none',
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
    required this.servicePromises,
    required this.transactionInfo,
  });

  final ListingSummary summary;
  final String description;
  final String sellerBio;
  final String sellerLocation;
  final int? sellerScore;
  final ListingPreview3d preview3d;
  final List<ListingSpec> specs;
  final List<ListingAction> actions;
  final List<String> servicePromises;
  final ListingTransactionInfo transactionInfo;

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
          'No description yet.',
      sellerBio: seller['bio']?.toString() ?? 'This seller has not added a bio.',
      sellerLocation:
          _firstNonEmptyString(<Object?>[
            seller['location'],
            listing['location'],
            listing['location_city'],
          ]) ??
          'Unknown location',
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
      servicePromises: _readStringList(resources['service_promises']),
      transactionInfo: ListingTransactionInfo.fromJson(
        (resources['transaction_info'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class ListingTransactionInfo {
  const ListingTransactionInfo({
    required this.conditionLevel,
    required this.conditionLabel,
    required this.defectNotes,
    required this.shippingFeeMinor,
    required this.shippingFeeLabel,
    required this.shippingPromise,
    required this.isNegotiable,
    required this.favoriteCount,
  });

  final String conditionLevel;
  final String conditionLabel;
  final String defectNotes;
  final int shippingFeeMinor;
  final String shippingFeeLabel;
  final String shippingPromise;
  final bool isNegotiable;
  final int favoriteCount;

  factory ListingTransactionInfo.fromJson(Map<String, dynamic> json) {
    return ListingTransactionInfo(
      conditionLevel: json['condition_level']?.toString() ?? '',
      conditionLabel: _normalizeConditionLabel(
        level: json['condition_level']?.toString(),
        label: json['condition_label']?.toString(),
      ),
      defectNotes: json['defect_notes']?.toString() ?? '',
      shippingFeeMinor: _moneyAmountMinor(json['shipping_fee']),
      shippingFeeLabel: formatMoney(json['shipping_fee']),
      shippingPromise: json['shipping_promise']?.toString() ?? '',
      isNegotiable: json['is_negotiable'] == true,
      favoriteCount: (json['favorite_count'] as num?)?.toInt() ?? 0,
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
      placeholderTitle:
          placeholder['title']?.toString() ?? '3D product preview',
      placeholderSubtitle:
          placeholder['subtitle']?.toString() ?? 'The 3D model is not ready yet.',
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
      label: json['spec_key']?.toString() ?? 'Spec',
      value: json['spec_value']?.toString() ?? '-',
    );
  }
}

class ListingAction {
  const ListingAction({
    required this.key,
    required this.title,
    required this.enabled,
    this.active = false,
  });

  final String key;
  final String title;
  final bool enabled;
  final bool active;

  factory ListingAction.fromJson(Map<String, dynamic> json) {
    return ListingAction(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      enabled: json['enabled'] != false,
      active: json['active'] == true,
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

const String _unknownConditionLabel = '成色待补充';

const Map<String, String> _conditionLabels = <String, String>{
  'new': '全新',
  'excellent': '近乎全新',
  'good': '成色良好',
  'fair': '正常使用',
  'poor': '瑕疵明显',
};

String _normalizeConditionLabel({
  required String? level,
  required String? label,
}) {
  final normalizedLevel = level?.trim().toLowerCase() ?? '';
  if (_conditionLabels.containsKey(normalizedLevel)) {
    return _conditionLabels[normalizedLevel]!;
  }

  final normalizedLabel = label?.trim() ?? '';
  if (normalizedLabel.isEmpty || _isUnknownConditionLabel(normalizedLabel)) {
    return _unknownConditionLabel;
  }

  final loweredLabel = normalizedLabel.toLowerCase();
  if (_conditionLabels.containsKey(loweredLabel)) {
    return _conditionLabels[loweredLabel]!;
  }

  return normalizedLabel;
}

bool _isUnknownConditionLabel(String label) {
  final lowered = label.trim().toLowerCase();
  return lowered.isEmpty ||
      lowered == 'unknown' ||
      lowered == 'condition unknown' ||
      lowered == 'n/a' ||
      lowered == 'null' ||
      lowered == 'none';
}

String formatMoney(Object? rawPrice) {
  if (rawPrice is! Map) {
    return 'Negotiable';
  }

  final price = rawPrice.cast<String, dynamic>();
  final currency = price['currency']?.toString() ?? '';
  final amountMinor = (price['amount_minor'] as num?)?.toInt();
  if (amountMinor == null) {
    return 'Negotiable';
  }

  final symbol = switch (currency.toUpperCase()) {
    'CNY' => '¥',
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
