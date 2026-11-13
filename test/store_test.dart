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
}
