import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/api.dart';
import 'core/design.dart';
import 'core/store.dart';
import 'features/auth.dart';
import 'features/shell.dart';

void main() { runApp(BankApp(store: BankStore(BankApi()))); }
class BankApp extends StatelessWidget {
  final BankStore store;
  const BankApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(value: store,
    child: MaterialApp(locale: const Locale('ru'), supportedLocales: const [Locale('ru')], localizationsDelegates: GlobalMaterialLocalizations.delegates, title: 'Business Bank', debugShowCheckedModeBanner: false, theme: bankTheme(),
      home: Consumer<BankStore>(builder: (_, s, __) => s.user == null ? const AuthScreen() : const BankShell())));
}
