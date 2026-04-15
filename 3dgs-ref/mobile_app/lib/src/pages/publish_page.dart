import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/native_camera_service.dart';
import 'task_library_page.dart';
import 'task_status_page.dart';
import 'viewer_page.dart';

class PublishPage extends StatefulWidget {
  const PublishPage({super.key});

  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  static const _defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController(text: '99.00');
  final _apiBaseUrlController = TextEditingController(text: _defaultApiBaseUrl);
  final _picker = ImagePicker();

  XFile? _selectedVideo;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _apiBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    XFile? video;
    try {
      video = source == ImageSource.camera
          ? await NativeCameraService.captureHighQualityVideo()
          : await _picker.pickVideo(source: source);
    } on MissingPluginException {
      video = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(seconds: 60),
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '打开系统相机失败：${error.message ?? error.code}';
      });
      return;
    }
    if (video == null || !mounted) {
      return;
    }

    setState(() {
      _selectedVideo = video;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedVideo == null) {
      setState(() {
        _errorMessage = '请先选择或拍摄一段商品视频。';
      });
      return;
    }

    final apiBaseUrl = _apiBaseUrlController.text.trim();
    if (apiBaseUrl.isEmpty) {
      setState(() {
        _errorMessage = '请填写后端地址。';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final client = ApiClient(apiBaseUrl);
      final task = await client.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: _priceController.text.trim(),
        video: _selectedVideo!,
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskStatusPage(client: client, initialTask: task),
        ),
      );
    } catch (error) {
      setState(() {
        _errorMessage = _formatSubmitError(error, apiBaseUrl);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatSubmitError(Object error, String apiBaseUrl) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError) {
        if (apiBaseUrl.contains('10.0.2.2')) {
          return '连接后端超时。你当前大概率是在 Android 真机上运行，'
              '10.0.2.2 只适用于 Android 模拟器。请把后端地址改成电脑局域网 IP，'
              '例如 http://192.168.1.23:8000，并确保后端使用 0.0.0.0:8000 启动。';
        }
        return '连接后端超时。请确认手机和电脑在同一局域网，后端地址填写的是电脑 IP，'
            '后端使用 0.0.0.0:8000 启动，并且 Windows 防火墙已放行 8000 端口。';
      }

      final responseData = error.response?.data;
      if (responseData is Map<String, dynamic> &&
          responseData['detail'] != null) {
        return '上传失败：${responseData['detail']}';
      }
      if (responseData is String && responseData.trim().isNotEmpty) {
        return '上传失败：$responseData';
      }
    }

    return '上传失败：$error';
  }

  Future<void> _openTaskLibrary() async {
    final apiBaseUrl = _apiBaseUrlController.text.trim();
    if (apiBaseUrl.isEmpty) {
      setState(() {
        _errorMessage = '请先填写后端地址，再查看已生成模型。';
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskLibraryPage(client: ApiClient(apiBaseUrl)),
      ),
    );
  }

  Future<void> _openModelCache() async {
    final apiBaseUrl = _apiBaseUrlController.text.trim();
    if (apiBaseUrl.isEmpty) {
      setState(() {
        _errorMessage = '请先填写后端地址，再管理模型缓存。';
      });
      return;
    }

    final client = ApiClient(apiBaseUrl);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ViewerPage(viewerUrl: client.viewerCacheUrl, taskTitle: '模型缓存管理'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedVideoName = _selectedVideo?.name ?? '尚未选择视频';

    return Scaffold(
      appBar: AppBar(
        title: const Text('3DGS 商品发布'),
        actions: [
          IconButton(
            onPressed: _openTaskLibrary,
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: '查看已生成模型',
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionTitle(
                title: '本地 MVP 入口',
                subtitle: '先上传商品视频创建 task_id，再在训练设置中手动启动流水线。',
              ),
              TextFormField(
                controller: _apiBaseUrlController,
                decoration: const InputDecoration(
                  labelText: '后端地址',
                  helperText:
                      '模拟器用 http://10.0.2.2:8000；真机请改成电脑局域网 IP，例如 http://192.168.1.23:8000',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入后端地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _openTaskLibrary,
                icon: const Icon(Icons.view_in_ar_outlined),
                label: const Text('查看已训练模型'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openModelCache,
                icon: const Icon(Icons.storage_outlined),
                label: const Text('管理模型缓存'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: '商品标题'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入商品标题';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: '商品描述'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: '价格'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入价格';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '拍摄素材',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedVideoName,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _isSubmitting
                                ? null
                                : () => _pickVideo(ImageSource.gallery),
                            child: const Text('从相册选择'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => _pickVideo(ImageSource.camera),
                            child: const Text('原生相机录制'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_isSubmitting ? '上传中...' : '创建重建任务并进入设置'),
              ),
              const SizedBox(height: 12),
              const Text(
                '当前 App 只覆盖最小闭环：发布、状态轮询、WebView 查看器。真实 3DGS 训练需要先把 COLMAP 和 nerfstudio 环境补齐。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
