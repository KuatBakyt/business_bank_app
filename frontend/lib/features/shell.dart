import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'overview.dart';
import 'payments.dart';
import 'statements.dart';
import 'team.dart';

class BankShell extends StatefulWidget {
  const BankShell({super.key});
  @override
  State<BankShell> createState() => _BankShellState();
}

class _BankShellState extends State<BankShell> with WidgetsBindingObserver {
  int page = 0;
  Timer? timer;
  bool visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !visible) return;
      final s = context.read<BankStore>();
      if (!s.loading && !s.mutating) s.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> newCompany() async {
    final name = await askText(context, 'Новая компания');
    if (name == null || !mounted) return;
    try {
      await context.read<BankStore>().createCompany(name);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget navigation(bool drawer) {
    final s = context.watch<BankStore>();
    const labels = [
      'Обзор',
      'Счета',
      'Платежи',
      'Выписки',
      'Участники',
      'Аудит'
    ];
    const icons = [
      Icons.dashboard_outlined,
      Icons.account_balance_wallet_outlined,
      Icons.swap_horiz_rounded,
      Icons.description_outlined,
      Icons.people_outline,
      Icons.verified_user_outlined
    ];
    final current = page == 5 && !s.owner ? 0 : page;
    return Container(
        width: 236,
        color: navy,
        padding: const EdgeInsets.fromLTRB(18, 35, 18, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 36),
              child: Row(children: [
                Icon(Icons.account_balance_rounded,
                    color: Color(0xFF5CE0D1), size: 33),
                SizedBox(width: 12),
                Text('Business\nBank',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.15))
              ])),
          for (var i = 0; i < labels.length; i++)
            if (i != 5 || s.owner)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                      color: current == i
                          ? const Color(0xFF1D425E)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9)),
                          leading: Icon(icons[i],
                              size: 22,
                              color: current == i
                                  ? const Color(0xFF70E4DA)
                                  : const Color(0xFFB7CCDC)),
                          title: Text(labels[i],
                              style: TextStyle(
                                  color: current == i
                                      ? Colors.white
                                      : const Color(0xFFCDDBE7),
                                  fontSize: 14,
                                  fontWeight: current == i
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                          onTap: () {
                            setState(() => page = i);
                            if (drawer) Navigator.pop(context);
                          }))),
          const Spacer(),
          const Divider(color: Color(0xFF315069)),
          ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              leading: const CircleAvatar(
                  backgroundColor: Color(0xFFDCE9F3),
                  child: Icon(Icons.person_outline, color: navy)),
              title: Text(s.user?['first_name'] as String? ?? 'Пользователь',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(roleLabels[s.role] ?? 'Выберите компанию',
                  style:
                      const TextStyle(color: Color(0xFFB7CCDC), fontSize: 11))),
          TextButton.icon(
              onPressed: s.pending != null || s.mutating
                  ? null
                  : () async {
                      try {
                        await s.logout();
                      } catch (e) {
                        if (mounted) showError(context, e);
                      }
                    },
              icon: const Icon(Icons.logout, size: 19),
              label: const Text('Выйти'),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38)),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    final current = page == 5 && !s.owner ? 0 : page;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final content = s.company == null
          ? EmptyState('Ваше рабочее пространство',
              'Создайте компанию, чтобы открыть первый учебный счёт.',
              action: FilledButton.icon(
                  onPressed: newCompany,
                  icon: const Icon(Icons.add),
                  label: const Text('Создать компанию')))
          : switch (current) {
              0 => const OverviewPage(),
              1 => const AccountsPage(),
              2 => const PaymentsPage(),
              3 => const StatementsPage(),
              4 => const TeamPage(),
              _ => const AuditPage()
            };
      return Scaffold(
          drawer: wide ? null : Drawer(child: navigation(true)),
          body: Row(children: [
            if (wide) navigation(false),
            Expanded(
                child: Column(children: [
              Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: wide ? 34 : 16, vertical: 19),
                  color: Colors.white,
                  child: Row(children: [
                    if (!wide)
                      Builder(
                          builder: (c) => IconButton(
                              tooltip: 'Меню',
                              onPressed: () => Scaffold.of(c).openDrawer(),
                              icon: const Icon(Icons.menu))),
                    Expanded(
                        child: s.companies.isEmpty
                            ? const Text('Business Bank',
                                style: TextStyle(fontWeight: FontWeight.w700))
                            : DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                    value: s.company?.id,
                                    isExpanded: true,
                                    items: s.companies
                                        .map((c) => DropdownMenuItem(
                                            value: c.id,
                                            child: Text(c.name,
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: s.mutating
                                        ? null
                                        : (id) {
                                            if (id != null) {
                                              s.select(s.companies.firstWhere(
                                                  (c) => c.id == id));
                                            }
                                          }))),
                    const SizedBox(width: 14),
                    IconButton(
                        tooltip: 'Создать компанию',
                        onPressed: s.mutating ? null : newCompany,
                        icon: const Icon(Icons.add_business_outlined)),
                    IconButton(
                        tooltip: 'Обновить данные',
                        onPressed: s.loading ? null : s.refresh,
                        icon: const Icon(Icons.refresh_rounded)),
                    if (wide)
                      Padding(
                          padding: const EdgeInsets.only(left: 18),
                          child: Row(children: [
                            const CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(0xFFEAF0F7),
                                child: Icon(Icons.person_outline,
                                    size: 20, color: navy)),
                            const SizedBox(width: 10),
                            Text(s.user?['email'] as String? ?? '',
                                style:
                                    const TextStyle(color: muted, fontSize: 12))
                          ])),
                  ])),
              if (s.loading) const LinearProgressIndicator(minHeight: 2),
              if (s.pending != null)
                Container(
                    width: double.infinity,
                    color: const Color(0xFFFFF3D6),
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                        spacing: 15,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(Icons.info_outline,
                              color: Color(0xFFAD6700)),
                          Text(
                              'Результат запроса «${s.pending!.label}» не подтверждён. Повтор использует прежний ключ.'),
                          OutlinedButton(
                              onPressed: s.mutating
                                  ? null
                                  : () async {
                                      try {
                                        await s.retryPending();
                                        if (context.mounted) {
                                          showSuccess(context,
                                              'Результат запроса получен');
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          showError(context, e);
                                        }
                                      }
                                    },
                              child: Text(s.mutating
                                  ? 'Проверяем…'
                                  : 'Проверить результат'))
                        ])),
              if (s.error != null)
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: const Color(0xFFFFEDED),
                    child: Row(children: [
                      Expanded(
                          child: Text(s.error!,
                              style:
                                  const TextStyle(color: Color(0xFF913B3B)))),
                      TextButton(
                          onPressed: s.refresh, child: const Text('Повторить'))
                    ])),
              Expanded(
                  child: SingleChildScrollView(
                      padding: EdgeInsets.all(wide ? 34 : 18),
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1400),
                              child: KeyedSubtree(
                                  key: ValueKey(s.company?.id),
                                  child: content))))),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.science_outlined, size: 14, color: muted),
                        SizedBox(width: 6),
                        Flexible(
                            child: Text('Учебный проект · Тестовые средства',
                                style: TextStyle(color: muted, fontSize: 11)))
                      ])),
            ])),
          ]));
    });
  }
}
