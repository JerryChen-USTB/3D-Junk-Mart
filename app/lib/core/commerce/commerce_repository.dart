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
  }) async {
    final response = await _apiClient.postJson(
      '/conversations/$conversationId/messages',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'content_text': contentText,
        'message_type': 'text',
      },
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
  }) async {
    final response = await _apiClient.postJson(
      '/orders',
      bearerToken: bearerToken,
      body: <String, dynamic>{'listing_id': listingId, 'address_id': addressId},
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

  Future<List<Map<String, dynamic>>> fetchAddresses(String bearerToken) async {
    final response = await _apiClient.getObject(
      '/users/me/addresses',
      bearerToken: bearerToken,
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> createAddress(
    String bearerToken, {
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
