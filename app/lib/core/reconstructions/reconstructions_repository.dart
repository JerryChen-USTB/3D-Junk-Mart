// ignore_for_file: use_null_aware_elements

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import 'reconstruction_models.dart';

class ReconstructionsRepository {
  ReconstructionsRepository(this._apiClient, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final ApiClient _apiClient;
  final http.Client _httpClient;

  Uri get _apiRoot => Uri.parse(_apiClient.baseUrl).resolve('/');

  Uri _endpoint(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${_apiClient.baseUrl}$normalizedPath').replace(
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  Map<String, String> _authHeaders(String? bearerToken) {
    return <String, String>{
      'Accept': 'application/json',
      if (bearerToken != null && bearerToken.isNotEmpty)
        'Authorization': 'Bearer $bearerToken',
    };
  }

  Future<ReconstructionTask> createTask({
    required String title,
    required String description,
    required String price,
    required XFile video,
    String? bearerToken,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _endpoint('/reconstructions'),
    );
    request.headers.addAll(_authHeaders(bearerToken));
    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['price'] = price;
    final filename = video.name.isEmpty ? 'capture.mp4' : video.name;
    final ext = filename.split('.').last.toLowerCase();
    final mimeSubtype = const {'mp4': 'mp4', 'mov': 'quicktime', 'avi': 'x-msvideo', 'mkv': 'x-matroska', 'webm': 'webm'}[ext] ?? 'mp4';
    request.files.add(
      await http.MultipartFile.fromPath(
        'video',
        video.path,
        filename: filename,
        contentType: MediaType('video', mimeSubtype),
      ),
    );

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    final payload = _decodeMap(response);
    return ReconstructionTask.fromJson(payload, _apiRoot);
  }

  Future<ReconstructionTask> fetchTask(
    String taskId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.getObject(
      '/reconstructions/$taskId',
      bearerToken: bearerToken,
      queryParameters: <String, dynamic>{
        '_': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Task detail payload is not a JSON object.');
    }
    return ReconstructionTask.fromJson(data, _apiRoot);
  }

  Future<List<ReconstructionTask>> fetchTasks({
    String? status,
    String? bearerToken,
  }) async {
    final response = await _apiClient.getObject(
      '/reconstructions',
      bearerToken: bearerToken,
      queryParameters: status == null || status.isEmpty
          ? null
          : <String, dynamic>{'status': status},
    );
    final data = response.data;
    if (data is! List) {
      return const <ReconstructionTask>[];
    }
    return data
        .whereType<Map>()
        .map(
          (item) => ReconstructionTask.fromJson(
            item.cast<String, dynamic>(),
            _apiRoot,
          ),
        )
        .toList(growable: false);
  }

  Future<ReconstructionTask> startPipeline({
    required String taskId,
    required String qualityProfile,
    required int trainMaxSteps,
    required bool objectMasking,
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/pipeline/start',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'quality_profile': qualityProfile,
        'train_max_steps': trainMaxSteps,
        'object_masking': objectMasking,
      },
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> cancelPipeline(
    String taskId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/pipeline/cancel',
      bearerToken: bearerToken,
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> startMaskDebug(
    String taskId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/mask-debug',
      bearerToken: bearerToken,
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> previewMaskPrompts({
    required String taskId,
    required List<MaskPromptPoint> points,
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/mask-preview',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        'points': points.map((item) => item.toJson()).toList(growable: false),
      },
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> confirmMaskPreview(
    String taskId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/mask-confirm',
      bearerToken: bearerToken,
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> publishTask(
    String taskId, {
    String? bearerToken,
  }) async {
    final response = await _apiClient.postJson(
      '/reconstructions/$taskId/publish',
      bearerToken: bearerToken,
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<ReconstructionTask> updatePublishFlowState({
    required String taskId,
    bool? viewerRotationDone,
    bool? viewerTranslationDone,
    bool? viewerInitialViewDone,
    bool? viewerAnimationApproved,
    String? bearerToken,
  }) async {
    final response = await _apiClient.putJson(
      '/reconstructions/$taskId/publish-flow',
      bearerToken: bearerToken,
      body: <String, dynamic>{
        if (viewerRotationDone != null)
          'viewer_rotation_done': viewerRotationDone,
        if (viewerTranslationDone != null)
          'viewer_translation_done': viewerTranslationDone,
        if (viewerInitialViewDone != null)
          'viewer_initial_view_done': viewerInitialViewDone,
        if (viewerAnimationApproved != null)
          'viewer_animation_approved': viewerAnimationApproved,
      },
    );
    return ReconstructionTask.fromJson(response.data, _apiRoot);
  }

  Future<MaskPreviewManifest> fetchMaskPreviewManifest(
    String manifestUrl,
  ) async {
    final response = await _httpClient.get(Uri.parse(manifestUrl));
    final payload = _decodeMap(response);
    return MaskPreviewManifest.fromJson(payload, Uri.parse(manifestUrl));
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final payload = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (payload is! Map<String, dynamic>) {
        throw StateError(
          'Expected a JSON object but received ${payload.runtimeType}.',
        );
      }
      return payload;
    }

    if (payload is Map<String, dynamic>) {
      final detail = payload['detail'] ?? payload['message'];
      if (detail != null) {
        throw ApiException(
          statusCode: response.statusCode,
          message: detail.toString(),
          rawBody: response.body,
        );
      }
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: response.reasonPhrase ?? 'request failed',
      rawBody: response.body,
    );
  }
}
