import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design.dart';
import '../core/models.dart';
import '../core/store.dart';

Future<void> openPaymentForm(BuildContext context, {Payment? payment}) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PaymentForm(payment: payment));
void openPayment(BuildContext context, Payment payment) => showDialog<void>(
    context: context, builder: (_) => PaymentDetail(payment: payment));

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  String filter = 'ALL', search = '';
  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    final list = s.payments
        .where((p) =>
            (filter == 'ALL' || p.status == filter) &&
            ('${p.purpose} ${p.id} ${p.recipient}'
                .toLowerCase()
                .contains(search.toLowerCase())))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Платежи', 'Черновики, согласование и история',
          action: s.writer
              ? FilledButton.icon(
                  onPressed: s.canWrite ? () => openPaymentForm(context) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Новый платёж'))
              : null),
      Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 15,
            runSpacing: 15,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 260,
                  child: TextField(
                      decoration: const InputDecoration(
                          hintText: 'Поиск платежа',
                          prefixIcon: Icon(Icons.search)),
                      onChanged: (v) => setState(() => search = v))),
              SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                      initialValue: filter,
                      items: [
                        const DropdownMenuItem(
                            value: 'ALL', child: Text('Все статусы')),
                        for (final key in [
                          'DRAFT',
                          'PENDING_APPROVAL',
                          'EXECUTED',
                          'REJECTED',
                          'CANCELLED'
                        ])
                          DropdownMenuItem(
                              value: key, child: Text(statuses[key]!))
                      ],
                      onChanged: (v) => setState(() => filter = v ?? 'ALL'))),
              Text('${list.length} платежей',
                  style: const TextStyle(color: muted)),
            ]),
        const SizedBox(height: 24),
        PaymentTable(payments: list),
      ])),
    ]);
  }
}

class PaymentTable extends StatelessWidget {
  final List<Payment> payments;
  const PaymentTable({super.key, required this.payments});
  @override
  Widget build(BuildContext context) => payments.isEmpty
      ? const EmptyState(
          'Платежей пока нет', 'Создайте первый платёж или измените фильтр.')
      : LayoutBuilder(builder: (_, box) {
          if (box.maxWidth < 650) {
            return Column(
                children: payments
                    .map((p) => InkWell(
                        onTap: () => openPayment(context, p),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(p.recipient,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700))),
                                    const SizedBox(width: 8),
                                    Text(Money.format(p.amount),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(p.purpose,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: muted)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                      spacing: 12,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        StatusPill(p.status),
                                        Text(shortDate(p.created),
                                            style: const TextStyle(
                                                color: muted, fontSize: 11))
                                      ]),
                                  const Divider(height: 25),
                                ]))))
                    .toList());
          }
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                      horizontalMargin: 0,
                      columnSpacing: 25,
                      headingTextStyle:
                          const TextStyle(color: muted, fontSize: 12),
                      dataRowMinHeight: 66,
                      dataRowMaxHeight: 76,
                      showCheckboxColumn: false,
                      columns: const [
                        DataColumn(label: Text('Дата · Алматы')),
                        DataColumn(label: Text('Получатель')),
                        DataColumn(label: Text('Назначение')),
                        DataColumn(label: Text('Сумма'), numeric: true),
                        DataColumn(label: Text('Статус')),
                        DataColumn(label: Text(''))
                      ],
                      rows: payments
                          .map((p) => DataRow(
                                  onSelectChanged: (_) =>
                                      openPayment(context, p),
                                  cells: [
                                    DataCell(Text(
                                        shortDate(p.created)
                                            .replaceFirst(' · ', '\n'),
                                        style: const TextStyle(
                                            color: muted, fontSize: 12))),
                                    DataCell(SizedBox(
                                        width: 150,
                                        child: Text(p.recipient,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis))),
                                    DataCell(SizedBox(
                                        width: 180,
                                        child: Text(p.purpose,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: muted, fontSize: 12)))),
                                    DataCell(Text(Money.format(p.amount),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                                    DataCell(StatusPill(p.status)),
                                    const DataCell(Icon(Icons.chevron_right,
                                        color: muted)),
                                  ]))
                          .toList())));
        });
}

class PaymentForm extends StatefulWidget {
  final Payment? payment;
  const PaymentForm({super.key, this.payment});
  @override
  State<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentForm> {
  final form = GlobalKey<FormState>();
  final number = TextEditingController(),
      amount = TextEditingController(),
      purpose = TextEditingController();
  String? source, destination, recipient, resolvedNumber, savedId;
  bool resolving = false, working = false;
  @override
  void initState() {
    super.initState();
    final s = context.read<BankStore>();
    final p = widget.payment;
    source = p?.source ?? s.accounts.where((a) => a.active).firstOrNull?.id;
    if (p != null) {
      amount.text = p.amount;
      purpose.text = p.purpose;
      savedId = p.id;
      destination = p.destination;
      recipient = p.recipient;
      number.text = p.destinationNumber ?? p.destination;
      resolvedNumber = number.text;
    }
  }

  @override
  void dispose() {
    number.dispose();
    amount.dispose();
    purpose.dispose();
    super.dispose();
  }

  Future<void> resolve() async {
    final lookup = number.text.trim();
    if (lookup.isEmpty) return;
    setState(() {
      resolving = true;
      destination = null;
      recipient = null;
    });
    try {
      final result = await context
              .read<BankStore>()
              .api
              .request('POST', 'recipients/resolve/', body: {'number': lookup})
          as Json;
      if (mounted && number.text.trim() == lookup) {
        setState(() {
          destination = result['id'] as String;
          recipient = result['company_name'] as String;
          resolvedNumber = lookup;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> save(bool submit) async {
    if (!form.currentState!.validate()) return;
    if (destination == null || number.text.trim() != resolvedNumber) {
      showError(context, 'Сначала проверьте счёт получателя');
      return;
    }
    if (source == destination) {
      showError(context, 'Выберите другой счёт получателя');
      return;
    }
    final s = context.read<BankStore>();
    if (submit) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Проверка платежа'),
                  content: Text(
                      'Получатель: $recipient\nСумма: ${Money.format(Money.input(amount.text))}\n\nПосле отправки реквизиты нельзя изменить. Средства спишутся только после одобрения.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Отправить'))
                  ]));
      if (confirm != true || !mounted) return;
    }
    setState(() => working = true);
    try {
      final body = <String, dynamic>{
        'source': source,
        'destination': destination,
        'amount': Money.input(amount.text),
        'purpose': purpose.text.trim()
      };
      final result = await s.command(
          savedId == null
              ? 'companies/${s.company!.id}/payments/'
              : 'payments/$savedId/',
          body,
          method: savedId == null ? 'POST' : 'PATCH',
          label: 'Сохранение платежа');
      savedId = result['id'] as String;
      if (submit) {
        await s.command('payments/$savedId/submit/', {},
            label: 'Отправка на согласование');
      }
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context,
            submit ? 'Платёж отправлен на согласование' : 'Черновик сохранён');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    final locked = working || s.mutating || s.pending != null;
    final sources =
        s.accounts.where((a) => a.active || a.id == source).toList();
    return AlertDialog(
        title: Row(children: [
          Expanded(
              child: Text(widget.payment == null
                  ? 'Новый платёж'
                  : 'Редактировать черновик')),
          IconButton(
              tooltip: 'Закрыть',
              onPressed: working ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close))
        ]),
        content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                              'Заполните реквизиты и проверьте получателя.',
                              style: TextStyle(color: muted)),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<String>(
                              initialValue: source,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Счёт списания'),
                              items: sources
                                  .map((a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text(
                                          '${a.name} · ${Money.format(a.balance)}',
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: locked
                                  ? null
                                  : (v) => setState(() => source = v),
                              validator: (v) =>
                                  v == null ? 'Откройте счёт списания' : null),
                          const SizedBox(height: 18),
                          TextFormField(
                              controller: number,
                              enabled: !locked && !resolving,
                              decoration: const InputDecoration(
                                  labelText: 'Счёт получателя',
                                  hintText: 'DEMO-VECTOR-001'),
                              onChanged: (_) => setState(() {
                                    destination = null;
                                    recipient = null;
                                  }),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Введите номер счёта'
                                  : null),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                              onPressed: locked || resolving ? null : resolve,
                              icon: const Icon(Icons.person_search_outlined,
                                  size: 18),
                              label: Text(resolving
                                  ? 'Проверяем…'
                                  : 'Проверить получателя')),
                          if (recipient != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(children: [
                                  const Icon(Icons.check_circle_outline,
                                      color: teal, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(recipient!,
                                          style: const TextStyle(
                                              color: teal,
                                              fontWeight: FontWeight.w600)))
                                ])),
                          const SizedBox(height: 18),
                          TextFormField(
                              controller: amount,
                              enabled: !locked,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Сумма', suffixText: '₸'),
                              validator: (v) {
                                try {
                                  final value = Money.cents(v ?? '');
                                  if (value <= BigInt.zero ||
                                      value > BigInt.from(10000000000)) {
                                    return 'Сумма от 0,01 до 100 000 000 ₸';
                                  }
                                } on FormatException {
                                  return 'Введите сумму, не более двух знаков после запятой';
                                }
                                return null;
                              }),
                          const SizedBox(height: 18),
                          TextFormField(
                              controller: purpose,
                              enabled: !locked,
                              maxLines: 3,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                  labelText: 'Назначение платежа'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Укажите назначение'
                                  : null),
                          const SizedBox(height: 12),
                          const Text(
                              'Только внутренний перевод тестовых средств. Комиссия отсутствует.',
                              style: TextStyle(color: muted, fontSize: 12)),
                        ])))),
        actions: [
          OutlinedButton(
              onPressed: locked || source == null ? null : () => save(false),
              child: const Text('Сохранить черновик')),
          FilledButton(
              onPressed: locked || source == null ? null : () => save(true),
              child: Text(working ? 'Сохраняем…' : 'На согласование'))
        ]);
  }
}

class PaymentDetail extends StatefulWidget {
  final Payment payment;
  const PaymentDetail({super.key, required this.payment});
  @override
  State<PaymentDetail> createState() => _PaymentDetailState();
}

class _PaymentDetailState extends State<PaymentDetail> {
  Future<void> action(Payment p, String action) async {
    final s = context.read<BankStore>();
    final body = <String, dynamic>{};
    if (action == 'reject') {
      final reason = await askText(context, 'Отклонить платёж',
          label: 'Причина отклонения');
      if (reason == null) return;
      body['reason'] = reason;
    } else {
      final confirmation = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(action == 'approve'
                      ? 'Одобрить перевод?'
                      : action == 'submit'
                          ? 'Отправить на согласование?'
                          : 'Отменить платёж?'),
                  content: Text(
                      '${p.recipient}\n${Money.format(p.amount)}\n${p.purpose}'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Подтвердить'))
                  ]));
      if (confirmation != true) return;
    }
    if (!mounted) return;
    try {
      await s.command('payments/${p.id}/$action/', body,
          label: 'Действие с платежом');
      if (mounted) showSuccess(context, 'Статус платежа обновлён');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BankStore>();
    final p = s.payments.where((v) => v.id == widget.payment.id).firstOrNull ??
        widget.payment;
    final editable = p.status == 'DRAFT' && p.author == s.userId && s.writer;
    final pending = p.status == 'PENDING_APPROVAL';
    final actionable = s.canWrite;
    return AlertDialog(
        title: const Text('Карточка платежа'),
        content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  StatusPill(p.status),
                  const SizedBox(height: 18),
                  Text(Money.format(p.amount),
                      style: Theme.of(context).textTheme.headlineLarge),
                  const Divider(height: 35),
                  detail('Получатель', p.recipient),
                  detail(
                      'Счёт получателя', p.destinationNumber ?? p.destination),
                  detail(
                      'Счёт списания', s.account(p.source)?.number ?? p.source),
                  detail('Назначение', p.purpose),
                  detail('Автор', s.memberName(p.author)),
                  detail('Создан · Алматы', shortDate(p.created)),
                  if (p.executed != null)
                    detail('Исполнен · Алматы', shortDate(p.executed!)),
                  if (p.reason.isNotEmpty)
                    detail('Причина отклонения', p.reason),
                  detail('ID платежа', p.id),
                  const SizedBox(height: 22),
                  const Text('Этапы платежа',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    const StatusPill('DRAFT'),
                    const Icon(Icons.arrow_right, color: muted),
                    const StatusPill('PENDING_APPROVAL'),
                    const Icon(Icons.arrow_right, color: muted),
                    StatusPill(p.status == 'DRAFT' || pending
                        ? 'NOT_EXECUTED'
                        : p.status)
                  ]),
                  if (pending)
                    const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Text(
                            'Ожидает решения владельца. Доступный остаток повторно проверяется при одобрении.',
                            style: TextStyle(color: muted))),
                ]))),
        actions: [
          if (editable)
            OutlinedButton(
                onPressed: actionable
                    ? () {
                        Navigator.pop(context);
                        openPaymentForm(context, payment: p);
                      }
                    : null,
                child: const Text('Редактировать')),
          if (editable)
            FilledButton(
                onPressed: actionable ? () => action(p, 'submit') : null,
                child: const Text('На согласование')),
          if (pending && s.owner) ...[
            OutlinedButton(
                onPressed: actionable ? () => action(p, 'reject') : null,
                child: const Text('Отклонить')),
            FilledButton.icon(
                onPressed: actionable ? () => action(p, 'approve') : null,
                icon: const Icon(Icons.check),
                label: const Text('Одобрить'))
          ],
          if ((p.status == 'DRAFT' || pending) &&
              s.writer &&
              (p.author == s.userId || s.owner))
            TextButton(
                onPressed: actionable ? () => action(p, 'cancel') : null,
                child: const Text('Отменить платёж')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть')),
        ]);
  }

  Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 3),
        SelectableText(value)
      ]));
}
