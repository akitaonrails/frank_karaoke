import 'dart:convert';
import 'package:flutter/services.dart';

/// Method channel controller for the native WebKitGTK webview on Linux.
class LinuxWebViewController {
  static const _channel = MethodChannel('frank_karaoke/webview');

  final Map<String, Function(List<dynamic>)> _handlers = {};

  Future<void> create({required String url, String? userAgent}) async {
    await _channel.invokeMethod('create', {
      'url': url,
      // ignore: use_null_aware_elements
      if (userAgent != null) 'userAgent': userAgent,
    });
  }

  /// Set the webview margins (top/bottom inset within the overlay).
  Future<void> setFrame({double top = 0, double bottom = 0}) async {
    await _channel.invokeMethod('setFrame', {
      'top': top,
      'bottom': bottom,
    });
  }

  Future<dynamic> evaluateJavascript({required String source}) async {
    return _channel.invokeMethod('evaluateJavascript', {'source': source});
  }

  void addJavaScriptHandler({
    required String handlerName,
    required Function(List<dynamic>) callback,
  }) {
    _handlers[handlerName] = callback;
    _channel.invokeMethod('addJavaScriptHandler', {'name': handlerName});
  }

  void dispatchHandler(String name, String argsJson) {
    final handler = _handlers[name];
    if (handler == null) return;
    try {
      final decoded = jsonDecode(argsJson);
      handler(decoded is List ? decoded : [decoded]);
    } catch (_) {
      handler([argsJson]);
    }
  }

  /// Show or hide the native webview.
  Future<void> setVisible(bool visible) async {
    await _channel.invokeMethod('setVisible', {'visible': visible});
  }

  Future<void> destroy() async {
    await _channel.invokeMethod('destroy');
    _handlers.clear();
  }
}
