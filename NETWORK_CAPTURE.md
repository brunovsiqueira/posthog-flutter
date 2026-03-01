# Network Capture for Flutter Session Replay

## Problem

Flutter session replays have no network tab. The Android SDK captures HTTP calls via `PostHogOkHttpInterceptor`, but Flutter apps use Dart-level HTTP clients (`package:http`, Dio), not OkHttp or URLSession. The iOS plugin explicitly disables `captureNetworkTelemetry`.

## What this branch does

Adds Dart-level HTTP interception via an opt-in `PostHogHttpClient` wrapper (same explicit-wrapping pattern as Android's `PostHogOkHttpInterceptor`). Captured data flows through the method channel to native SDKs as `rrweb/network@1` plugin events.

### Usage

```dart
import 'package:http/http.dart' as http;
import 'package:posthog_flutter/posthog_flutter.dart';

final client = PostHogHttpClient(http.Client());
final response = await client.get(Uri.parse('https://api.example.com/data'));
// Network event is automatically captured in session replay
```

### Config

```dart
final config = PostHogConfig('YOUR_API_KEY');
config.sessionReplay = true;
config.sessionReplayConfig.captureNetworkTelemetry = true; // default
```

## Architecture

```
PostHogHttpClient (wraps package:http Client)
  → PostHogNetworkCapture (guard checks + builds payload)
    → NativeCommunicator.sendNetworkEvent() (method channel)
      → Android: RRPluginEvent("rrweb/network@1", payload).capture()
      → iOS: Manual $snapshot event with type:6 plugin data
```

## Files changed

| File | Change |
|------|--------|
| `lib/src/posthog_config.dart` | Added `captureNetworkTelemetry` flag |
| `lib/src/replay/native_communicator.dart` | Added `sendNetworkEvent()` |
| `lib/src/network/posthog_network_event.dart` | **New** - shared capture logic with guards |
| `lib/src/network/posthog_http_client.dart` | **New** - `BaseClient` wrapper |
| `android/.../PosthogFlutterPlugin.kt` | Added `sendNetworkEvent` handler |
| `android/.../SnapshotSender.kt` | Added `sendNetworkEvent()` using `RRPluginEvent` |
| `ios/Classes/PosthogFlutterPlugin.swift` | Added `sendNetworkEvent` handler |
| `lib/posthog_flutter.dart` | Exported `PostHogHttpClient` |
| `pubspec.yaml` | Added `http` dependency |

## Guard conditions

- `captureNetworkTelemetry` config flag (local, default true)
- `isSessionReplayActive()` (native check)
- PostHog API URL filtering (skips requests to PostHog host)
- Remote config guard (`isNetworkCaptureEnabled`) — **deferred**, not yet plumbed in Flutter

## Still TODO

- [ ] Unit tests for `PostHogHttpClient` and `PostHogNetworkCapture`
- [ ] Manual verification in example app
- [ ] Dio interceptor (deferred — separate package or optional dep)
- [ ] Remote config guard for network capture
