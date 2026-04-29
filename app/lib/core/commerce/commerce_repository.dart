import '../api/api_client.dart';

class CommerceRepository {
  CommerceRepository(this._apiClient);

  final ApiClient _apiClient;

  Uri get apiRoot => Uri.parse(_apiClient.baseUrl).resolve('/');

  String? resolveUrl(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return apiRoot.resolve(raw).toString();
  }

  Future<List<Map<String, dynamic>>> fetchConversations(
    String bearerToken,
  ) async {
    final response = await _apiClient.getObject(
      '/conversations',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> createConversation(
    String bearerToken, {
    required String listingId,
    String? contentText,
  }) async {
    final response = await _apiClient.postJson(
      '/conversations',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'listing_id': listingId,
        if (contentText != null && contentText.trim().isNotEmpty)
          'content_text': contentText.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> fetchConversationDetail(
    String conversationId,
    String bearerToken,
  ) async {
    final response = await _apiClient.getJson(
      '/conversations/$conversationId',
      bearerToken: bearerToken,
    );
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchConversationMessages(
    String conversationId,
    String bearerToken,
  ) async {
    final response = await _apiClient.getObject(
      '/conversations/$conversationId/messages',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> sendConversationMessage(
    String conversationId,
    String bearerToken, {
    required String contentText,
    String messageType = 'text',
    String? offerId,
  }) async {
    final response = await _apiClient.postJson(
      '/conversations/$conversationId/messages',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'content_text': contentText,
        'message_type': messageType,
        if (offerId != null && offerId.isNotEmpty) 'offer_id': offerId,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> createConversationOffer(
    String conversationId,
    String bearerToken, {
    required int amountMinor,
    String currency = 'CNY',
    String? note,
  }) async {
    final response = await _apiClient.postJson(
      '/conversations/$conversationId/offers',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'amount_minor': amountMinor,
        'currency': currency,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> acceptConversationOffer(
    String conversationId,
    String offerId,
    String bearerToken,
  ) async {
    final response = await _apiClient.postJson(
      '/conversations/$conversationId/offers/$offerId/accept',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> rejectConversationOffer(
    String conversationId,
    String offerId,
    String bearerToken,
  ) async {
    final response = await _apiClient.postJson(
      '/conversations/$conversationId/offers/$offerId/reject',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return response.data;
  }

  Future<void> markConversationRead(
    String conversationId,
    String bearerToken,
  ) async {
    await _apiClient.postJson(
      '/conversations/$conversationId/read',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
  }

  Future<List<Map<String, dynamic>>> fetchOrders(String bearerToken) async {
    final response = await _apiClient.getObject(
      '/orders',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> fetchOrderDetail(
    String orderId,
    String bearerToken,
  ) async {
    final response = await _apiClient.getJson(
      '/orders/$orderId',
      bearerToken: bearerToken,
    );
    return response.data;
  }

  Future<Map<String, dynamic>> createOrder(
    String bearerToken, {
    required String listingId,
    required String addressId,
    String? offerId,
    String? conversationId,
    String? buyerNote,
  }) async {
    final response = await _apiClient.postJson(
      '/orders',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'listing_id': listingId,
        'address_id': addressId,
        if (offerId != null && offerId.isNotEmpty) 'offer_id': offerId,
        if (conversationId != null && conversationId.isNotEmpty)
          'conversation_id': conversationId,
        if (buyerNote != null && buyerNote.trim().isNotEmpty)
          'buyer_note': buyerNote.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> mockPayOrder(
    String orderId,
    String bearerToken,
  ) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/mock-pay',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> shipOrder(
    String orderId,
    String bearerToken, {
    required String carrierName,
    required String trackingNo,
  }) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/ship',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'carrier_name': carrierName,
        'tracking_no': trackingNo,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> confirmReceipt(
    String orderId,
    String bearerToken,
  ) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/confirm-receipt',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> cancelOrder(
    String orderId,
    String bearerToken,
  ) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/cancel',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> requestRefund(
    String orderId,
    String bearerToken, {
    required String reason,
  }) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/refund-request',
      bearerToken: bearerToken,
      body: <String, dynamic>{'reason': reason},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> approveRefund(
    String orderId,
    String bearerToken, {
    String? resolutionNote,
  }) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/approve-refund',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        if (resolutionNote != null && resolutionNote.trim().isNotEmpty)
          'resolution_note': resolutionNote.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> rejectRefund(
    String orderId,
    String bearerToken, {
    String? resolutionNote,
  }) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/reject-refund',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        if (resolutionNote != null && resolutionNote.trim().isNotEmpty)
          'resolution_note': resolutionNote.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> disputeOrder(
    String orderId,
    String bearerToken, {
    required String reason,
  }) async {
    final response = await _apiClient.postJson(
      '/orders/$orderId/dispute',
      bearerToken: bearerToken,
      body: <String, dynamic>{'reason': reason},
    );
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchAddresses(String bearerToken) async {
    final response = await _apiClient.getObject(
      '/users/me/addresses',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> createAddress(
    String bearerToken, {
    String? label,
    required String recipientName,
    required String phone,
    required String regionCode,
    required String addressLine1,
    String? addressLine2,
    bool isDefault = false,
  }) async {
    final response = await _apiClient.postJson(
      '/users/me/addresses',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        'recipient_name': recipientName,
        'phone': phone,
        'region_code': regionCode,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'is_default': isDefault,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> updateAddress(
    String addressId,
    String bearerToken, {
    String? label,
    String? recipientName,
    String? phone,
    String? regionCode,
    String? addressLine1,
    String? addressLine2,
    bool? isDefault,
  }) async {
    final response = await _apiClient.patchJson(
      '/users/me/addresses/$addressId',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        if (label case final value?) 'label': value,
        if (recipientName case final value?) 'recipient_name': value,
        if (phone case final value?) 'phone': value,
        if (regionCode case final value?) 'region_code': value,
        if (addressLine1 case final value?) 'address_line1': value,
        if (addressLine2 case final value?) 'address_line2': value,
        if (isDefault case final value?) 'is_default': value,
      },
    );
    return response.data;
  }

  Future<void> deleteAddress(String addressId, String bearerToken) async {
    await _apiClient.deleteJson(
      '/users/me/addresses/$addressId',
      bearerToken: bearerToken,
    );
  }

  Future<List<Map<String, dynamic>>> fetchListingReviews(
    String listingId,
  ) async {
    final response = await _apiClient.getObject('/listings/$listingId/reviews');
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchReviewTags() async {
    final response = await _apiClient.getObject('/reviews/tags');
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> fetchReviewDraft(
    String orderId,
    String bearerToken,
  ) async {
    final response = await _apiClient.getJson(
      '/orders/$orderId/review-draft',
      bearerToken: bearerToken,
    );
    return response.data;
  }

  Future<Map<String, dynamic>> updateReviewDraft(
    String orderId,
    String bearerToken, {
    required Map<String, dynamic> payload,
  }) async {
    final response = await _apiClient.patchJson(
      '/orders/$orderId/review-draft',
      bearerToken: bearerToken,
      body: payload,
    );
    return response.data;
  }

  Future<Map<String, dynamic>> submitReview(
    String bearerToken, {
    required String orderId,
    required int rating,
    required String content,
    List<String> tags = const <String>[],
  }) async {
    final response = await _apiClient.postJson(
      '/reviews',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'order_id': orderId,
        'rating': rating,
        'content': content,
        'tags': tags,
        'media_asset_ids': const <String>[],
        'anonymity_enabled': false,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> fetchWallet(String bearerToken) async {
    final response = await _apiClient.getJson(
      '/wallet/summary',
      bearerToken: bearerToken,
    );
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchMembershipPlans() async {
    final response = await _apiClient.getObject('/membership/plans');
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>?> fetchMembershipCurrent(
    String bearerToken,
  ) async {
    final response = await _apiClient.getJson(
      '/memberships/current',
      bearerToken: bearerToken,
    );
    return response.data.isEmpty ? null : response.data;
  }

  Future<Map<String, dynamic>> upgradeMembership(
    String bearerToken, {
    required String planKey,
  }) async {
    final response = await _apiClient.postJson(
      '/membership/upgrade',
      bearerToken: bearerToken,
      body: <String, dynamic>{'plan_key': planKey},
    );
    return response.data;
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(
    String bearerToken,
  ) async {
    final response = await _apiClient.getObject(
      '/notifications',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<void> readAllNotifications(String bearerToken) async {
    await _apiClient.postJson(
      '/notifications/read-all',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
  }

  Future<void> readNotification(
    String notificationId,
    String bearerToken,
  ) async {
    await _apiClient.patchJson(
      '/notifications/$notificationId/read',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }
}
