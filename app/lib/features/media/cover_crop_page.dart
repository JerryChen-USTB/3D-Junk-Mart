import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../theme/app_colors.dart';

const double _listingCoverAspectRatio = 220 / 168;

Future<XFile?> pickAndCropCoverImage(
  BuildContext context, {
  required ImagePicker picker,
  required ImageSource source,
}) async {
  final image = await picker.pickImage(
    source: source,
    preferredCameraDevice: CameraDevice.rear,
    maxWidth: 2000,
    maxHeight: 2000,
    imageQuality: 90,
  );
  if (image == null || !context.mounted) {
    return null;
  }
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute<XFile>(
      builder: (_) => CoverCropPage(image: image),
      fullscreenDialog: true,
    ),
  );
}

class CoverCropPage extends StatefulWidget {
  const CoverCropPage({super.key, required this.image});

  final XFile image;

  @override
  State<CoverCropPage> createState() => _CoverCropPageState();
}

class _CoverCropPageState extends State<CoverCropPage> {
  ui.Image? _decodedImage;
  img.Image? _normalizedImage;
  Size _stageSize = Size.zero;
  Size _viewport = Size.zero;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.image.readAsBytes();
      final decodedSource = img.decodeImage(bytes);
      if (decodedSource == null) {
        throw StateError('无法解析图片文件');
      }
      final normalized = img.bakeOrientation(decodedSource);
      final outputFormat = _outputFormat;
      final normalizedBytes = outputFormat.extension == '.png'
          ? Uint8List.fromList(img.encodePng(normalized))
          : Uint8List.fromList(img.encodeJpg(normalized, quality: 96));
      final decoded = await decodeImageFromList(normalizedBytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _decodedImage = decoded;
        _normalizedImage = normalized;
        _zoom = 1;
        _offset = Offset.zero;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '加载封面失败：$error';
      });
    }
  }

  Size get _imageSize {
    final decoded = _decodedImage;
    if (decoded == null) {
      return Size.zero;
    }
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  ({String extension, String mimeType}) get _outputFormat {
    final path = widget.image.path.toLowerCase();
    if (path.endsWith('.png')) {
      return (extension: '.png', mimeType: 'image/png');
    }
    return (extension: '.jpg', mimeType: 'image/jpeg');
  }

  double get _baseScale {
    final imageSize = _imageSize;
    if (_viewport == Size.zero || imageSize == Size.zero) {
      return 1;
    }
    return math.max(
      _viewport.width / imageSize.width,
      _viewport.height / imageSize.height,
    );
  }

  Size get _baseDisplaySize {
    final imageSize = _imageSize;
    final scale = _baseScale;
    return Size(imageSize.width * scale, imageSize.height * scale);
  }

  Offset _clampOffset(Offset candidate, double zoom) {
    final size = _baseDisplaySize;
    if (_viewport == Size.zero || size == Size.zero) {
      return candidate;
    }
    final displayWidth = size.width * zoom;
    final displayHeight = size.height * zoom;
    final maxDx = math.max(0.0, (displayWidth - _viewport.width) / 2);
    final maxDy = math.max(0.0, (displayHeight - _viewport.height) / 2);
    return Offset(
      candidate.dx.clamp(-maxDx, maxDx).toDouble(),
      candidate.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  Rect _cropRect(Size stageSize) {
    if (stageSize == Size.zero) {
      return Rect.zero;
    }
    final maxFrameWidth = math.max(120.0, stageSize.width - 24);
    final maxFrameHeight = math.max(120.0, stageSize.height - 24);
    var width = maxFrameWidth;
    var height = width / _listingCoverAspectRatio;
    if (height > maxFrameHeight) {
      height = maxFrameHeight;
      width = height * _listingCoverAspectRatio;
    }
    return Rect.fromCenter(
      center: stageSize.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  Future<void> _export() async {
    final image = _normalizedImage;
    if (image == null || _decodedImage == null || _stageSize == Size.zero) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final baseScale = _baseScale;
      final displayScale = baseScale * _zoom;
      final displaySize = _baseDisplaySize;
      final displayWidth = displaySize.width * _zoom;
      final displayHeight = displaySize.height * _zoom;
      final cropRect = _cropRect(_stageSize);
      final topLeft = Offset(
        cropRect.center.dx - displayWidth / 2 + _offset.dx,
        cropRect.center.dy - displayHeight / 2 + _offset.dy,
      );

      final cropX = ((cropRect.left - topLeft.dx) / displayScale).round().clamp(
        0,
        math.max(image.width - 1, 0),
      ).toInt();
      final cropY = ((cropRect.top - topLeft.dy) / displayScale).round().clamp(
        0,
        math.max(image.height - 1, 0),
      ).toInt();
      final cropWidth = (cropRect.width / displayScale).round().clamp(
        1,
        image.width - cropX,
      ).toInt();
      final cropHeight = (cropRect.height / displayScale).round().clamp(
        1,
        image.height - cropY,
      ).toInt();

      final cropped = img.copyCrop(
        image,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );
      final outputFormat = _outputFormat;
      final output = outputFormat.extension == '.png'
          ? img.encodePng(cropped)
          : img.encodeJpg(cropped, quality: 92);
      final file = File(
        '${Directory.systemTemp.path}\\junk_mart_cover_${DateTime.now().microsecondsSinceEpoch}${outputFormat.extension}',
      );
      await file.writeAsBytes(output, flush: true);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        XFile(
          file.path,
          name: file.uri.pathSegments.last,
          mimeType: outputFormat.mimeType,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '处理封面失败：$error';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decodedImage;
    return Scaffold(
      appBar: AppBar(
        title: const Text('调整封面'),
        actions: [
          TextButton(
            onPressed: _saving || decoded == null ? null : _export,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
        ],
      ),
      body: SafeArea(
        child: decoded == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: AppColors.coral),
                        ),
                      ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final stageMaxWidth = math.max(240.0, constraints.maxWidth - 32);
                  final stageMaxHeight = math.max(
                    280.0,
                    constraints.maxHeight - 220,
                  );
                  var stageWidth = stageMaxWidth;
                  var stageHeight = math.min(stageMaxHeight, stageWidth * 1.08);
                  if (stageHeight > stageMaxHeight) {
                    stageHeight = stageMaxHeight;
                  }
                  if (stageHeight < 260) {
                    stageHeight = 260;
                  }
                  final stageSize = Size(stageWidth, stageHeight);
                  final viewport = _cropRect(stageSize).size;
                  if (_viewport != viewport || _stageSize != stageSize) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _stageSize = stageSize;
                        _viewport = viewport;
                        _offset = _clampOffset(_offset, _zoom);
                      });
                    });
                  }

                  final displaySize = _baseDisplaySize;
                  final cropRect = _cropRect(stageSize);

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '拖动图片，把商品对齐到中间的显示框内。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '白色边框内就是商品卡片里最终显示的横向封面区域。图片本身保持原比例，只裁切范围。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: Center(
                            child: Container(
                              width: stageWidth,
                              height: stageHeight,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x18000000),
                                    blurRadius: 24,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (details) {
                                  setState(() {
                                    _offset = _clampOffset(
                                      _offset + details.delta,
                                      _zoom,
                                    );
                                  });
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.black,
                                            Colors.black.withValues(alpha: 0.8),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: _CoverPreviewPainter(
                                          image: _decodedImage,
                                          cropRect: cropRect,
                                          displaySize: displaySize,
                                          zoom: _zoom,
                                          offset: _offset,
                                        ),
                                        size: stageSize,
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: _CropStagePainter(cropRect),
                                        size: stageSize,
                                      ),
                                    ),
                                    Positioned(
                                      left: cropRect.left + 14,
                                      top: cropRect.top + 14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.88),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          '封面显示区域',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(
                              Icons.pan_tool_alt_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '拖动对齐',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 18),
                            const Icon(
                              Icons.zoom_in_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: _zoom,
                                min: 1,
                                max: 3,
                                divisions: 20,
                                label: '${(_zoom * 100).round()}%',
                                onChanged: (value) {
                                  setState(() {
                                    _zoom = value;
                                    _offset = _clampOffset(_offset, _zoom);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.coral,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving ? null : _export,
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('使用此封面'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CropStagePainter extends CustomPainter {
  const _CropStagePainter(this.cropRect);

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (cropRect == Rect.zero) {
      return;
    }

    const radius = Radius.circular(24);
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.32);
    final fullPath = Path()..addRect(Offset.zero & size);
    final cropPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cropRect, radius),
      );
    final mask = Path.combine(PathOperation.difference, fullPath, cropPath);
    canvas.drawPath(mask, overlay);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect, radius),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropStagePainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

class _CoverPreviewPainter extends CustomPainter {
  const _CoverPreviewPainter({
    required this.image,
    required this.cropRect,
    required this.displaySize,
    required this.zoom,
    required this.offset,
  });

  final ui.Image? image;
  final Rect cropRect;
  final Size displaySize;
  final double zoom;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null || cropRect == Rect.zero || displaySize == Size.zero) {
      return;
    }

    final clip = RRect.fromRectAndRadius(cropRect, const Radius.circular(24));
    canvas.save();
    canvas.clipRRect(clip);
    canvas.drawRect(cropRect, Paint()..color = Colors.black);

    final destRect = Rect.fromCenter(
      center: cropRect.center + offset,
      width: displaySize.width * zoom,
      height: displaySize.height * zoom,
    );
    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(
        0,
        0,
        image!.width.toDouble(),
        image!.height.toDouble(),
      ),
      destRect,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CoverPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.displaySize != displaySize ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offset != offset;
  }
}
