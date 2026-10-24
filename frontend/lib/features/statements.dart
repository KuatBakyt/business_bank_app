import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/platform.dart' as platform;

class StatementsPage extends StatefulWidget {
  const StatementsPage({super.key});
  @override
  State<StatementsPage> createState() => _StatementsPageState();
}

class _StatementsPageState extends State<StatementsPage>
    with WidgetsBindingObserver {
  String? account;
  String format = 'pdf';
  DateTime from = DateTime.now().subtract(const Duration(days: 30)),
      to = DateTime.now();
  List<Json> exports = [];
  String? error;
  bool loading = false, creating = false, visible = true;
  final Set<String> downloading = {};
  Timer? timer;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    account = context.read<BankStore>().accounts.firstOrNull?.id;
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (visible && !loading) load();
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

  Future<void> load() async {
    final selected = account;
    if (selected == null) return;
    final revision = ++epoch;
    if (mounted) setState(() => loading = true);
    try {
      final rows = await context
          .read<BankStore>()
          .api
          .all('accounts/$selected/statement-exports/');
      if (mounted && epoch == revision) {
        setState(() {
          exports = rows;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && epoch == revision) setState(() => error = '$e');
    } finally {
      if (mounted && epoch == revision) setState(() => loading = false);
    }
  }

  Future<void> pick(bool first) async {
    final date = await showDatePicker(
        context: context,
        initialDate: first ? from : to,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        helpText: first ? 'Начало периода' : 'Конец периода');
    if (date != null && mounted) {
      setState(() {
        if (first) {
          from = date;
        } else {
          to = date;
        }
      });
    }
  }

  Future<void> create() async {
    if (to.isBefore(from) || to.difference(from).inDays >= 366) {
      showError(context, 'Выберите период от 1 до 366 дней');
      return;
    }
    setState(() => creating = true);
    try {
      await context.read<BankStore>().api.request(
          'POST', 'accounts/$account/statement-exports/', body: {
        'date_from': dateValue(from),
        'date_to': dateValue(to),
        'format': format
      });
      await load();
      if (mounted) {
        showSuccess(context,
            'Выписка в очереди. Обычно подготовка занимает до минуты.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> download(Json export) async {
    final id = export['id'] as String;
    setState(() => downloading.add(id));
    try {
      final bytes = await context
              .read<BankStore>()
              .api
              .request('GET', 'statement-exports/$id/download/', binary: true)
          as Uint8List;
      platform.downloadBytes(bytes,
          'BusinessBank-${export['date_from']}-${export['date_to']}.${export['format']}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => downloading.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    if (s.accounts.isEmpty) {
      return const EmptyState(
          'Нет счетов для выписки', 'Сначала откройте учебный счёт.');
    }
    // Accounts can arrive after the initial company refresh.
    if (account == null) {
      account = s.accounts.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Выписки', 'Проведённые операции за выбранный период'),
      Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Подготовить выписку',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 22),
        Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 270,
                  child: DropdownButtonFormField<String>(
                      initialValue: account,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Счёт'),
                      items: s.accounts
                          .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: creating
                          ? null
                          : (v) {
                              setState(() {
                                account = v;
                                exports = [];
                              });
                              load();
                            })),
              OutlinedButton.icon(
                  onPressed: () => pick(true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: Text('С ${dateValue(from)}')),
              OutlinedButton.icon(
                  onPressed: () => pick(false),
                  icon: const Icon(Icons.event_outlined, size: 17),
                  label: Text('По ${dateValue(to)}')),
              SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                      initialValue: format,
                      items: const [
                        DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                        DropdownMenuItem(value: 'csv', child: Text('CSV'))
                      ],
                      onChanged: (v) => setState(() => format = v ?? 'pdf'))),
              FilledButton.icon(
                  onPressed: creating ? null : create,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(creating ? 'Создаём…' : 'Подготовить')),
            ]),
        const SizedBox(height: 20),
        const Text(
            'Период считается по времени Алматы. Файлы доступны 24 часа; доступ проверяется при скачивании.',
            style: TextStyle(color: muted, fontSize: 12)),
      ])),
      const SizedBox(height: 25),
      Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('История выписок',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          IconButton(
              tooltip: 'Обновить выписки',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh))
        ]),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(error!, style: const TextStyle(color: Colors.red))),
        if (exports.isEmpty && !loading)
          const EmptyState(
              'Нет подготовленных выписок', 'Выберите период и формат выше.'),
        for (final export in exports)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.description_outlined, color: teal),
                      Text('${export['date_from']} — ${export['date_to']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text((export['format'] as String).toUpperCase(),
                          style: const TextStyle(color: muted)),
                      StatusPill(export['status'] as String),
                      if (export['status'] == 'READY')
                        OutlinedButton.icon(
                            onPressed: downloading.contains(export['id'])
                                ? null
                                : () => download(export),
                            icon: const Icon(Icons.download, size: 17),
                            label: Text(downloading.contains(export['id'])
                                ? 'Скачиваем…'
                                : 'Скачать')),
                      if (export['status'] == 'FAILED')
                        const Text(
                            'Не удалось подготовить. Создайте выписку заново.',
                            style: TextStyle(color: muted)),
                    ]),
                const Divider(height: 20),
              ])),
      ])),
    ]);
  }
}
