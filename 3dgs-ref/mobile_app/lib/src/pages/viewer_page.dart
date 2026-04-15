import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ViewerPage extends StatelessWidget {
  const ViewerPage({
    super.key,
    required this.viewerUrl,
    required this.taskTitle,
    this.additionalQueryParameters = const {},
  });

  final String viewerUrl;
  final String taskTitle;
  final Map<String, String> additionalQueryParameters;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(taskTitle)),
      body: ViewerFrame(
        viewerUrl: viewerUrl,
        additionalQueryParameters: additionalQueryParameters,
      ),
    );
  }
}

class ViewerFrame extends StatefulWidget {
  const ViewerFrame({
    super.key,
    required this.viewerUrl,
    this.additionalQueryParameters = const {},
    this.showLoadingBar = true,
  });

  final String viewerUrl;
  final Map<String, String> additionalQueryParameters;
  final bool showLoadingBar;

  @override
  State<ViewerFrame> createState() => _ViewerFrameState();
}

class _ViewerFrameState extends State<ViewerFrame> {
  static const _viewerBuild = '20260408_43';
  final Set<Factory<OneSequenceGestureRecognizer>> _gestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };
  late final WebViewController _controller;
  int _loadingProgress = 0;

  Uri get _viewerUri {
    final original = Uri.parse(widget.viewerUrl);
    final query = Map<String, String>.from(original.queryParameters);
    query['viewer_build'] = _viewerBuild;
    query.addAll(widget.additionalQueryParameters);
    return original.replace(queryParameters: query);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loadingProgress = progress;
            });
          },
        ),
      );
    _prepareAndLoad();
  }

  @override
  void didUpdateWidget(covariant ViewerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerUrl != widget.viewerUrl ||
        !mapEquals(
          oldWidget.additionalQueryParameters,
          widget.additionalQueryParameters,
        )) {
      _prepareAndLoad();
    }
  }

  Future<void> _prepareAndLoad() async {
    await _controller.enableZoom(false);
    await _controller.loadRequest(_viewerUri);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: _gestureRecognizers,
        ),
        if (widget.showLoadingBar && _loadingProgress < 100)
          LinearProgressIndicator(value: _loadingProgress / 100),
      ],
    );
  }
}
