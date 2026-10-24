import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:business_bank/core/api.dart';

void main() {
  test('Concurrent expired requests share refresh and save rotated tokens',
      () async {
    var refreshes = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('auth/login/')) {
        return http.Response(
            jsonEncode({'access': 'old', 'refresh': 'r1'}), 200);
      }
      if (request.url.path.endsWith('auth/refresh/')) {
        refreshes++;
        expect(jsonDecode(request.body)['refresh'], 'r1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(
            jsonEncode({'access': 'new', 'refresh': 'r2'}), 200);
      }
      return request.headers['Authorization'] == 'Bearer new'
          ? http.Response('{}', 200)
          : http.Response('{}', 401);
    });
    final api = BankApi(client: client);
    await api.login('a@b.kz', 'password');
    await Future.wait(
        [api.request('GET', 'companies/'), api.request('GET', 'auth/me/')]);
    expect(refreshes, 1);
    api.close();
  });
  test('Mutation key and exact body survive 401 token renewal', () async {
    final requests = <http.Request>[];
    final api = BankApi(client: MockClient((request) async {
      if (request.url.path.endsWith('auth/login/')) {
        return http.Response('{"access":"a","refresh":"r"}', 200);
      }
      if (request.url.path.endsWith('auth/refresh/')) {
        return http.Response('{"access":"b","refresh":"s"}', 200);
      }
      requests.add(request);
      return http.Response('{}', requests.length == 1 ? 401 : 200);
    }));
    await api.login('a@b.kz', 'password');
    await api.request('POST', 'payments/one/approve/',
        body: {}, key: 'same-key');
    expect(requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {'same-key'});
    expect(requests[0].body, requests[1].body);
    api.close();
  });
  test('A 500 on a mutation is uncertain, not silently retried', () async {
    var calls = 0;
    final api = BankApi(client: MockClient((_) async {
      calls++;
      return http.Response('{}', 500);
    }));
    await expectLater(
        api.request('POST', 'payments/', body: {}, key: 'key'),
        throwsA(
            isA<ApiFailure>().having((e) => e.uncertain, 'uncertain', true)));
    expect(calls, 1);
    api.close();
  });
}
