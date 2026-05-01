import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimereport/features/feed/data/repositories/report_repository.dart';
import 'package:crimereport/features/submit/data/services/upload_service.dart';
import 'package:crimereport/features/submit/providers/upload_provider.dart';
import 'package:crimereport/shared/data/api/api_client.dart';

/// Fake [UploadService] whose `pollMediaStatus` returns a programmable
/// stream. Other methods throw — they are not exercised by these tests.
class _FakeUploadService implements UploadService {
  _FakeUploadService(this._poll);

  final Stream<MediaPollResult> Function(String reportId) _poll;

  @override
  Stream<MediaPollResult> pollMediaStatus(String reportId) => _poll(reportId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class _FakeReportRepository implements ReportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

UploadNotifier _makeNotifier(
  Stream<MediaPollResult> Function(String reportId) poll,
) {
  return UploadNotifier(_FakeUploadService(poll), _FakeReportRepository());
}

void main() {
  group('UploadPhase.statusText', () {
    test('processing surfaces "Processing media…"', () {
      expect(UploadPhase.processing.statusText, 'Processing media…');
    });
  });

  group('UploadNotifier.messageForFailureReason', () {
    test('maps known failure reasons to user-facing copy', () {
      expect(
        UploadNotifier.messageForFailureReason('flagged_content'),
        contains('flagged'),
      );
      expect(
        UploadNotifier.messageForFailureReason('unsupported_format'),
        contains('not supported'),
      );
      expect(
        UploadNotifier.messageForFailureReason('processing_error'),
        contains('trouble'),
      );
    });

    test('falls back to a generic message for unknown reasons', () {
      expect(
        UploadNotifier.messageForFailureReason(null),
        "Your media couldn't be processed. Please try again.",
      );
      expect(
        UploadNotifier.messageForFailureReason('something_new'),
        "Your media couldn't be processed. Please try again.",
      );
    });
  });

  group('MediaPollResult', () {
    test('parses optional failure_reason', () {
      final r = MediaPollResult.fromJson({
        'status': 'failed',
        'media_url': null,
        'failure_reason': 'flagged_content',
      });
      expect(r.status, 'failed');
      expect(r.failureReason, 'flagged_content');
      expect(r.isTerminal, isTrue);
    });

    test('failure_reason is null when omitted', () {
      final r = MediaPollResult.fromJson({'status': 'processing'});
      expect(r.failureReason, isNull);
      expect(r.isTerminal, isFalse);
    });
  });

  group('UploadNotifier.waitForProcessing', () {
    Stream<MediaPollResult> tickingStream(List<MediaPollResult> events) async* {
      for (final e in events) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        yield e;
      }
    }

    test('transitions to done when poll yields active', () async {
      final notifier = _makeNotifier(
        (_) => tickingStream([
          const MediaPollResult(status: 'processing'),
          const MediaPollResult(status: 'active', mediaUrl: 'cdn://m.jpg'),
        ]),
      );
      addTearDown(notifier.dispose);

      final phases = <UploadPhase>[];
      notifier.addListener(
        (s) => phases.add(s.phase),
        fireImmediately: false,
      );

      await notifier.waitForProcessing('r-1');

      expect(phases, contains(UploadPhase.processing));
      expect(phases.last, UploadPhase.done);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.infoMessage, isNull);
    });

    test('transitions to error with reason-specific copy when poll yields '
        'failed', () async {
      final notifier = _makeNotifier(
        (_) => tickingStream([
          const MediaPollResult(
            status: 'failed',
            failureReason: 'flagged_content',
          ),
        ]),
      );
      addTearDown(notifier.dispose);

      await notifier.waitForProcessing('r-2');

      expect(notifier.state.phase, UploadPhase.error);
      expect(notifier.state.errorMessage, contains('flagged'));
    });

    test('falls back to generic error copy when failure_reason is missing',
        () async {
      final notifier = _makeNotifier(
        (_) => tickingStream([const MediaPollResult(status: 'failed')]),
      );
      addTearDown(notifier.dispose);

      await notifier.waitForProcessing('r-3');

      expect(notifier.state.phase, UploadPhase.error);
      expect(
        notifier.state.errorMessage,
        "Your media couldn't be processed. Please try again.",
      );
    });

    test('polling timeout transitions to done with a still-processing notice',
        () {
      fakeAsync((async) {
        // Stream that emits a non-terminal status periodically forever.
        Stream<MediaPollResult> nonTerminal(String _) async* {
          while (true) {
            await Future<void>.delayed(const Duration(seconds: 3));
            yield const MediaPollResult(status: 'processing');
          }
        }

        final notifier = _makeNotifier(nonTerminal);
        addTearDown(notifier.dispose);

        notifier.waitForProcessing('r-4');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(notifier.state.phase, UploadPhase.processing);

        async.elapse(
          UploadNotifier.processingTimeout + const Duration(seconds: 1),
        );

        expect(notifier.state.phase, UploadPhase.done);
        expect(notifier.state.infoMessage, contains('still processing'));
        expect(notifier.state.errorMessage, isNull);
      });
    });

    test('falls back to still-processing notice when stream errors out',
        () async {
      Stream<MediaPollResult> erroring(String _) async* {
        yield const MediaPollResult(status: 'processing');
        throw Exception('network blip');
      }

      final notifier = _makeNotifier(erroring);
      addTearDown(notifier.dispose);

      await notifier.waitForProcessing('r-5');

      expect(notifier.state.phase, UploadPhase.done);
      expect(notifier.state.infoMessage, contains('still processing'));
    });

    test('cancel() during polling resets state', () async {
      final controller = StreamController<MediaPollResult>();
      addTearDown(controller.close);

      final notifier = _makeNotifier((_) => controller.stream);
      addTearDown(notifier.dispose);

      final future = notifier.waitForProcessing('r-6');
      // Allow the listener subscription to attach and the state to flip
      // to `processing`.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(notifier.state.phase, UploadPhase.processing);

      notifier.cancel();
      await future;

      expect(notifier.state.phase, UploadPhase.idle);
      expect(notifier.state.errorMessage, isNull);
    });
  });

  // Sanity-check that an UploadService backed by an ApiClient still resolves
  // — guards against accidental constructor-signature changes that would
  // break the production `uploadServiceProvider`.
  test('UploadService can be constructed with an ApiClient', () {
    final svc = UploadService(ApiClient(baseUrl: 'http://localhost'));
    addTearDown(svc.dispose);
    expect(svc, isNotNull);
  });
}
