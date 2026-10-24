import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiFailure implements Exception {
  final String message, code;
  final int? status;
  final bool uncertain;
  const ApiFailure(this.message,
      {this.code = '', this.status, this.uncertain = false});
  @override
  String toString() => message;
}

class BankApi {
  final http.Client client;
  final Uri base;
  String? _access, _refresh;
  int _generation = 0;
  Future<void>? _refreshing;
  VoidCallback? onExpired;
  bool _closed = false;
  BankApi({http.Client? client, String? baseUrl})
      : client = client ?? http.Client(),
        base = Uri.parse(baseUrl ??
            const String.fromEnvironment('API_URL',
                defaultValue: 'http://localhost:8000/api/v1/')) {
    if (!base.hasScheme ||
        !['http', 'https'].contains(base.scheme) ||
        !base.path.endsWith('/')) {
      throw ArgumentError(
          'API_URL должен быть HTTP(S) адресом с /api/v1/ в конце');
    }
  }

  void clear() {
    _generation++;
    _access = null;
    _refresh = null;
  }

  void close() {
    _closed = true;
    clear();
    client.close();
  }

  Future<void> login(String email, String password) async {
    clear();
    final generation = _generation;
    final data = await request('POST', 'auth/login/',
        body: {'email': email.trim(), 'password': password},
        authenticated: false) as Json;
    if (generation != _generation || _closed)
      throw const ApiFailure('Сессия изменена');
    _access = data['access'] as String;
    _refresh = data['refresh'] as String;
  }

  Future<void> logout() async {
    final refresh = _refresh;
    try {
      if (refresh != null)
        await request('POST', 'auth/logout/', body: {'refresh': refresh});
    } finally {
      clear();
    }
  }

  Future<void> _renew(int generation) async {
    final token = _refresh;
    if (token == null) throw const ApiFailure('Войдите снова', status: 401);
    final response = await client
        .post(base.resolve('auth/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': token}))
        .timeout(const Duration(seconds: 25));
    if (_closed || generation != _generation)
      throw const ApiFailure('Сессия изменена');
    if (response.statusCode != 200) {
      clear();
      onExpired?.call();
      throw const ApiFailure('Сессия завершена. Войдите снова.', status: 401);
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
    _access = data['access'] as String;
    _refresh = data['refresh'] as String;
  }

  Future<dynamic> request(String method, String path,
      {Json? body,
      Json? query,
      String? key,
      bool authenticated = true,
      bool binary = false}) async {
    final generation = _generation;
    final originalToken = _access;
    Future<http.Response> send() async {
      final uri = base
          .resolve(path)
          .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));
      if (uri.origin != base.origin || !uri.path.startsWith(base.path))
        throw ArgumentError('Invalid API path');
      final req = http.Request(method, uri);
      req.headers['Accept'] =
          binary ? 'application/octet-stream' : 'application/json';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      if (authenticated && _access != null)
        req.headers['Authorization'] = 'Bearer $_access';
      if (key != null) req.headers['Idempotency-Key'] = key;
      return client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    }

    try {
      var response = await send();
      if (authenticated && generation != _generation)
        throw const ApiFailure('Сессия изменена');
      if (response.statusCode == 401 && authenticated) {
        if (originalToken == _access) {
          final existing = _refreshing;
          if (existing != null) {
            await existing;
          } else {
            final renewal = _renew(generation);
            _refreshing = renewal;
            try {
              await renewal;
            } finally {
              if (identical(_refreshing, renewal)) _refreshing = null;
            }
          }
        }
        if (generation != _generation)
          throw const ApiFailure('Войдите снова', status: 401);
        response = await send();
      }
      if (generation != _generation || _closed)
        throw const ApiFailure('Сессия изменена');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (binary) return Uint8List.fromList(response.bodyBytes);
        return response.bodyBytes.isEmpty
            ? null
            : jsonDecode(utf8.decode(response.bodyBytes));
      }
      Json data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
      } catch (_) {
        data = {};
      }
      final fields = data['fields'];
      var message = data['message'] as String? ??
          'Запрос не выполнен (${response.statusCode})';
      if (fields is Map && fields.isNotEmpty) {
        message = fields.entries
            .map((e) =>
                '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
            .join('\n');
      }
      throw ApiFailure(message,
          code: data['code'] as String? ?? '',
          status: response.statusCode,
          uncertain: method != 'GET' && response.statusCode >= 500);
    } on TimeoutException {
      throw ApiFailure('Сервер не ответил вовремя. Проверьте соединение.',
          uncertain: method != 'GET');
    } on http.ClientException {
      throw ApiFailure('Нет соединения с API. Проверьте адрес сервера и CORS.',
          uncertain: method != 'GET');
    }
  }

  Future<List<Json>> all(String path, {Json? query}) async {
    final result = <Json>[];
    var page = 1;
    while (true) {
      final data = await request('GET', path,
          query: {...?query, 'page': page, 'page_size': 100}) as Json;
      result.addAll((data['results'] as List).cast<Json>());
      if (data['next'] == null) return result;
      page++;
    }
  }
}
