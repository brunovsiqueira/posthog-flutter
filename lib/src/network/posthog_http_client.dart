import 'package:http/http.dart';

import 'posthog_network_event.dart';

/// An HTTP client wrapper that captures network telemetry for PostHog session replay.
///
/// Wraps any `package:http` [Client] and automatically records HTTP requests
/// as `rrweb/network@1` events when session replay is active and
/// `captureNetworkTelemetry` is enabled.
///
/// **Usage:**
/// ```dart
/// import 'package:http/http.dart' as http;
/// import 'package:posthog_flutter/posthog_flutter.dart';
///
/// final client = PostHogHttpClient(http.Client());
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// ```
///
/// Network events captured include: URL, HTTP method, status code, duration,
/// and transfer size. PostHog API calls are automatically filtered out.
class PostHogHttpClient extends BaseClient {
  final Client _inner;
  final PostHogNetworkCapture _capture;

  /// Creates a new [PostHogHttpClient] wrapping the given [inner] client.
  PostHogHttpClient(Client inner)
      : _inner = inner,
        _capture = PostHogNetworkCapture();

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();

    final response = await _inner.send(request);

    stopwatch.stop();

    final requestSize = request.contentLength ?? 0;
    final responseSize = response.contentLength ?? 0;
    final transferSize = requestSize + responseSize;

    // Fire-and-forget: don't block the response on network event capture
    _capture.captureNetworkEvent(
      url: request.url.toString(),
      method: request.method,
      statusCode: response.statusCode,
      startTimeMs: startTime,
      durationMs: stopwatch.elapsedMilliseconds,
      transferSize: transferSize,
    );

    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
