import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:business_bank/main.dart';
import 'package:business_bank/core/api.dart';
import 'package:business_bank/core/store.dart';
import 'package:business_bank/core/models.dart';

BankStore fixture({String role = 'OWNER'}) {
  final s = BankStore(BankApi(
      client: MockClient(
          (_) async => http.Response('{"results":[],"next":null}', 200))));
  s.user = {'id': 'user', 'email': 'owner@demo.example', 'first_name': 'Бакыт'};
  s.company = Company.fromJson(
      {'id': 'company', 'name': 'ИП Куат Демо', 'owner': 'user'});
  s.companies = [s.company!];
  s.role = role;
  s.members = [
    {
      'id': 'member',
      'user': 'user',
      'email': 'owner@demo.example',
      'role': role,
      'is_active': true
    }
  ];
  s.accounts = [
    BankAccount.fromJson({
      'id': 'a',
      'number': 'DEMO-KUAT-001',
      'name': 'Основной счёт',
      'cached_balance': '1850000.00',
      'status': 'ACTIVE'
    }),
    BankAccount.fromJson({
      'id': 'b',
      'number': 'DEMO-KUAT-002',
      'name': 'Резервный счёт',
      'cached_balance': '600000.00',
      'status': 'ACTIVE'
    })
  ];
  s.payments = [
    for (var i = 0; i < 4; i++)
      Payment.fromJson({
        'id': 'p$i',
        'source': 'a',
        'destination': 'dest',
        'amount': ['320000.00', '150000.00', '280000.00', '450000.00'][i],
        'purpose': [
          'Поставка оборудования',
          'Консультационные услуги',
          'Оплата услуг',
          'Аренда офиса'
        ][i],
        'status': i == 1 ? 'PENDING_APPROVAL' : 'EXECUTED',
        'author': 'user',
        'reason': '',
        'created_at': '2026-10-24T05:00:00Z',
        'approver': i == 1 ? null : 'user',
        'destination_name': [
          'ТОО Альфа',
          'ТОО Вектор',
          'ИП Садыков',
          'ТОО Альфа'
        ][i],
        'destination_number': 'DEMO-VECTOR-001'
      })
  ];
  return s;
}

Future<void> loadFonts() async {
  final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (file.existsSync()) {
    final loader = FontLoader('BankSans')
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  } else {
    final loader = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await loader.load();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('Dashboard adapts without overflow at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = fixture();
      await tester.pumpWidget(BankApp(store: s));
      await tester.pumpAndSettle();
      expect(find.text('Обзор'), findsWidgets);
      expect(find.text('2 450 000 ₸'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 1440 && const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('screenshots/dashboard-desktop.png'));
      }
      if (width == 360 && const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('screenshots/dashboard-mobile.png'));
      }
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    });
  }
  testWidgets('Viewer has no payment creation action', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = fixture(role: 'VIEWER');
    await tester.pumpWidget(BankApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('Новый платёж'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets('Payment form validates empty recipient before sending',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = fixture();
    await tester.pumpWidget(BankApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый платёж'));
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await tester.enterText(find.byType(TextFormField).at(0), 'DEMO-VECTOR-001');
      await tester.enterText(find.byType(TextFormField).at(1), '150000');
      await tester.enterText(find.byType(TextFormField).at(2), 'Оплата услуг');
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/payment-form.png'));
      for (var i = 0; i < 3; i++) { await tester.enterText(find.byType(TextFormField).at(i), ''); }
    }
    await tester.tap(find.text('На согласование'));
    await tester.pumpAndSettle();
    expect(find.text('Введите номер счёта'), findsOneWidget);
    expect(s.pending, isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets('Owner sees approval controls on a pending payment',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = fixture();
    await tester.pumpWidget(BankApp(store: s));
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(MaterialApp));
    // Use the dashboard row, preserving the same provider and navigator.
    await tester.tap(find.text('Консультационные услуги'));
    await tester.pumpAndSettle();
    expect(find.text('Одобрить'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('screenshots/payment-approval.png'));
    }
    expect(element.mounted, true);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
