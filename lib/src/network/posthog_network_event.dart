// ignore: unnecessary_import
import 'package:meta/meta.dart';

import 'package:posthog_flutter/src/posthog.dart';
import 'package:posthog_flutter/src/replay/native_communicator.dart';

@internal
class PostHogNetworkCapture {
  static final _instance = PostHogNetworkCapture._();
  final _communicator = NativeCommunicator();

  PostHogNetworkCapture._();

  factory PostHogNetworkCapture() => _instance;

  Future<void> captureNetworkEvent({
    required String url,
    required String method,
    required int statusCode,
    required int startTimeMs,
    required int durationMs,
    required int transferSize,
  }) async {
    // Guard: captureNetworkTelemetry must be enabled
    final config = Posthog().config;
    if (config == null ||
        !config.sessionReplayConfig.captureNetworkTelemetry) {
      return;
    }

    // Guard: session replay must be active
    if (!await _communicator.isSessionReplayActive()) return;

    // Guard: filter PostHog API calls
    if (_isPostHogUrl(url, config.host)) return;

    final requestData = {
      'name': url,
      'method': method,
      'responseStatus': statusCode,
      'timestamp': startTimeMs,
      'duration': durationMs,
      'transferSize': transferSize >= 0 ? transferSize : 0,
      'initiatorType': 'fetch',
      'entryType': 'resource',
    };

    await _communicator.sendNetworkEvent(requestData);
  }

  bool _isPostHogUrl(String url, String host) {
    try {
      final requestUri = Uri.parse(url);
      final hostUri = Uri.parse(host);
      return requestUri.host == hostUri.host;
    } catch (_) {
      return false;
    }
  }
}
