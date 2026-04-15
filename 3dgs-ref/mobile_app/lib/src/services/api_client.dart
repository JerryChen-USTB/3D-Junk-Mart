import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../models/reconstruction_task.dart';

class ApiClient {
  ApiClient(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;
  String get viewerCacheUrl =>
      Uri.parse(baseUrl).resolve('/viewer/cache.html').toString();

  Future<ReconstructionTask> createTask({
    required String title,
    required String description,
    required String price,
    required XFile video,
  }) async {
    final formData = FormData.fromMap({
      'title': title,
      'description': description,
      'price': price,
      'video': await MultipartFile.fromFile(video.path, filename: video.name),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions',
      data: formData,
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> fetchTask(String taskId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId',
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> startPipeline({
    required String taskId,
    required String qualityProfile,
    required int trainMaxSteps,
    bool objectMasking = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/pipeline/start',
      data: {
        'quality_profile': qualityProfile,
        'train_max_steps': trainMaxSteps,
        'object_masking': objectMasking,
      },
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> cancelPipeline(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/pipeline/cancel',
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> previewMaskPrompts({
    required String taskId,
    required List<Map<String, dynamic>> points,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/mask-preview',
      data: {'points': points},
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> confirmMaskPreview(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/mask-confirm',
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<ReconstructionTask> startMaskDebug(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/mask-debug',
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<Map<String, dynamic>> fetchMaskPreviewManifest(
    String manifestUrl,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(manifestUrl);
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> downloadFile(String url, String savePath) async {
    await _dio.download(url, savePath, deleteOnError: true);
  }

  Future<List<ReconstructionTask>> fetchTasks({String? status}) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/reconstructions',
      queryParameters: status == null || status.isEmpty
          ? null
          : {'status': status},
    );

    final payload = response.data ?? const [];
    return payload
        .whereType<Map<String, dynamic>>()
        .map(ReconstructionTask.fromJson)
        .toList();
  }

  Future<ReconstructionTask> publishTask(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/publish',
    );

    return ReconstructionTask.fromJson(response.data!);
  }

  Future<void> deleteTask(String taskId) async {
    await _dio.delete<void>('/api/v1/reconstructions/$taskId');
  }

  Future<ReconstructionTask> updatePublishFlowState({
    required String taskId,
    bool? viewerRotationDone,
    bool? viewerTranslationDone,
    bool? viewerInitialViewDone,
    bool? viewerAnimationApproved,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/reconstructions/$taskId/publish-flow',
      data: {
        'viewer_rotation_done': viewerRotationDone,
        'viewer_translation_done': viewerTranslationDone,
        'viewer_initial_view_done': viewerInitialViewDone,
        'viewer_animation_approved': viewerAnimationApproved,
      },
    );

    return ReconstructionTask.fromJson(response.data!);
  }
}
