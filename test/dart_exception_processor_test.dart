// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_exception.dart';

void main() {
  group('DartExceptionProcessor', () {
    test('processes exception with correct properties', () {
      final mainException = StateError('Test exception message');
      final stackTrace = StackTrace.fromString('''
#0      Object.noSuchMethod (package:posthog-flutter:1884:25)
#1      Trace.terse.<anonymous closure> (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/src/trace.dart:47:21)
#2      IterableMixinWorkaround.reduce (dart:collection:29:29)
#3      List.reduce (dart:core-patch:1247:42)
#4      Trace.terse (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/src/trace.dart:40:35)
#5      format (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/stack_trace.dart:24:28)
#6      main.<anonymous closure> (file:///usr/local/google-old/home/goog/dart/dart/test.dart:21:29)
#7      _CatchErrorFuture._sendError (dart:async:525:24)
#8      _FutureImpl._setErrorWithoutAsyncTrace (dart:async:393:26)
#9      _FutureImpl._setError (dart:async:378:31)
#10     _ThenFuture._sendValue (dart:async:490:16)
#11     _FutureImpl._handleValue.<anonymous closure> (dart:async:349:28)
#12     Timer.run.<anonymous closure> (dart:async:2402:21)
#13     Timer.Timer.<anonymous closure> (dart:async-patch:15:15)
''');

      final additionalProperties = {'custom_key': 'custom_value'};

      // Process the exception
      final result = DartExceptionProcessor.processException(
        error: mainException,
        stackTrace: stackTrace,
        properties: additionalProperties,
        inAppIncludes: ['posthog_flutter_example'],
        inAppExcludes: [],
        inAppByDefault: true,
      );

      // Verify basic structure
      expect(result, isA<Map<String, dynamic>>());
      expect(result.containsKey('\$exception_level'), isTrue);
      expect(result.containsKey('\$exception_list'), isTrue);
      expect(
          result.containsKey('custom_key'), isTrue); // Properties are in root

      // Verify custom properties are preserved
      expect(result['custom_key'], equals('custom_value'));

      // Verify exception list structure
      final exceptionList =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      expect(exceptionList, isNotEmpty);

      final mainExceptionData = exceptionList.first;

      // Verify main exception structure
      expect(mainExceptionData['type'], equals('StateError'));
      expect(
          mainExceptionData['value'],
          equals(
              'Bad state: Test exception message')); // StateError adds prefix
      expect(mainExceptionData['thread_id'],
          isA<int>()); // Should be hash-based thread ID

      // Verify mechanism structure
      final mechanism = mainExceptionData['mechanism'] as Map<String, dynamic>;
      expect(mechanism['handled'], isTrue);
      expect(mechanism['synthetic'], isFalse);
      expect(mechanism['type'], equals('generic'));

      // Verify stack trace structure
      final stackTraceData =
          mainExceptionData['stacktrace'] as Map<String, dynamic>;
      expect(stackTraceData['type'], equals('raw'));

      final frames = stackTraceData['frames'] as List<Map<String, dynamic>>;
      expect(frames, isNotEmpty);

      // Verify first frame structure (should be main function)
      final firstFrame = frames.first;
      expect(firstFrame.containsKey('function'), isTrue);
      expect(firstFrame.containsKey('filename'), isTrue);
      expect(firstFrame.containsKey('lineno'), isTrue);
      expect(firstFrame['platform'], equals('dart'));

      // Verify inApp detection works - just check that the field exists and is boolean
      expect(firstFrame['in_app'], isTrue);

      // Check that dart core frames are marked as not inApp
      final dartFrame = frames.firstWhere(
        (frame) =>
            frame['package'] == null &&
            (frame['abs_path']?.contains('dart:') == true),
        orElse: () => <String, dynamic>{},
      );
      if (dartFrame.isNotEmpty) {
        expect(dartFrame['in_app'], isFalse);
      }
    });

    test('handles inAppIncludes configuration correctly', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('''
#0      main (package:my_app/main.dart:25:7)
#1      helper (package:third_party/helper.dart:10:5)
#2      core (dart:core/core.dart:100:10)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: ['my_app'],
        inAppExcludes: [],
        inAppByDefault: false, // third_party is not included
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find frames by package
      final myAppFrame = frames.firstWhere((f) => f['package'] == 'my_app');
      final thirdPartyFrame =
          frames.firstWhere((f) => f['package'] == 'third_party');

      // Verify inApp detection
      expect(myAppFrame['in_app'], isTrue); // Explicitly included
      expect(thirdPartyFrame['in_app'], isFalse); // Not included
    });

    test('handles inAppExcludes configuration correctly', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('''
#0      main (package:my_app/main.dart:25:7)
#1      analytics (package:analytics_lib/tracker.dart:50:3)
#2      helper (package:helper_lib/utils.dart:15:8)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: [],
        inAppExcludes: ['analytics_lib'],
        inAppByDefault: true, // all inApp except inAppExcludes
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find frames by package
      final myAppFrame = frames.firstWhere((f) => f['package'] == 'my_app');
      final analyticsFrame =
          frames.firstWhere((f) => f['package'] == 'analytics_lib');
      final helperFrame =
          frames.firstWhere((f) => f['package'] == 'helper_lib');

      // Verify inApp detection
      expect(myAppFrame['in_app'], isTrue); // Default true, not excluded
      expect(analyticsFrame['in_app'], isFalse); // Explicitly excluded
      expect(helperFrame['in_app'], isTrue); // Default true, not excluded
    });

    test('gives precedence to inAppIncludes over inAppExcludes', () {
      // Test the precedence logic directly with a simple scenario
      final exception = Exception('Test exception');
      final stackTrace =
          StackTrace.fromString('#0 test (package:test_package/test.dart:1:1)');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: ['test_package'], // Include test_package
        inAppExcludes: ['test_package'], // But also exclude test_package
        inAppByDefault: false,
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find any frame from test_package
      final testFrame = frames.firstWhere(
        (frame) => frame['package'] == 'test_package',
        orElse: () => <String, dynamic>{},
      );

      // If we found the frame, test precedence
      if (testFrame.isNotEmpty) {
        expect(testFrame['in_app'], isTrue,
            reason: 'inAppIncludes should take precedence over inAppExcludes');
      } else {
        // Just verify that the configuration was processed without error
        expect(frames, isA<List>());
      }
    });

    test('processes exception types correctly', () {
      final testCases = [
        // Real Exception/Error objects
        {
          'exception': Exception('Exception test'),
          'expectedType': '_Exception'
        },
        {
          'exception': StateError('StateError test'),
          'expectedType': 'StateError'
        },
        {
          'exception': ArgumentError('ArgumentError test'),
          'expectedType': 'ArgumentError'
        },
        {
          'exception': FormatException('FormatException test'),
          'expectedType': 'FormatException'
        },
        // Primitive types
        {'exception': 'Plain string error', 'expectedType': 'String'},
        {'exception': 42, 'expectedType': 'int'},
        {'exception': true, 'expectedType': 'bool'},
        {'exception': 3.14, 'expectedType': 'double'},
        {'exception': [], 'expectedType': 'List<dynamic>'},
        {
          'exception': ['some', 'error'],
          'expectedType': 'List<String>'
        },
        {'exception': {}, 'expectedType': '_Map<dynamic, dynamic>'},
      ];

      for (final testCase in testCases) {
        final exception = testCase['exception']!;
        final expectedType = testCase['expectedType'] as String;

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
          properties: {},
        );

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final exceptionData = exceptionList.first;

        expect(exceptionData['type'], equals(expectedType),
            reason: 'Exception type mismatch for: $exception');

        // Verify the exception value is present and is a string
        expect(exceptionData['value'], isA<String>());
        expect(exceptionData['value'], isNotEmpty);
      }
    });

    test('generates consistent thread IDs', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('#0 test (test.dart:1:1)');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final threadId = exceptionData.first['thread_id'];

      final result2 = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
      );
      final exceptionData2 =
          result2['\$exception_list'] as List<Map<String, dynamic>>;
      final threadId2 = exceptionData2.first['thread_id'];

      expect(threadId, equals(threadId2)); // Should be consistent
    });

    test('generates stack trace when none provided', () {
      final exception = Exception('Test exception'); // will have no stack trace

      final result = DartExceptionProcessor.processException(
        error: exception,
        // No stackTrace provided - should generate one
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final stackTraceData = exceptionData.first['stacktrace'];

      // Should have generated a stack trace
      expect(stackTraceData, isNotNull);
      expect(stackTraceData['frames'], isA<List>());
      expect((stackTraceData['frames'] as List).isNotEmpty, isTrue);

      // Should be marked as synthetic since we generated it
      expect(exceptionData.first['mechanism']['synthetic'], isTrue);
    });

    test('uses error.stackTrace when available', () {
      try {
        throw StateError('Test error');
      } catch (error) {
        final result = DartExceptionProcessor.processException(
          error: error,
          // No stackTrace provided - should generate one from error.stackTrace
        );

        final exceptionData =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final stackTraceData = exceptionData.first['stacktrace'];

        // Should have a stack trace from the Error object
        expect(stackTraceData, isNotNull);
        expect(stackTraceData['frames'], isA<List>());

        // Should not be marked as synthetic since we did not generate a stack trace
        expect(exceptionData.first['mechanism']['synthetic'], isFalse);
      }
    });

    test('removes PostHog frames when stack trace is generated', () {
      final exception = Exception('Test exception');

      // Create a mock stack trace that includes PostHog frames
      final mockStackTrace = StackTrace.fromString('''
#0      DartExceptionProcessor.processException (package:posthog_flutter/src/error_tracking/dart_exception_processor.dart:28:7)
#1      PosthogFlutterIO.captureException (package:posthog_flutter/src/posthog_flutter_io.dart:435:29)
#2      Posthog.captureException (package:posthog_flutter/src/posthog.dart:136:7)
#3      userFunction (package:my_app/main.dart:100:5)
#4      PosthogFlutterIO.setup (package:posthog_flutter/src/posthog.dart:136:7)
#5      main (package:some_lib/lib.dart:50:3)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTraceProvider: () {
          return mockStackTrace;
        },
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames'] as List;

      // Should include frames since we provided the stack trace
      expect(frames[0]['package'], 'my_app');
      expect(frames[0]['filename'], 'main.dart');
      // earlier PH frames should be untouched
      expect(frames[1]['package'], 'posthog_flutter');
      expect(frames[1]['filename'], 'posthog.dart');
      expect(frames[2]['package'], 'some_lib');
      expect(frames[2]['filename'], 'lib.dart');
    });

    test('marks generated stack frames as synthetic', () {
      final exception = Exception('Test exception'); // will have no stack trace

      final result = DartExceptionProcessor.processException(
        error: exception,
        // No stackTrace provided - should generate one
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;

      // Should be marked as synthetic since we generated it
      expect(exceptionData.first['mechanism']['synthetic'], isTrue);
    });

    test('does not mark exceptions as synthetic when stack trace is provided',
        () {
      final realExceptions = [
        Exception('Real exception'),
        StateError('Real error'),
        ArgumentError('Real argument error'),
      ];

      for (final exception in realExceptions) {
        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            result['\$exception_list'] as List<Map<String, dynamic>>;

        expect(exceptionData.first['mechanism']['synthetic'], isFalse);
      }
    });

    test('allows user properties to override system properties', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('#0 test (test.dart:1:1)');

      // Properties that override system properties
      final overrideProperties = {
        '\$exception_level': 'warning', // Override default 'error'
        'custom_property': 'custom_value', // Additional custom property
      };

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: overrideProperties,
      );

      // Verify that user properties take precedence
      expect(result['\$exception_level'], equals('warning'));
      expect(result['custom_property'], equals('custom_value'));
    });

    test('inserts asynchronous gap frames between traces', () async {
      final exception = Exception('Async test exception');

      // Create an async stack trace by throwing from an async function
      StackTrace? asyncStackTrace;
      try {
        await _asyncFunction1();
      } catch (e, stackTrace) {
        asyncStackTrace = stackTrace;
      }

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: asyncStackTrace,
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Look for asynchronous gap frames
      final gapFrames = frames
          .where((frame) => frame['abs_path'] == '<asynchronous suspension>')
          .toList();

      // Should have at least one gap frame in an async stack trace
      expect(gapFrames, isNotEmpty,
          reason: 'Async stack traces should contain gap frames');

      // Verify gap frame structure
      final gapFrame = gapFrames.first;
      expect(gapFrame['platform'], equals('dart'));
      expect(gapFrame['in_app'], isFalse);
      expect(gapFrame['abs_path'], equals('<asynchronous suspension>'));
    });

    test('processes PostHogException with different mechanism types', () {
      final testCases = [
        {'mechanism': 'FlutterError', 'handled': false},
        {'mechanism': 'PlatformDispatcher', 'handled': false},
        {'mechanism': 'UncaughtExceptionHandler', 'handled': true},
        {'mechanism': 'custom_mechanism', 'handled': true},
      ];

      for (final testCase in testCases) {
        final originalError = StateError('Test error');
        final postHogException = PostHogException(
          source: originalError,
          mechanism: testCase['mechanism'] as String,
          handled: testCase['handled'] as bool,
        );

        final result = DartExceptionProcessor.processException(
          error: postHogException,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        expect(
            exceptionData['mechanism']['type'], equals(testCase['mechanism']));
        expect(
            exceptionData['mechanism']['handled'], equals(testCase['handled']));
        expect(exceptionData['type'], equals('StateError'));
      }
    });

    test(
        'uses original error for stack trace processing when wrapped in PostHogException',
        () {
      // Create an Error (not Exception) so it has a built-in stackTrace
      late Error originalError;

      try {
        throw StateError('Original error with stack trace');
      } catch (error) {
        originalError = error as Error;
      }

      // Wrap in PostHogException
      final postHogException = PostHogException(
        source: originalError,
        mechanism: 'test_mechanism',
        handled: true,
      );

      // Process without providing external stack trace - should use original error's stackTrace
      final result = DartExceptionProcessor.processException(
        error: postHogException,
        // No stackTrace provided - should extract from original error
      );

      final exceptionData =
          (result['\$exception_list'] as List).first as Map<String, dynamic>;

      // Verify it used the original error for processing
      expect(exceptionData['type'], equals('StateError'));
      expect(exceptionData['value'],
          equals('Bad state: Original error with stack trace'));
      expect(exceptionData['mechanism']['type'], equals('test_mechanism'));
      expect(exceptionData['mechanism']['handled'], equals(true));

      // Should have stacktrace frames from the original error
      expect(exceptionData['stacktrace'], isNotNull);
      expect(exceptionData['stacktrace']['frames'], isA<List>());
      expect(
          (exceptionData['stacktrace']['frames'] as List).isNotEmpty, isTrue);
    });

    group('non-symbolic stack traces (--split-debug-info)', () {
      // Simulates an Android ARM64 obfuscated stack trace
      const androidArm64Trace = '''
Warning: This VM has been configured to produce stack traces that violate the Dart standard.
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 29278, tid: 29340, name 1.ui
build_id: 'f84eca6467890839d0b53ac1f77e147b'
isolate_dso_base: 6fe9d64000, vm_dso_base: 6fe9d64000
isolate_instructions: 6fe9d74000, vm_instructions: 6fe9d66000
    #00 abs 0000006fe9f4e87b virt 00000000001ea87b _kDartIsolateSnapshotInstructions+0x1da87b
    #01 abs 0000006fe9f5152f virt 00000000001ed52f _kDartIsolateSnapshotInstructions+0x1dd52f
    #02 abs 0000006fea080493 virt 00000000003bc493 _kDartIsolateSnapshotInstructions+0x30c493
''';

      // Android ARM32 format
      const androidArm32Trace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 28496, tid: 28600, name 1.ui
build_id: 'abcdef0123456789abcdef0123456789'
isolate_dso_base: c0ec6000, vm_dso_base: c0ec6000
isolate_instructions: c11ea6c0, vm_instructions: c11e6000
    #00 abs c11ebb0b virt 00325b0b _kDartIsolateSnapshotInstructions+0x144b
    #01 abs c11eb777 virt 00325777 _kDartIsolateSnapshotInstructions+0x10b7
''';

      // Trace without build_id (older SDK or iOS Mach-O assembly)
      const traceWithoutBuildId = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 14175, tid: 6099480576, name io.flutter.1.ui
os: ios arch: arm64 comp: no sim: no
isolate_dso_base: 111f84000, vm_dso_base: 111f84000
isolate_instructions: 111f914c0, vm_instructions: 111f8b9c0
    #00 abs 00000001128bfb9f _kDartIsolateSnapshotInstructions+0x92e6df
    #01 abs 00000001128bf800 _kDartIsolateSnapshotInstructions+0x92e340
''';

      test('detects non-symbolic stack trace and parses frames', () {
        final exception = Exception('Obfuscated crash');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final exceptionData =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final stackTraceData =
            exceptionData.first['stacktrace'] as Map<String, dynamic>;
        final frames =
            stackTraceData['frames'] as List<Map<String, dynamic>>;

        expect(frames, hasLength(3));
        expect(stackTraceData['type'], equals('raw'));
      });

      test('extracts instruction_addr from each frame', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        expect(frames[0]['instruction_addr'], equals('0x0000006fe9f4e87b'));
        expect(frames[1]['instruction_addr'], equals('0x0000006fe9f5152f'));
        expect(frames[2]['instruction_addr'], equals('0x0000006fea080493'));
      });

      test('extracts build_id and image_addr from header', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        for (final frame in frames) {
          expect(frame['build_id'],
              equals('f84eca6467890839d0b53ac1f77e147b'));
          expect(frame['image_addr'], equals('0x6fe9d64000'));
        }
      });

      test('sets platform to dart and in_app to true', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        for (final frame in frames) {
          expect(frame['platform'], equals('dart'));
          expect(frame['in_app'], isTrue);
        }
      });

      test('uses instruction_addr as abs_path', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        expect(frames[0]['abs_path'], equals('0x0000006fe9f4e87b'));
        expect(frames[0]['abs_path'], equals(frames[0]['instruction_addr']));
      });

      test('handles 32-bit addresses (ARM32)', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm32Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        expect(frames, hasLength(2));
        expect(frames[0]['instruction_addr'], equals('0xc11ebb0b'));
        expect(frames[1]['instruction_addr'], equals('0xc11eb777'));
        expect(frames[0]['image_addr'], equals('0xc0ec6000'));
        expect(
            frames[0]['build_id'], equals('abcdef0123456789abcdef0123456789'));
      });

      test('handles missing build_id gracefully', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(traceWithoutBuildId);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        expect(frames, hasLength(2));
        expect(frames[0]['instruction_addr'], equals('0x00000001128bfb9f'));
        expect(frames[0].containsKey('build_id'), isFalse);
        expect(frames[0]['image_addr'], equals('0x111f84000'));
      });

      test('preserves exception metadata with non-symbolic traces', () {
        final originalError = StateError('crash in obfuscated build');
        final wrappedError = PostHogException(
          source: originalError,
          mechanism: 'FlutterError',
          handled: false,
        );
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: wrappedError,
          stackTrace: stackTrace,
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        expect(exceptionData['type'], equals('StateError'));
        expect(exceptionData['value'],
            equals('Bad state: crash in obfuscated build'));
        expect(exceptionData['mechanism']['type'], equals('FlutterError'));
        expect(exceptionData['mechanism']['handled'], isFalse);
        expect(exceptionData['mechanism']['synthetic'], isFalse);
      });

      test('does not have lineno, colno, function, filename, or package', () {
        final exception = Exception('test');
        final stackTrace = StackTrace.fromString(androidArm64Trace);

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        for (final frame in frames) {
          expect(frame.containsKey('lineno'), isFalse);
          expect(frame.containsKey('colno'), isFalse);
          expect(frame.containsKey('function'), isFalse);
          expect(frame.containsKey('filename'), isFalse);
          expect(frame.containsKey('package'), isFalse);
        }
      });

      test('normal symbolic traces still use Chain.forTrace() path', () {
        final exception = Exception('Normal exception');
        final stackTrace = StackTrace.fromString('''
#0      main (package:my_app/main.dart:25:7)
#1      helper (package:third_party/helper.dart:10:5)
''');

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: stackTrace,
        );

        final frames = _extractFrames(result);

        // Should have symbolic info (package, filename, lineno)
        expect(frames[0]['package'], equals('my_app'));
        expect(frames[0]['filename'], equals('main.dart'));
        expect(frames[0]['lineno'], equals(25));
        // Should NOT have non-symbolic fields
        expect(frames[0].containsKey('instruction_addr'), isFalse);
        expect(frames[0].containsKey('build_id'), isFalse);
        expect(frames[0].containsKey('image_addr'), isFalse);
      });
    });

    test('processes original error type correctly when wrapped', () {
      final testErrorTypes = [
        Exception('Test exception'),
        StateError('State error'),
        ArgumentError('Argument error'),
        FormatException('Format error'),
        RangeError('Range error'),
      ];

      for (final originalError in testErrorTypes) {
        final postHogException = PostHogException(
          source: originalError,
          mechanism: 'test_mechanism',
        );

        final result = DartExceptionProcessor.processException(
          error: postHogException,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        // Should extract type from original error, not PostHogException
        final expectedType = originalError.runtimeType.toString();
        expect(exceptionData['type'], equals(expectedType));

        // Should use original error's toString for message
        expect(exceptionData['value'], equals(originalError.toString()));

        // But mechanism should come from wrapper
        expect(exceptionData['mechanism']['type'], equals('test_mechanism'));
      }
    });
  });
}

/// Extracts frames from a processException result
List<Map<String, dynamic>> _extractFrames(Map<String, dynamic> result) {
  final exceptionData =
      result['\$exception_list'] as List<Map<String, dynamic>>;
  return exceptionData.first['stacktrace']['frames']
      as List<Map<String, dynamic>>;
}

// Helper functions to generate async stack traces for testing
Future<void> _asyncFunction1() async {
  await _asyncFunction2();
}

Future<void> _asyncFunction2() async {
  await Future.delayed(Duration.zero); // Force async boundary
  throw StateError('Async error for testing');
}
