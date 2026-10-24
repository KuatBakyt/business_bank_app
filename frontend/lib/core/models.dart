typedef Json = Map<String, dynamic>;

class Money {
  static BigInt cents(String value) {
    final normalized = value
        .trim()
        .replaceAll(' ', '')
        .replaceAll('\u00a0', '')
        .replaceAll(',', '.');
    if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(normalized)) {
      throw const FormatException('Введите сумму с точностью до двух знаков');
    }
    final negative = normalized.startsWith('-');
    final parts = normalized.replaceFirst('-', '').split('.');
    final result = BigInt.parse(parts[0]) * BigInt.from(100) +
        BigInt.parse(parts.length == 2 ? parts[1].padRight(2, '0') : '0');
    return negative ? -result : result;
  }

  static String decimal(BigInt value) {
    final abs = value.abs();
    return '${value.isNegative ? '-' : ''}${abs ~/ BigInt.from(100)}.${(abs % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

  static String input(String value) => decimal(cents(value));

  static String format(String value) {
    final amount = cents(value);
    final whole = (amount.abs() ~/ BigInt.from(100)).toString();
    final grouped =
        whole.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
    final remainder =
        (amount.abs() % BigInt.from(100)).toString().padLeft(2, '0');
    return '${amount.isNegative ? '−' : ''}$grouped${remainder == '00' ? '' : ',$remainder'} ₸';
  }
}

class Company {
  final String id, name, owner;
  Company.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        owner = j['owner'] as String;
}

class BankAccount {
  final String id, number, name, balance, status;
  BankAccount.fromJson(Json j)
      : id = j['id'] as String,
        number = j['number'] as String,
        name = j['name'] as String,
        balance = j['cached_balance'] as String,
        status = j['status'] as String;
  bool get active => status == 'ACTIVE';
}

class Payment {
  final String id,
      source,
      destination,
      amount,
      purpose,
      status,
      author,
      reason,
      created;
  final String? approver, executed, destinationNumber;
  final String recipient;
  Payment.fromJson(Json j)
      : id = j['id'] as String,
        source = j['source'] as String,
        destination = j['destination'] as String,
        amount = j['amount'] as String,
        purpose = j['purpose'] as String,
        status = j['status'] as String,
        author = j['author'] as String,
        reason = j['reason'] as String? ?? '',
        created = j['created_at'] as String,
        approver = j['approver'] as String?,
        executed = j['executed_at'] as String?,
        destinationNumber = j['destination_number'] as String?,
        recipient =
            j['destination_name'] as String? ?? j['destination'] as String;
}

const statuses = <String, String>{
  'DRAFT': 'Черновик',
  'NOT_EXECUTED': 'Не исполнен',
  'PENDING_APPROVAL': 'На согласовании',
  'EXECUTED': 'Исполнен',
  'REJECTED': 'Отклонён',
  'CANCELLED': 'Отменён',
  'QUEUED': 'В очереди',
  'PROCESSING': 'Готовится',
  'READY': 'Готова',
  'FAILED': 'Ошибка подготовки',
  'EXPIRED': 'Срок истёк',
  'ACTIVE': 'Активен',
  'CLOSED': 'Закрыт',
};
const roleLabels = {
  'OWNER': 'Владелец',
  'ACCOUNTANT': 'Бухгалтер',
  'VIEWER': 'Наблюдатель'
};

String shortDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final d = date.toUtc().add(const Duration(hours: 5));
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String dateValue(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
