import 'package:flutter_test/flutter_test.dart';
import 'package:nobudget/models.dart';

void main() {
  const bank = Account(id: '1', name: 'CommBank', type: AccountType.bank, balance: 100000, color: 0);
  const up = Account(id: '2', name: 'Up', type: AccountType.bank, balance: 5000, color: 0);
  const afterpay = Account(
    id: '3',
    name: 'Afterpay',
    type: AccountType.credit,
    balance: 30000,
    limit: 200000,
    color: 0,
  );
  const loan = Account(id: '4', name: 'Latitude', type: AccountType.loan, balance: 500000, limit: 800000, color: 0);
  final accounts = {
    for (final a in [bank, up, afterpay, loan]) a.id!: a,
  };
  final day = DateTime(2026, 11, 13);

  Tx tx(TxType type, int amount, String from, {String? to, String category = ''}) =>
      Tx(type: type, amount: amount, accountId: from, toAccountId: to, category: category, date: day);

  test('totals', () {
    expect(accounts.values.cash, 105000);
    expect(accounts.values.debt, 530000);
    expect(accounts.values.availableCredit, 170000); // loans give no available credit
    expect(const Account(name: 'x', type: AccountType.credit, balance: 500, limit: 100, color: 0).available, 0);
  });

  test('balance deltas', () {
    expect(balanceDeltas(tx(TxType.expense, 2500, '1'), accounts), {'1': -2500});
    expect(balanceDeltas(tx(TxType.expense, 2500, '3'), accounts), {'3': 2500}, reason: 'BNPL purchase raises owed');
    expect(balanceDeltas(tx(TxType.income, 2500, '1'), accounts), {'1': 2500});
    expect(balanceDeltas(tx(TxType.income, 2500, '3'), accounts), {'3': -2500}, reason: 'refund lowers owed');
    expect(balanceDeltas(tx(TxType.transfer, 2500, '1', to: '2'), accounts), {'1': -2500, '2': 2500});
    expect(balanceDeltas(tx(TxType.transfer, 2500, '1', to: '4'), accounts), {
      '1': -2500,
      '4': -2500,
    }, reason: 'repayment');
    expect(balanceDeltas(tx(TxType.transfer, 2500, '1', to: '99'), accounts), {'1': -2500}, reason: 'deleted account');
  });

  test('spend by category ignores income and transfers', () {
    final spend = spendByCategory([
      tx(TxType.expense, 1000, '1', category: 'Groceries'),
      tx(TxType.expense, 250, '3', category: 'Groceries'),
      tx(TxType.expense, 400, '1', category: 'Fun'),
      tx(TxType.income, 9999, '1'),
      tx(TxType.transfer, 9999, '1', to: '3'),
    ]);
    expect(spend, {'Groceries': 1250, 'Fun': 400});
  });

  test('parseCents', () {
    expect(parseCents('19.99'), 1999);
    expect(parseCents(r'$1,234.5'), 123450);
    expect(parseCents('-20'), -2000);
    expect(parseCents(''), null);
    expect(parseCents('abc'), null);
  });

  test('weekly amount needed for a goal', () {
    Goal goal({int saved = 0, DateTime? deadline}) =>
        Goal(name: 'Trip', target: 100000, saved: saved, deadline: deadline);
    expect(goal(deadline: DateTime(2026, 12, 11)).weeklyNeeded(day), 25000); // 4 weeks
    expect(goal(deadline: DateTime(2026, 11, 14)).weeklyNeeded(day), 100000); // under a week
    expect(goal().weeklyNeeded(day), null);
    expect(goal(deadline: DateTime(2026, 1, 1)).weeklyNeeded(day), null);
    expect(goal(saved: 100000, deadline: DateTime(2026, 12, 11)).weeklyNeeded(day), null);
  });

  test('net worth trend walks back through income and expenses', () {
    final now = DateTime(2026, 11, 14, 9);
    Tx tx(TxType type, int amount, DateTime date) => Tx(type: type, amount: amount, accountId: 'a', date: date);
    final trend = netWorthTrend(
      1000,
      [
        tx(TxType.expense, 100, DateTime(2026, 11, 14, 8)), // today
        tx(TxType.income, 500, DateTime(2026, 11, 13)), // yesterday
        tx(TxType.transfer, 300, DateTime(2026, 11, 13)),
        tx(TxType.expense, 50, DateTime(2026, 12, 1)), // future-dated: already in the balance
        tx(TxType.income, 200, DateTime(2025, 1, 1)), // before the window
      ],
      now,
      days: 3,
    );
    expect(trend, [650, 1150, 1000]);
  });
}
