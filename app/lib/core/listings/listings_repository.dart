import '../api/api_client.dart';
import 'listing_models.dart';

class ListingsRepository {
  ListingsRepository(this._apiClient);

  final ApiClient _apiClient;

  Uri get _apiRoot => Uri.parse(_apiClient.baseUrl).resolve('/');

  String? resolveUrl(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _apiRoot.resolve(raw).toString();
  }

  Future<List<ListingSummary>> fetchListings({
    int limit = 20,
    String query = '',
    String? status,
  }) async {
    final response = await _apiClient.getObject(
      '/listings',
      queryParameters: <String, dynamic>{
        'page_size': limit,
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final data = response.data;
    if (data is! List) {
      return const <ListingSummary>[];
    }

    return data
        .whereType<Map>()
        .map((item) => ListingSummary.fromJson(item.cast<String, dynamic>(), _apiRoot))
        .toList(growable: false);
  }

  Future<List<ListingSummary>> fetchMyListings(String bearerToken) async {
    final response = await _apiClient.getObject(
      '/users/me/listings',
      bearerToken: bearerToken,
      queryParameters: const <String, dynamic>{'page_size': 50},
    );
    final data = response.data;
    if (data is! List) {
      return const <ListingSummary>[];
    }

    return data
        .whereType<Map>()
        .map((item) => ListingSummary.fromJson(item.cast<String, dynamic>(), _apiRoot))
        .toList(growable: false);
  }

  Future<ListingDetail> fetchListingDetail(String listingId) async {
    final response = await _apiClient.getObject('/pages/listings/$listingId');
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Listing detail payload is not a JSON object.');
    }

    return ListingDetail.fromJson(data, _apiRoot);
  }

  Future<ListingSummary> updateListing({
    required String listingId,
    required String bearerToken,
    required String title,
    required String description,
    required int priceMinor,
    required String currency,
    String? locationCity,
  }) async {
    final response = await _apiClient.patchJson(
      '/listings/$listingId',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'title': title,
        'description': description,
        'price_minor': priceMinor,
        'currency': currency,
        'location_city': locationCity,
      },
    );
    return ListingSummary.fromJson(response.data, _apiRoot);
  }

  Future<ListingSummary> uploadListingCover({
    required String listingId,
    required String bearerToken,
    required String filePath,
  }) async {
    final response = await _apiClient.uploadFile(
      '/listings/$listingId/cover',
      filePath: filePath,
      fieldName: 'file',
      bearerToken: bearerToken,
    );
    return ListingSummary.fromJson(response.data, _apiRoot);
  }

  Future<void> deleteListing({
    required String listingId,
    required String bearerToken,
  }) async {
    await _apiClient.deleteJson(
      '/listings/$listingId',
      bearerToken: bearerToken,
    );
  }
}
