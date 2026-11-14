import 'package:flutter_test/flutter_test.dart';
import 'package:nobudget/models.dart';
import 'package:nobudget/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('transactions move balances, and everything survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.open();
    expect(s.accounts.map((a) => a.name), presets.map((a) => a.name));

    final bank = s.accounts.first.id!, klarna = s.accounts.firstWhere((a) => a.name == 'Klarna').id!;
    final day = DateTime(2026, 11, 1);
    s.addTx(Tx(type: TxType.income, amount: 100000, accountId: bank, date: day));
    s.addTx(Tx(type: TxType.expense, amount: 5000, accountId: klarna, category: 'Shopping', date: day));
    s.addTx(Tx(type: TxType.transfer, amount: 2000, accountId: bank, toAccountId: klarna, date: day));
    expect(s.account(bank)!.balance, 98000);
    expect(s.account(klarna)!.balance, 3000); // owed
    expect(s.txs.first.type, TxType.transfer); // same day: newest first

    // Editing the repayment down to $10 moves both accounts by the difference.
    final repay = s.txs.first;
    s.replaceTx(repay, Tx(type: TxType.transfer, amount: 1000, accountId: bank, toAccountId: klarna, date: day));
    expect(s.account(bank)!.balance, 99000);
    expect(s.account(klarna)!.balance, 4000);
    expect(s.txs.first.id, repay.id);

    s.deleteTx(s.txs.first);
    expect(s.account(bank)!.balance, 100000);
    expect(s.account(klarna)!.balance, 5000);

    s.saveGoal(Goal(name: 'Trip', target: 50000, deadline: DateTime(2027)));
    s.setBudget('Shopping', 20000);

    final again = Store();
    await again.open();
    expect(again.account(bank)!.balance, 100000);
    expect(again.txs.length, 2);
    expect(again.goals.single.deadline, DateTime(2027));
    expect(again.budgets, {'Shopping': 20000});

    again.deleteAccount(again.account(klarna)!);
    expect(again.txs.single.type, TxType.income);
  });

  test('repeating transactions catch up when the app opens', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.open(DateTime(2026, 11, 1));
    final bank = s.accounts.first.id!;
    final rent = Tx(
      type: TxType.expense,
      amount: 10000,
      accountId: bank,
      category: 'Rent',
      date: DateTime(2026, 11, 1),
    );
    s.addTx(rent);
    s.addRecurring(rent, Repeat.weekly);
    expect(s.account(bank)!.balance, -10000);

    // Opened again 15 days later: the 8th and 15th were missed, the 22nd is not due yet.
    final later = Store();
    await later.open(DateTime(2026, 11, 16));
    expect(later.txs.map((t) => t.date.day), [15, 8, 1]);
    expect(later.account(bank)!.balance, -30000);
    expect(later.recurring.single.next, DateTime(2026, 11, 22));

    // Nothing is added twice.
    final again = Store();
    await again.open(DateTime(2026, 11, 16));
    expect(again.txs.length, 3);

    again.deleteRecurring(again.recurring.single);
    final stopped = Store();
    await stopped.open(DateTime(2027));
    expect(stopped.txs.length, 3);
  });

  test('a backup restores into an empty app, and junk is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.open();
    s.addTx(Tx(type: TxType.income, amount: 5000, accountId: s.accounts.first.id!, date: DateTime(2026, 11, 1)));
    s.setBudget('Fun', 1000);
    final backup = s.export();

    SharedPreferences.setMockInitialValues({});
    final other = Store();
    await other.open();
    for (final junk in ['hello', '{}', '{"accounts": {"1": {"name": 5}}, "txs": {}}']) {
      expect(() => other.restore(junk), throwsA(anything));
      expect(other.accounts.length, presets.length);
      expect(other.txs, isEmpty);
    }
    other.restore(backup);
    expect(other.export(), backup);
    expect(other.accounts.first.balance, 5000);
  });

  test('other currencies: transfers between them, totals in the home currency, rates', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.open();
    final aud = s.accounts.first.id!;
    s.saveAccount(const Account(name: 'Wise USD', type: AccountType.bank, color: 0, currency: 'USD'));
    final usd = s.accounts.last.id!;
    final day = DateTime(2026, 11, 1);
    s.addTx(Tx(type: TxType.income, amount: 100000, accountId: aud, date: day));
    // $300 leaves in AUD, 200 arrives in USD.
    s.addTx(Tx(type: TxType.transfer, amount: 30000, accountId: aud, toAccountId: usd, toAmount: 20000, date: day));
    s.addTx(Tx(type: TxType.expense, amount: 5000, accountId: usd, category: 'Fun', date: day));
    expect(s.account(aud)!.balance, 70000);
    expect(s.account(usd)!.balance, 15000);

    s.setRate('USD', 1.5); // 1 USD = 1.50 AUD
    expect(s.convert(10000, 'USD'), 15000);
    expect(s.convert(15000, 'AUD', 'USD'), 10000);
    expect(s.homeAccounts.cash, 70000 + 22500);
    expect(spendByCategory(s.inHome(s.txs)), {'Fun': 7500});

    // Undoing the transfer puts each side back in its own currency.
    s.deleteTx(s.txs.firstWhere((t) => t.type == TxType.transfer));
    expect(s.account(aud)!.balance, 100000);
    expect(s.account(usd)!.balance, -5000);

    s.setHome('USD');
    final again = Store();
    await again.open();
    expect(again.home, 'USD');
    expect(again.account(usd)!.currency, 'USD');
    expect(again.homeAccounts.cash, 66667 - 5000); // the changed rate was saved too

    final backup = again.export();
    expect(() => again.restore(backup.replaceFirst('"currency":"USD"', '"currency":"XXX"')), throwsFormatException);
    expect(() => again.restore(backup.replaceFirst('"home":"USD"', '"home":"XXX"')), throwsFormatException);
    expect(again.export(), backup);
  });
}
