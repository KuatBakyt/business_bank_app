import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:business_bank/core/api.dart';
import 'package:business_bank/core/models.dart';
import 'package:business_bank/core/store.dart';

void main() {
  test('An uncertain payment blocks new mutations and retry keeps its key',
      () async {
    final keys = <String?>[];
    final bodies = <String>[];
    final api = BankApi(client: MockClient((r) async {
      if (r.method == 'POST') {
        keys.add(r.headers['Idempotency-Key']);
        bodies.add(r.body);
        return http.Response(keys.length == 1 ? '{}' : '{"id":"payment"}',
            keys.length == 1 ? 500 : 201);
      }
      return http.Response('{"results":[],"next":null}', 200);
    }));
    final s = BankStore(api)
      ..user = {'id': 'user'}
      ..company = Company.fromJson(
          {'id': 'company', 'name': 'Company', 'owner': 'user'})
      ..role = 'OWNER';
    await expectLater(
        s.command('companies/company/payments/', {'amount': '10.00'}),
        throwsA(isA<ApiFailure>()));
    expect(s.pending, isNotNull);
    expect(s.canWrite, false);
    await expectLater(
        s.command('companies/company/payments/', {'amount': '20.00'}),
        throwsA(isA<ApiFailure>()));
    await s.retryPending();
    expect(keys.length, 2);
    expect(keys[0], keys[1]);
    expect(bodies[0], bodies[1]);
    expect(jsonDecode(bodies[1])['amount'], '10.00');
    expect(s.pending, isNull);
    s.dispose();
  });
}
