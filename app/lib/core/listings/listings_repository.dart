import '../api/api_client.dart';
import 'listing_models.dart';

class ListingsRepository {
  ListingsRepository(this._apiClient);

  final ApiClient _apiClient;

  Uri get _apiRoot => Uri.parse(_apiClient.baseUrl).resolve('/');

  Future<List<ListingSummary>> fetchListings({int limit = 20}) async {
    final response = await _apiClient.getObject(
      '/listings',
      queryParameters: <String, dynamic>{'limit': limit},
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
}
