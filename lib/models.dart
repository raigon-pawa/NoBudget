import 'dart:math';

// All money is integer cents (AUD).

/// Document id that sorts by creation time, so lists keep the order things were added in.
String newId([int offset = 0]) => '${DateTime.now().microsecondsSinceEpoch + offset}';

enum AccountType { bank, credit, loan }

enum TxType { expense, income, transfer }

class Account {
  const Account({
    this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.limit = 0,
    required this.color,
  });

  final String? id;
  final String name;
  final AccountType type;
  final int balance; // bank: money held. credit/loan: amount owed.
  final int limit; // credit: credit limit. loan: original amount. bank: unused.
  final int color;

  bool get isDebt => type != AccountType.bank;
  int get available => type == AccountType.credit ? max(0, limit - balance) : 0;

  Account.fromMap(this.id, Map<String, Object?> m)
    : name = m['name'] as String,
      type = AccountType.values.byName(m['type'] as String),
      balance = m['balance'] as int,
      limit = m['limit'] as int,
      color = m['color'] as int;

  Map<String, Object?> toMap() => {'name': name, 'type': type.name, 'balance': balance, 'limit': limit, 'color': color};
}

const presets = [
  Account(name: 'CommBank', type: AccountType.bank, color: 0xFFFFCC00),
  Account(name: 'ANZ Plus', type: AccountType.bank, color: 0xFF4AA8FF),
  Account(name: 'Wise', type: AccountType.bank, color: 0xFF9FE870),
  Account(name: 'Revolut', type: AccountType.bank, color: 0xFFE6E6E6),
  Account(name: 'Up', type: AccountType.bank, color: 0xFFFF7A64),
  Account(name: 'Latitude', type: AccountType.loan, color: 0xFF6C8CFF),
  Account(name: 'Klarna', type: AccountType.credit, color: 0xFFFFB3C7),
  Account(name: 'Afterpay', type: AccountType.credit, color: 0xFFB2FCE4),
];

class Tx {
  const Tx({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.category = '',
    this.note = '',
    required this.date,
  });

  final String? id;
  final TxType type;
  final int amount; // always positive
  final String accountId;
  final String? toAccountId; // transfers only
  final String category; // expenses only
  final String note;
  final DateTime date;

  Tx.fromMap(this.id, Map<String, Object?> m)
    : type = TxType.values.byName(m['type'] as String),
      amount = m['amount'] as int,
      accountId = m['accountId'] as String,
      toAccountId = m['toAccountId'] as String?,
      category = m['category'] as String,
      note = m['note'] as String,
      date = DateTime.fromMillisecondsSinceEpoch(m['date'] as int);

  Map<String, Object?> toMap() => {
    'type': type.name,
    'amount': amount,
    'accountId': accountId,
    'toAccountId': toAccountId,
    'category': category,
    'note': note,
    'date': date.millisecondsSinceEpoch,
  };
}

class Goal {
  const Goal({this.id, required this.name, required this.target, this.saved = 0, this.deadline});

  final String? id;
  final String name;
  final int target;
  final int saved;
  final DateTime? deadline;

  /// Cents per week needed to reach the target by the deadline, if one is set and still ahead.
  int? weeklyNeeded(DateTime now) {
    final d = deadline;
    if (d == null || saved >= target || !d.isAfter(now)) return null;
    return ((target - saved) / max(1, (d.difference(now).inDays / 7).ceil())).ceil();
  }

  Goal.fromMap(this.id, Map<String, Object?> m)
    : name = m['name'] as String,
      target = m['target'] as int,
      saved = m['saved'] as int,
      deadline = m['deadline'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deadline'] as int);

  Map<String, Object?> toMap() => {
    'name': name,
    'target': target,
    'saved': saved,
    'deadline': deadline?.millisecondsSinceEpoch,
  };
}

extension Totals on Iterable<Account> {
  int get cash => where((a) => !a.isDebt).fold(0, (s, a) => s + a.balance);
  int get debt => where((a) => a.isDebt).fold(0, (s, a) => s + a.balance);
  int get availableCredit => fold(0, (s, a) => s + a.available);
}

/// Balance change per account id for [t]. Debt balances mean "amount owed",
/// so money leaving a debt account raises its balance and money entering lowers it.
Map<String, int> balanceDeltas(Tx t, Map<String, Account> accounts) {
  int out(Account a) => a.isDebt ? t.amount : -t.amount;
  final from = accounts[t.accountId], to = accounts[t.toAccountId];
  return {
    if (from != null) from.id!: t.type == TxType.income ? -out(from) : out(from),
    if (t.type == TxType.transfer && to != null) to.id!: -out(to),
  };
}

Map<String, int> spendByCategory(Iterable<Tx> txs) {
  final spend = <String, int>{};
  for (final t in txs) {
    if (t.type == TxType.expense) spend[t.category] = (spend[t.category] ?? 0) + t.amount;
  }
  return spend;
}

bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
bool sameDay(DateTime a, DateTime b) => sameMonth(a, b) && a.day == b.day;

/// "1,234.50" or "$12" -> cents. Null when it is not a number.
int? parseCents(String s) {
  final v = double.tryParse(s.replaceAll(RegExp(r'[\s,$]'), ''));
  return v == null || !v.isFinite ? null : (v * 100).round();
}
