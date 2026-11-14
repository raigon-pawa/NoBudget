import 'dart:math';

// All money is integer cents, in the currency of the account it sits in.

/// Currency code -> (country, units per US dollar on 13 Nov 2026). The rates are only starting values:
/// the app never goes online, so the user corrects them by hand.
// shortcut: every currency is kept to two decimal places, which is finer than yen or dong need and too
// coarse for the three-decimal dinars (none listed); store a per-currency scale if one of those is added.
const currencies = <String, (String, double)>{
  'AUD': ('Australia', 1.4683),
  'BDT': ('Bangladesh', 124.77),
  'BRL': ('Brazil', 5.6102),
  'CAD': ('Canada', 1.4256),
  'CNY': ('China', 6.6851),
  'DKK': ('Denmark', 6.7476),
  'EUR': ('Eurozone', 0.90349),
  'FJD': ('Fiji', 2.2634),
  'HKD': ('Hong Kong', 7.8450),
  'INR': ('India', 94.086),
  'IDR': ('Indonesia', 18251),
  'JPY': ('Japan', 159.80),
  'MYR': ('Malaysia', 4.0788),
  'MXN': ('Mexico', 18.620),
  'NPR': ('Nepal', 150.54),
  'NZD': ('New Zealand', 1.8027),
  'NOK': ('Norway', 9.5607),
  'PKR': ('Pakistan', 276.62),
  'PHP': ('Philippines', 63.786),
  'SAR': ('Saudi Arabia', 3.75),
  'SGD': ('Singapore', 1.2863),
  'ZAR': ('South Africa', 16.736),
  'KRW': ('South Korea', 1334.2),
  'LKR': ('Sri Lanka', 332.43),
  'SEK': ('Sweden', 10.018),
  'CHF': ('Switzerland', 0.83437),
  'THB': ('Thailand', 33.855),
  'TRY': ('Turkey', 50.312),
  'AED': ('United Arab Emirates', 3.6725),
  'GBP': ('United Kingdom', 0.75515),
  'USD': ('United States', 1),
  'VND': ('Vietnam', 25691),
};

/// Document id that sorts by creation time, so lists keep the order things were added in.
String newId([int offset = 0]) => '${DateTime.now().microsecondsSinceEpoch + offset}';

enum AccountType { bank, credit, loan }

enum TxType { expense, income, transfer }

enum Repeat { never, weekly, fortnightly, monthly }

class Account {
  const Account({
    this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.limit = 0,
    required this.color,
    this.currency = 'AUD',
  });

  final String? id;
  final String name;
  final AccountType type;
  final int balance; // bank: money held. credit/loan: amount owed.
  final int limit; // credit: credit limit. loan: original amount. bank: unused.
  final int color;
  final String currency; // a key of [currencies]

  bool get isDebt => type != AccountType.bank;
  int get available => type == AccountType.credit ? max(0, limit - balance) : 0;

  Account.fromMap(this.id, Map<String, Object?> m)
    : name = m['name'] as String,
      type = AccountType.values.byName(m['type'] as String),
      balance = m['balance'] as int,
      limit = m['limit'] as int,
      color = m['color'] as int,
      currency = m['currency'] as String? ?? 'AUD'; // accounts saved before currencies existed

  Map<String, Object?> toMap() => {
    'name': name,
    'type': type.name,
    'balance': balance,
    'limit': limit,
    'color': color,
    'currency': currency,
  };
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
    this.toAmount,
    this.category = '',
    this.note = '',
    required this.date,
  });

  final String? id;
  final TxType type;
  final int amount; // always positive, in the currency of [accountId]
  final String accountId;
  final String? toAccountId; // transfers only
  final int? toAmount; // transfers between currencies only: what arrived, in the receiving account's currency
  final String category; // expenses only
  final String note;
  final DateTime date;

  Tx.fromMap(this.id, Map<String, Object?> m)
    : type = TxType.values.byName(m['type'] as String),
      amount = m['amount'] as int,
      accountId = m['accountId'] as String,
      toAccountId = m['toAccountId'] as String?,
      toAmount = m['toAmount'] as int?,
      category = m['category'] as String,
      note = m['note'] as String,
      date = DateTime.fromMillisecondsSinceEpoch(m['date'] as int);

  Map<String, Object?> toMap() => {
    'type': type.name,
    'amount': amount,
    'accountId': accountId,
    'toAccountId': toAccountId,
    'toAmount': toAmount,
    'category': category,
    'note': note,
    'date': date.millisecondsSinceEpoch,
  };
}

/// A transaction that adds itself again on a schedule.
class Recurring {
  const Recurring({this.id, required this.tx, required this.every, this.done = 0});

  final String? id;
  final Tx tx; // the template; its date is the first occurrence
  final Repeat every;
  final int done; // occurrences already added as transactions

  DateTime get next => occurrence(tx.date, every, done);

  Recurring.fromMap(this.id, Map<String, Object?> m)
    : tx = Tx.fromMap(null, m),
      every = Repeat.values.byName(m['every'] as String),
      done = m['done'] as int;

  Map<String, Object?> toMap() => {...tx.toMap(), 'every': every.name, 'done': done};
}

/// The date of occurrence [n] (0 is [first] itself). Counting from the first date, instead of stepping
/// from the previous one, keeps a monthly 31st on the last day of short months without drifting to the 28th.
DateTime occurrence(DateTime first, Repeat every, int n) {
  if (every != Repeat.monthly) {
    return DateTime(first.year, first.month, first.day + n * (every == Repeat.weekly ? 7 : 14));
  }
  final lastDay = DateTime(first.year, first.month + n + 1, 0).day;
  return DateTime(first.year, first.month + n, min(first.day, lastDay));
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
  int out(Account a, int amount) => a.isDebt ? amount : -amount;
  final from = accounts[t.accountId], to = accounts[t.toAccountId];
  return {
    if (from != null) from.id!: t.type == TxType.income ? -out(from, t.amount) : out(from, t.amount),
    if (t.type == TxType.transfer && to != null) to.id!: -out(to, t.toAmount ?? t.amount),
  };
}

Map<String, int> spendByCategory(Iterable<Tx> txs) {
  final spend = <String, int>{};
  for (final t in txs) {
    if (t.type == TxType.expense) spend[t.category] = (spend[t.category] ?? 0) + t.amount;
  }
  return spend;
}

/// Net worth at the close of each of the last [days] days, oldest first and ending today at [current],
/// worked backwards through the transactions. Transfers only move money around, so they change nothing.
List<int> netWorthTrend(int current, Iterable<Tx> txs, DateTime now, {int days = 30}) {
  final trend = List.filled(days, current);
  int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
  for (final t in txs) {
    final change = switch (t.type) {
      TxType.expense => -t.amount,
      TxType.income => t.amount,
      TxType.transfer => 0,
    };
    // Every day before the transaction closed without it. Future-dated ones count as today.
    final index = min(days - 1, days - 1 - (dayNumber(now) - dayNumber(t.date)));
    for (var i = 0; i < index; i++) {
      trend[i] -= change;
    }
  }
  return trend;
}

bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;
bool sameDay(DateTime a, DateTime b) => sameMonth(a, b) && a.day == b.day;

/// "1,234.50" or "$12" -> cents. Null when it is not a number.
int? parseCents(String s) {
  final v = double.tryParse(s.replaceAll(RegExp(r'[\s,$]'), ''));
  return v == null || !v.isFinite ? null : (v * 100).round();
}
