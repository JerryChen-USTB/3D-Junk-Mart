import '../api/api_client.dart';
import 'listing_models.dart';

class ListingsRepository {
  ListingsRepository(this._apiClient);

  final ApiClient _apiClient;

  Uri get _apiRoot => Uri.parse(_apiClient.baseUrl).resolve('/');
  Uri get apiRoot => _apiRoot;

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
    String? categoryId,
    String? sort,
    String? priceBucket,
    String? location,
    String? conditionLevel,
    bool only3d = false,
    bool onlyNegotiable = false,
    String? bearerToken,
  }) async {
    final response = await _apiClient.getObject(
      '/listings',
      bearerToken: bearerToken,
      queryParameters: <String, dynamic>{
        'page_size': limit,
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        if (sort != null && sort.isNotEmpty) 'sort': sort,
        if (priceBucket != null && priceBucket.isNotEmpty)
          'price_bucket': priceBucket,
        if (location != null && location.isNotEmpty) 'location': location,
        if (conditionLevel != null && conditionLevel.isNotEmpty)
          'condition_level': conditionLevel,
        if (only3d) 'only_3d': true,
        if (onlyNegotiable) 'only_negotiable': true,
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

  Future<Map<String, dynamic>> fetchHomePage({String? bearerToken}) async {
    final response = await _apiClient.getJson(
      '/pages/home',
      bearerToken: bearerToken,
    );
    return response.data;
  }

  Future<List<ListingSummary>> fetchHomeFeed({
    int limit = 20,
    String query = '',
    String? categoryId,
    String? sort,
    String? priceBucket,
    String? location,
    String? conditionLevel,
    bool only3d = false,
    bool onlyNegotiable = false,
    String? bearerToken,
  }) {
    return fetchListings(
      limit: limit,
      query: query,
      categoryId: categoryId,
      sort: sort,
      priceBucket: priceBucket,
      location: location,
      conditionLevel: conditionLevel,
      only3d: only3d,
      onlyNegotiable: onlyNegotiable,
      bearerToken: bearerToken,
    );
  }

  Future<Map<String, dynamic>> fetchSearchSuggestions({String query = ''}) async {
    final response = await _apiClient.getJson(
      '/search/suggestions',
      queryParameters: <String, dynamic>{
        if (query.trim().isNotEmpty) 'query': query.trim(),
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> fetchSearchFacets() async {
    final response = await _apiClient.getJson('/search/facets');
    return response.data;
  }

  Future<List<ListingSummary>> fetchFavoriteListings(String bearerToken) async {
    final response = await _apiClient.getObject(
      '/users/me/favorites',
      bearerToken: bearerToken,
      queryParameters: const <String, dynamic>{'page_size': 50},
    );
    final data = response.data;
    if (data is! List) {
      return const <ListingSummary>[];
    }
    return data
        .whereType<Map>()
        .map(
          (item) =>
              ListingSummary.fromJson(item.cast<String, dynamic>(), _apiRoot),
        )
        .toList(growable: false);
  }

  Future<bool> toggleFavorite({
    required String listingId,
    required String bearerToken,
    required bool isFavorited,
  }) async {
    if (isFavorited) {
      await _apiClient.deleteJson(
        '/listings/$listingId/favorite',
        bearerToken: bearerToken,
      );
      return false;
    }
    await _apiClient.postJson(
      '/listings/$listingId/favorite',
      bearerToken: bearerToken,
      body: const <String, dynamic>{},
    );
    return true;
  }

  Future<ListingDetail> fetchListingDetail(
    String listingId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.getObject(
      '/pages/listings/$listingId',
      bearerToken: bearerToken,
    );
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
