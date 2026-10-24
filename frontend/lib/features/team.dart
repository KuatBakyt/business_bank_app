import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design.dart';
import '../core/models.dart';
import '../core/store.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  bool busy = false;
  Future<void> add() async {
    final s = context.read<BankStore>();
    final email = await askText(context, 'Добавить участника',
        label: 'Email зарегистрированного пользователя');
    if (email == null || !mounted) return;
    final role = await showDialog<String>(
        context: context,
        builder: (c) =>
            SimpleDialog(title: const Text('Роль сотрудника'), children: [
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, 'ACCOUNTANT'),
                  child: const ListTile(
                      leading: Icon(Icons.edit_note),
                      title: Text('Бухгалтер'),
                      subtitle: Text('Готовит платежи, но не одобряет их'))),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, 'VIEWER'),
                  child: const ListTile(
                      leading: Icon(Icons.visibility_outlined),
                      title: Text('Наблюдатель'),
                      subtitle: Text('Просматривает счета и операции'))),
            ]));
    if (role == null || !mounted) return;
    setState(() => busy = true);
    try {
      await s.api.request('POST', 'companies/${s.company!.id}/members/',
          body: {'email': email, 'role': role});
      await s.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(Json member, Json body) async {
    final s = context.read<BankStore>();
    setState(() => busy = true);
    try {
      await s.api.request(
          'PATCH', 'companies/${s.company!.id}/members/${member['id']}/',
          body: body);
      await s.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Участники', 'Команда и права доступа',
          action: s.owner
              ? FilledButton.icon(
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Добавить участника'))
              : null),
      Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'Владелец одобряет платежи, бухгалтер создаёт их, наблюдатель просматривает данные.',
            style: TextStyle(color: muted)),
        const SizedBox(height: 25),
        for (final member in s.members)
          Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CircleAvatar(
                        backgroundColor: const Color(0xFFEAF2F8),
                        child: Icon(
                            member['role'] == 'OWNER'
                                ? Icons.verified_user_outlined
                                : Icons.person_outline,
                            color: navy)),
                    SizedBox(
                        width: 240,
                        child: Text(member['email'] as String,
                            overflow: TextOverflow.ellipsis)),
                    if (s.owner && member['role'] != 'OWNER')
                      SizedBox(
                          width: 185,
                          child: DropdownButtonFormField<String>(
                              key:
                                  ValueKey('${member['id']}-${member['role']}'),
                              initialValue: member['role'] as String,
                              items: const [
                                DropdownMenuItem(
                                    value: 'ACCOUNTANT',
                                    child: Text('Бухгалтер')),
                                DropdownMenuItem(
                                    value: 'VIEWER', child: Text('Наблюдатель'))
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) {
                                      if (v != null)
                                        change(member, {'role': v});
                                    }))
                    else
                      Text(roleLabels[member['role']] ?? '',
                          style: const TextStyle(color: muted)),
                    if (s.owner && member['role'] != 'OWNER')
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                              title: Text(
                                                  member['is_active'] == true
                                                      ? 'Отключить доступ?'
                                                      : 'Восстановить доступ?'),
                                              content: Text(
                                                  member['email'] as String),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child:
                                                        const Text('Отмена')),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const Text(
                                                        'Подтвердить'))
                                              ]));
                                  if (confirm == true && mounted)
                                    change(member, {
                                      'is_active': member['is_active'] != true
                                    });
                                },
                          child: Text(member['is_active'] == true
                              ? 'Отключить'
                              : 'Восстановить')),
                    if (member['is_active'] != true)
                      const Text('Доступ отключён',
                          style: TextStyle(color: Colors.red)),
                  ])),
      ])),
    ]);
  }
}

class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  List<Json> rows = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final s = context.read<BankStore>();
    try {
      final result = await s.api.all('companies/${s.company!.id}/audit/');
      if (mounted) setState(() => rows = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    const labels = {
      'company.created': 'Компания создана',
      'member.added': 'Добавлен участник',
      'member.changed': 'Изменены права участника',
      'account.opened': 'Открыт счёт',
      'account.closed': 'Закрыт счёт',
      'payment.created': 'Создан платёж',
      'payment.edited': 'Изменён черновик',
      'payment.submit': 'Отправлен на согласование',
      'payment.approve': 'Платёж исполнен',
      'payment.reject': 'Платёж отклонён',
      'payment.cancel': 'Платёж отменён',
      'demo.funded': 'Тестовое пополнение'
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Аудит', 'Неизменяемая история действий команды',
          action: OutlinedButton.icon(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'))),
      Surface(
          child: loading
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator()))
              : error != null
                  ? EmptyState('Не удалось загрузить аудит', error!,
                      action: TextButton(
                          onPressed: load, child: const Text('Повторить')))
                  : rows.isEmpty
                      ? const EmptyState('Пока нет событий',
                          'Здесь появятся действия команды.')
                      : Column(
                          children: rows
                              .map((r) => ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFEAF5F4),
                                      child: Icon(Icons.history, color: teal)),
                                  title: Text(labels[r['action']] ??
                                      r['action'] as String),
                                  subtitle: Text(
                                      '${r['actor'] == null ? 'Система' : s.memberName(r['actor'] as String)}\n${shortDate(r['created_at'] as String)}\nID: ${r['entity_id']}'),
                                  isThreeLine: true))
                              .toList())),
    ]);
  }
}
