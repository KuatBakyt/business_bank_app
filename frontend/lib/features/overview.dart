import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/design.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'payments.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Обзор', 'Ваш бизнес под контролем',
          action: s.writer
              ? FilledButton.icon(
                  onPressed: s.canWrite ? () => openPaymentForm(context) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Новый платёж'))
              : null),
      LayoutBuilder(builder: (_, c) {
        final width =
            c.maxWidth < 600 ? (c.maxWidth - 16) / 2 : (c.maxWidth - 32) / 3;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          Metric(
              'Общий баланс',
              Money.format(Money.decimal(s.total)),
              Icons.account_balance_wallet_outlined,
              const Color(0xFFEAF7F7),
              c.maxWidth < 600 ? c.maxWidth : width),
          Metric('Счета', '${s.accounts.length}', Icons.description_outlined,
              const Color(0xFFEEF5FE), width),
          Metric(
              c.maxWidth < 600 ? 'Ожидают' : 'На согласовании',
              '${s.payments.where((p) => p.status == 'PENDING_APPROVAL').length}',
              Icons.schedule,
              const Color(0xFFFFF8E9),
              width),
        ]);
      }),
      const SizedBox(height: 32),
      Text('Мои счета', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 17),
      AccountGrid(accounts: s.accounts.take(4).toList()),
      const SizedBox(height: 30),
      Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Последние платежи',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        PaymentTable(payments: s.payments.take(6).toList()),
      ])),
    ]);
  }
}

class Metric extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  final double width;
  const Metric(this.title, this.value, this.icon, this.color, this.width,
      {super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title)),
          Icon(icon, color: teal, size: 24)
        ]),
        const SizedBox(height: 19),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: ink)))
      ]));
}

class AccountGrid extends StatelessWidget {
  final List<BankAccount> accounts;
  const AccountGrid({super.key, required this.accounts});
  @override
  Widget build(BuildContext context) => accounts.isEmpty
      ? const Surface(
          child:
              EmptyState('Пока нет счетов', 'Откройте счёт в разделе «Счета».'))
      : LayoutBuilder(
          builder: (_, c) => Wrap(
              spacing: 18,
              runSpacing: 18,
              children: accounts
                  .map((a) => SizedBox(
                      width:
                          c.maxWidth < 650 ? c.maxWidth : (c.maxWidth - 18) / 2,
                      child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => AccountHistory(account: a)),
                          child: Surface(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  const CircleAvatar(
                                      backgroundColor: Color(0xFFE5F5F2),
                                      child: Icon(
                                          Icons.account_balance_wallet_outlined,
                                          color: teal)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(a.name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 3),
                                        Text(a.number,
                                            style: const TextStyle(
                                                color: muted, fontSize: 11),
                                            overflow: TextOverflow.ellipsis)
                                      ])),
                                  if (!a.active)
                                    StatusPill(a.status)
                                  else
                                    const Icon(Icons.chevron_right,
                                        color: muted)
                                ]),
                                const SizedBox(height: 22),
                                Text(Money.format(a.balance),
                                    style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                const Text('KZT · История операций',
                                    style:
                                        TextStyle(color: muted, fontSize: 12)),
                              ])))))
                  .toList()));
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Счета', 'Средства вашей компании в тенге',
          action: s.owner
              ? FilledButton.icon(
                  onPressed: s.mutating || s.pending != null
                      ? null
                      : () async {
                          final name =
                              await askText(context, 'Открыть учебный счёт');
                          if (name == null || !context.mounted) return;
                          try {
                            await s.api.request(
                                'POST', 'companies/${s.company!.id}/accounts/',
                                body: {'name': name});
                            await s.refresh();
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Открыть счёт'))
              : null),
      AccountGrid(accounts: s.accounts),
      const SizedBox(height: 24),
      const Text(
          'Остатки основаны на проведённых операциях. Платежи на согласовании не резервируют средства.',
          style: TextStyle(color: muted)),
    ]);
  }
}

class AccountHistory extends StatefulWidget {
  final BankAccount account;
  const AccountHistory({super.key, required this.account});
  @override
  State<AccountHistory> createState() => _AccountHistoryState();
}

class _AccountHistoryState extends State<AccountHistory> {
  List<Json> rows = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await context
          .read<BankStore>()
          .api
          .all('accounts/${widget.account.id}/transactions/');
      if (mounted) {
        setState(() {
          rows = result;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    return AlertDialog(
        title: Text(widget.account.name),
        content: SizedBox(
            width: 760,
            height: 430,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(widget.account.number,
                  style: const TextStyle(color: muted)),
              const SizedBox(height: 15),
              Text(
                  Money.format(s.account(widget.account.id)?.balance ??
                      widget.account.balance),
                  style: Theme.of(context).textTheme.headlineSmall),
              const Divider(height: 30),
              Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(
                              child: TextButton(
                                  onPressed: load,
                                  child: Text('$error · Повторить')))
                          : rows.isEmpty
                              ? const EmptyState('Операций пока нет',
                                  'Здесь появятся проведённые списания и зачисления.')
                              : ListView.separated(
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (_, i) {
                                    final r = rows[i];
                                    final credit = r['side'] == 'CREDIT';
                                    return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                            credit
                                                ? Icons.south_west
                                                : Icons.north_east,
                                            color: credit ? teal : muted),
                                        title: Text(r['purpose'] as String),
                                        subtitle: Text(shortDate(
                                            r['posted_at'] as String)),
                                        trailing: Text(
                                            '${credit ? '+' : '−'}${Money.format(r['amount'] as String)}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: credit ? teal : ink)));
                                  })),
            ])),
        actions: [
          if (s.owner && widget.account.active)
            TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await s.api.request(
                              'POST', 'accounts/${widget.account.id}/close/',
                              body: {});
                          await s.refresh();
                          if (context.mounted) Navigator.pop(context);
                        } on ApiFailure catch (e) {
                          if (context.mounted) showError(context, e);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Закрыть пустой счёт')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'))
        ]);
  }
}
