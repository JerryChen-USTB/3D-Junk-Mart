import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ViewerPage extends StatelessWidget {
  const ViewerPage({
    super.key,
    required this.viewerUrl,
    required this.title,
    this.additionalQueryParameters = const <String, String>{},
  });

  final String viewerUrl;
  final String title;
  final Map<String, String> additionalQueryParameters;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
    this.additionalQueryParameters = const <String, String>{},
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
  int _progress = 0;

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
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) {
              return;
            }
            setState(() {
              _progress = progress;
            });
          },
        ),
      );
    _load();
  }

  @override
  void didUpdateWidget(covariant ViewerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerUrl != widget.viewerUrl ||
        !mapEquals(
          oldWidget.additionalQueryParameters,
          widget.additionalQueryParameters,
        )) {
      _load();
    }
  }

  Future<void> _load() async {
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
        if (widget.showLoadingBar && _progress < 100)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(value: _progress / 100),
          ),
      ],
    );
  }
}
