import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      baseUrl = _normalizeBaseUrl(baseUrl ?? _configuredBaseUrl);

  final http.Client _httpClient;
  final String baseUrl;

  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String _normalizeBaseUrl(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/api/v1')) {
      return trimmed;
    }
    if (trimmed.endsWith('/api')) {
      return '$trimmed/v1';
    }
    return '$trimmed/api/v1';
  }

  Uri _uri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  Future<ApiEnvelope<Map<String, dynamic>>> getJson(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _httpClient.get(
      _uri(path, queryParameters),
      headers: _headers(bearerToken),
    );
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  Future<ApiEnvelope<Object?>> getObject(
    String path, {
    String? bearerToken,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _httpClient.get(
      _uri(path, queryParameters),
      headers: _headers(bearerToken),
    );
    return _decodeEnvelope<Object?>(response, (value) => value);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> postJson(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers(bearerToken),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  Future<ApiEnvelope<Map<String, dynamic>>> patchJson(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    final response = await _httpClient.patch(
      _uri(path),
      headers: _headers(bearerToken),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  Future<ApiEnvelope<Map<String, dynamic>>> putJson(
    String path, {
    Object? body,
    String? bearerToken,
  }) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: _headers(bearerToken),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  Future<ApiEnvelope<Map<String, dynamic>>> deleteJson(
    String path, {
    String? bearerToken,
  }) async {
    final response = await _httpClient.delete(
      _uri(path),
      headers: _headers(bearerToken),
    );
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  /// Upload a file via multipart POST and return the decoded envelope.
  Future<ApiEnvelope<Map<String, dynamic>>> uploadFile(
    String path, {
    required String filePath,
    required String fieldName,
    String? bearerToken,
  }) async {
    final uri = _uri(path);
    final request = http.MultipartRequest('POST', uri);
    if (bearerToken != null && bearerToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearerToken';
    }
    request.headers['Accept'] = 'application/json';

    // Determine MIME type from file extension.
    final lower = filePath.toLowerCase();
    MediaType contentType;
    if (lower.endsWith('.png')) {
      contentType = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      contentType = MediaType('image', 'webp');
    } else if (lower.endsWith('.gif')) {
      contentType = MediaType('image', 'gif');
    } else {
      contentType = MediaType('image', 'jpeg');
    }

    request.files.add(await http.MultipartFile.fromPath(
      fieldName,
      filePath,
      contentType: contentType,
    ));
    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decodeEnvelope<Map<String, dynamic>>(
      response,
      (value) => value is Map<String, dynamic> ? value : <String, dynamic>{},
    );
  }

  Map<String, String> _headers(String? bearerToken) {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      if (bearerToken != null && bearerToken.isNotEmpty)
        'Authorization': 'Bearer $bearerToken',
    };
  }

  ApiEnvelope<T> _decodeEnvelope<T>(
    http.Response response,
    T Function(Object? value) dataFactory,
  ) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic> && decoded.containsKey('code')) {
        return ApiEnvelope<T>.fromJson(decoded, dataFactory);
      }

      return ApiEnvelope<T>(
        code: 0,
        message: 'ok',
        data: dataFactory(decoded),
        meta: const <String, dynamic>{},
      );
    }

    if (decoded is Map<String, dynamic> && decoded.containsKey('code')) {
      throw ApiException.fromEnvelope(
        statusCode: response.statusCode,
        envelope: ApiEnvelope<Object?>.fromJson(decoded, (value) => value),
      );
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: response.reasonPhrase ?? 'request failed',
      rawBody: response.body,
    );
  }
}

class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.code,
    required this.message,
    required this.data,
    required this.meta,
    this.errors = const <Map<String, dynamic>>[],
  });

  final int code;
  final String message;
  final T data;
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> errors;

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Object? value) dataFactory,
  ) {
    final errors = <Map<String, dynamic>>[];
    final rawErrors = json['errors'];
    if (rawErrors is List) {
      for (final item in rawErrors) {
        if (item is Map<String, dynamic>) {
          errors.add(item);
        }
      }
    }

    return ApiEnvelope<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: json['message']?.toString() ?? '',
      data: dataFactory(json['data']),
      meta:
          (json['meta'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      errors: errors,
    );
  }
}

class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.rawBody,
    this.serverCode,
  });

  factory ApiException.fromEnvelope({
    required int statusCode,
    required ApiEnvelope<Object?> envelope,
  }) {
    return ApiException(
      statusCode: statusCode,
      message: envelope.message,
      rawBody: null,
      serverCode: envelope.code,
    );
  }

  final int statusCode;
  final int? serverCode;
  final String message;
  final String? rawBody;

  @override
  String toString() {
    final codePart = serverCode == null ? '' : ' serverCode=$serverCode';
    return 'ApiException(statusCode=$statusCode$codePart, message=$message)';
  }
}
