import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class NativeCameraService {
  NativeCameraService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.mobile_app/native_camera',
  );

  static Future<XFile?> captureHighQualityVideo({
    Duration maxDuration = const Duration(seconds: 60),
  }) async {
    final path = await _channel.invokeMethod<String>(
      'captureHighQualityVideo',
      {'maxDurationSeconds': maxDuration.inSeconds},
    );
    if (path == null || path.isEmpty) {
      return null;
    }
    return XFile(path);
  }
}
