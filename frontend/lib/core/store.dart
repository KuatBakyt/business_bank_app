import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'models.dart';
import 'platform.dart' as platform;

class PendingCommand {
  final String path, method, key, companyId, label;
  final Json body;
  PendingCommand({required this.path, required this.method, required this.key,
      required this.companyId, required this.body, required this.label});
  Json toJson() => {'path': path, 'method': method, 'key': key, 'companyId': companyId, 'body': body, 'label': label};
  factory PendingCommand.fromJson(Json j) => PendingCommand(path: j['path'] as String,
      method: j['method'] as String, key: j['key'] as String, companyId: j['companyId'] as String,
      body: j['body'] as Json, label: j['label'] as String);
}

class BankStore extends ChangeNotifier {
  final BankApi api;
  BankStore(this.api) { api.onExpired = _expire; }
  Json? user;
  List<Company> companies = [];
  Company? company;
  List<BankAccount> accounts = [];
  List<Payment> payments = [];
  List<Json> members = [];
  String? role;
  String? error;
  bool busy = false, loading = false, mutating = false;
  PendingCommand? pending;
  int _epoch = 0, _authEpoch = 0;
  bool _disposed = false;
  bool get owner => role == 'OWNER';
  bool get writer => owner || role == 'ACCOUNTANT';
  bool get canWrite => writer && pending == null && !mutating;
  String get userId => user?['id'] as String? ?? '';
  BigInt get total => accounts.fold(BigInt.zero, (a, b) => a + Money.cents(b.balance));

  void _notify() { if (!_disposed) notifyListeners(); }
  void _expire() {
    _epoch++; _authEpoch++; user = null; companies = []; company = null; accounts = []; payments = []; members = [];
    role = null; busy = false; loading = false; mutating = false; pending = null;
    error = 'Сессия завершена. Войдите снова.'; _notify();
  }

  Future<void> authenticate(String email, String password, {bool register = false, String name = ''}) async {
    final epoch = ++_authEpoch;
    busy = true; error = null; _notify();
    try {
      if (register) await api.request('POST', 'auth/register/', authenticated: false,
          body: {'email': email.trim(), 'password': password, 'first_name': name.trim()});
      await api.login(email, password);
      final me = await api.request('GET', 'auth/me/') as Json;
      final list = (await api.all('companies/')).map(Company.fromJson).toList();
      if (epoch != _authEpoch) return;
      user = me; companies = list;
      final saved = platform.readPending(userId);
      if (saved != null) {
        try { pending = PendingCommand.fromJson(jsonDecode(saved) as Json); } catch (_) { platform.savePending(userId, null); }
      }
      if (companies.isNotEmpty) {
        company = companies.firstWhere((c) => c.id == pending?.companyId, orElse: () => companies.first);
        await refresh();
      }
    } catch (e) { if (epoch == _authEpoch) error = '$e'; }
    finally { if (epoch == _authEpoch) { busy = false; _notify(); } }
  }

  Future<void> select(Company selected) async {
    _epoch++; company = selected; accounts = []; payments = []; members = []; role = null;
    await refresh();
  }

  Future<void> refresh() async {
    final selected = company;
    if (selected == null || user == null) return;
    final epoch = ++_epoch;
    loading = true; error = null; _notify();
    try {
      final results = await Future.wait([
        api.all('companies/${selected.id}/accounts/'), api.all('companies/${selected.id}/payments/'),
        api.all('companies/${selected.id}/members/'),
      ]);
      if (epoch != _epoch) return;
      accounts = results[0].map(BankAccount.fromJson).toList();
      payments = results[1].map(Payment.fromJson).toList();
      members = results[2];
      role = members.where((m) => m['user'] == userId && m['is_active'] == true).firstOrNull?['role'] as String?;
    } catch (e) { if (epoch == _epoch) error = '$e'; }
    finally { if (epoch == _epoch) { loading = false; _notify(); } }
  }

  Future<void> logout() async {
    if (pending != null) throw const ApiFailure('Сначала проверьте результат ожидающего запроса');
    busy = true; _notify();
    try { await api.logout(); } finally { _expire(); error = null; _notify(); }
  }

  Future<void> createCompany(String name) async {
    await api.request('POST', 'companies/', body: {'name': name.trim()});
    companies = (await api.all('companies/')).map(Company.fromJson).toList();
    await select(companies.last);
  }

  Future<Json> command(String path, Json body, {String method = 'POST', String label = 'Платёж'}) async {
    if (pending != null) throw const ApiFailure('Сначала проверьте предыдущий запрос');
    if (mutating) throw const ApiFailure('Запрос уже выполняется');
    pending = PendingCommand(path: path, method: method, key: const Uuid().v4(),
        companyId: company!.id, body: Map<String, dynamic>.from(body), label: label);
    platform.savePending(userId, jsonEncode(pending!.toJson()));
    return retryPending();
  }

  Future<Json> retryPending() async {
    final current = pending;
    if (current == null || mutating) throw const ApiFailure('Нет доступного запроса');
    mutating = true; _notify();
    final identity = userId;
    try {
      final result = await api.request(current.method, current.path, body: current.body, key: current.key) as Json;
      if (userId != identity) throw const ApiFailure('Войдите снова для проверки результата');
      pending = null; platform.savePending(identity, null);
      await refresh();
      return result;
    } on ApiFailure catch (e) {
      if (!e.uncertain && e.status != 401) {
        pending = null; platform.savePending(identity, null);
      }
      rethrow;
    } finally { mutating = false; _notify(); }
  }

  BankAccount? account(String id) => accounts.where((a) => a.id == id).firstOrNull;
  String memberName(String id) => members.where((m) => m['user'] == id).firstOrNull?['email'] as String? ?? id;

  @override
  void dispose() { _disposed = true; api.onExpired = null; api.close(); super.dispose(); }
}
