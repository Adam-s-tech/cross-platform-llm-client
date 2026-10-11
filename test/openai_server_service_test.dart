import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privatelm/services/openai_server_service_io.dart';

void main() {
  late OpenAiServerService server;
  late HttpClient client;
  const port = 18765;

  setUp(() {
    server = OpenAiServerService();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<HttpClientResponse> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:$port$path'));
    req.persistentConnection = false;
    headers.forEach(req.headers.set);
    if (body != null) req.write(body);
    final res = await req.close();
    await res.drain<void>();
    return res;
  }

  test('binds to loopback only by default', () async {
    await server.start(port: port);
    expect(server.localUrl, 'http://127.0.0.1:$port');
  });

  test('network mode refuses to start without an API key', () async {
    expect(
      () => server.start(port: port, allowNetwork: true),
      throwsArgumentError,
    );
    expect(server.isRunning, isFalse);
  });

  test('enforces the API key and applies key changes live', () async {
    await server.start(port: port, apiKey: 'first');

    expect((await send('GET', '/v1/models')).statusCode, 401);
    expect(
      (await send('GET', '/health')).statusCode,
      200,
      reason: 'health check stays public',
    );

    server.updateApiKey('second');
    expect(
      (await send('GET', '/v1/server/capabilities',
              headers: {'Authorization': 'Bearer first'}))
          .statusCode,
      401,
    );
  });

  test('rejects POST bodies that are not JSON', () async {
    await server.start(port: port);
    final res = await send('POST', '/v1/chat/completions',
        headers: {'Content-Type': 'text/plain'},
        body: jsonEncode({'messages': []}));
    expect(res.statusCode, HttpStatus.unsupportedMediaType);
  });

  test('only sends CORS headers when a key is required', () async {
    await server.start(port: port);
    var res = await send('GET', '/health');
    expect(res.headers.value('access-control-allow-origin'), isNull);
    await server.stop();

    await server.start(port: port, apiKey: 'k');
    res = await send('GET', '/health');
    expect(res.headers.value('access-control-allow-origin'), '*');
  });
}
