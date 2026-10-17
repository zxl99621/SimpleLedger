import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:beecount/ai/simple/ai_engine.dart';
import 'package:beecount/ai/simple/cloud_ai_engine.dart';

void main() {
  test('取消后立即停止读取 SSE，并抛出 AiCancelled', () async {
    final controller = StreamController<List<int>>();
    final client = _FakeClient(controller.stream);
    final engine = CloudAiEngine(
      baseUrl: 'https://example.com/v1',
      apiKey: 'test-key',
      model: 'test-model',
      clientFactory: () => client,
    );

    final received = <String>[];
    final errors = <Object>[];
    final done = Completer<void>();
    final subscription = engine
        .streamChat(const [AiMessage(role: 'user', content: 'hi')])
        .listen(
          received.add,
          onError: (Object error, StackTrace stackTrace) {
            errors.add(error);
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );

    controller.add(utf8.encode(
        'data: {"choices":[{"delta":{"content":"a"}}]}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    engine.cancel();
    controller.add(utf8.encode(
        'data: {"choices":[{"delta":{"content":"b"}}]}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await controller.close();

    await done.future.timeout(const Duration(seconds: 2));
    expect(errors, hasLength(1));
    expect(errors.single, isA<AiCancelled>());
    expect(received, ['a']);
    await subscription.cancel();
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.stream);

  final Stream<List<int>> stream;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    closed = true;
  }
}
