import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:business_bank/core/api.dart';
import 'package:business_bank/core/models.dart';

class RealNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context);
}
void main() {
  test('Live Django payment lifecycle and exact idempotent approval', () async {
    await HttpOverrides.runZoned(() async {
      final api = BankApi(); addTearDown(api.close);
      const password = String.fromEnvironment('LIVE_PASSWORD');
      await api.login('accountant@demo.example', password);
      final companies = await api.all('companies/');
      final company = companies.firstWhere((c) => c['name'] == 'ИП Куат Демо');
      final accounts = await api.all('companies/${company['id']}/accounts/');
      final source = accounts.firstWhere((a) => a['number'] == 'DEMO-KUAT-001');
      final recipient = await api.request('POST', 'recipients/resolve/', body: {'number': 'DEMO-VECTOR-001'}) as Json;
      final payment = await api.request('POST', 'companies/${company['id']}/payments/', key: const Uuid().v4(), body: {
        'source': source['id'], 'destination': recipient['id'], 'amount': '125.25', 'purpose': 'Flutter API integration',
      }) as Json;
      final id = payment['id'];
      await api.request('POST', 'payments/$id/submit/', body: {}, key: const Uuid().v4());
      await expectLater(api.request('POST', 'payments/$id/approve/', body: {}, key: const Uuid().v4()),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)));
      await api.logout(); await api.login('owner@demo.example', password);
      final approvalKey = const Uuid().v4();
      final approved = await api.request('POST', 'payments/$id/approve/', body: {}, key: approvalKey) as Json;
      expect(approved['status'], 'EXECUTED');
      final repeat = await api.request('POST', 'payments/$id/approve/', body: {}, key: approvalKey) as Json;
      expect(repeat, approved);
      final after = await api.all('companies/${company['id']}/accounts/');
      expect(Money.cents(after.firstWhere((a) => a['id'] == source['id'])['cached_balance'] as String),
          Money.cents(source['cached_balance'] as String) - Money.cents('125.25'));
      final entries = await api.all('accounts/${source['id']}/transactions/');
      expect(entries.where((e) => e['purpose'] == 'Flutter API integration' && e['side'] == 'DEBIT').length, 1);
      final export = await api.request('POST', 'accounts/${source['id']}/statement-exports/', body: {
        'date_from': '2020-01-01', 'date_to': '2020-01-31', 'format': 'csv',
      }) as Json;
      final history = await api.all('accounts/${source['id']}/statement-exports/');
      expect(history.any((e) => e['id'] == export['id']), true);
      await api.logout();
    }, createHttpClient: RealNetwork().createHttpClient);
  }, skip: !const bool.fromEnvironment('LIVE_API'));
}
