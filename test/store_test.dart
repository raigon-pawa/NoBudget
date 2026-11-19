import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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

  test('editing a repeating transaction changes what it adds from then on', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    await s.open();
    final bank = s.accounts.first.id!;
    final gym = Tx(type: TxType.expense, amount: 2000, accountId: bank, category: 'Fun', date: today);
    s.addTx(gym);
    s.addRecurring(gym, Repeat.weekly);

    // Pricier and monthly, starting in ten days: nothing is added yet, and past entries keep their amount.
    final start = DateTime(today.year, today.month, today.day + 10);
    final id = s.recurring.single.id;
    Tx pricier(DateTime date) =>
        Tx.fromMap(null, {...gym.toMap(), 'amount': 3000, 'date': date.millisecondsSinceEpoch});
    s.saveRecurring(Recurring(id: id, tx: pricier(start), every: Repeat.monthly));
    expect(s.recurring.single.next, start);
    expect(s.txs.single.amount, 2000);

    // Moved to today: added at once.
    s.saveRecurring(Recurring(id: id, tx: pricier(today), every: Repeat.monthly));
    expect(s.txs.map((t) => t.amount), unorderedEquals([2000, 3000]));
    expect(s.account(bank)!.balance, -5000);
    expect(s.recurring.single.next, occurrence(today, Repeat.monthly, 1));
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

  test('daily rates are used unless the user set their own, and bad ones are refused', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.open();
    expect(() => s.useDailyRates('<html>'), throwsA(anything));
    expect(() => s.useDailyRates('{"date": "2026-11-15"}'), throwsA(anything));
    expect(s.daily, isEmpty);

    // EUR is fine, GBP is a hundred times off (a broken or tampered file), XYZ is unknown to the app.
    s.useDailyRates('{"date": "2026-11-15", "rates": {"USD": 1, "EUR": 0.9, "GBP": 75.6, "XYZ": 3, "AUD": "x"}}');
    expect(s.daily, {'USD': 1.0, 'EUR': 0.9});
    expect(s.dailyDate, '2026-11-15');
    expect(s.rate('EUR'), 0.9);
    expect(s.rate('GBP'), currencies['GBP']!.$2);

    s.setRate('EUR', 2); // 1 EUR = 2 AUD
    expect(s.convert(100, 'EUR'), 200);
    s.clearRate('EUR');
    expect(s.rate('EUR'), 0.9);
    expect(s.export(), isNot(contains('0.9'))); // daily rates stay on the device, out of the synced data
  });

  group('sync', () {
    // A stand-in for the user's Firestore document that counts what would be billed.
    late Map<String, dynamic>? doc;
    var reads = 0, writes = 0;
    Cloud cloud() => (
      get: () async {
        reads++;
        return doc;
      },
      set: (m) async {
        writes++;
        doc = m;
      },
    );
    setUp(() {
      doc = null;
      reads = writes = 0;
    });

    Future<String> otherDevice() async {
      SharedPreferences.setMockInitialValues({});
      final o = Store();
      await o.open();
      o.setBudget('Fun', 999);
      return o.export();
    }

    test('reset empties the device and the synced copy, keeps the currency, and can be undone', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.open();
      s.setHome('USD');
      s.addTx(Tx(type: TxType.income, amount: 100, accountId: s.accounts.first.id!, date: DateTime(2026, 11, 1)));
      s.saveGoal(Goal(name: 'Trip', target: 50000));
      s.setBudget('Fun', 1000);
      await s.sync(cloud());
      final before = s.export();
      s.reset();
      expect(<Iterable<Object>>[s.accounts, s.txs, s.goals, s.budgets.keys, s.recurring].every((x) => x.isEmpty), isTrue);
      expect(s.home, 'USD');
      await s.flush();
      expect(doc!['data'], s.export());
      final again = Store();
      await again.open();
      expect(again.accounts, isEmpty); // not the starter accounts of a new install
      s.restore(before);
      expect(s.export(), before);
    });

    test('signed out uses no cloud; signing in uploads to a new account once', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.open();
      s.setBudget('Fun', 1000);
      await s.sync(cloud());
      expect((reads, writes), (1, 1));
      expect(doc!['data'], s.export());
      expect(s.unsent, isFalse);
    });

    test('changes go up as one write, and saves that change nothing are skipped', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.open();
      await s.sync(cloud());
      writes = 0;
      final bank = s.accounts.first.id!;
      for (var i = 0; i < 5; i++) {
        s.addTx(Tx(type: TxType.income, amount: 100, accountId: bank, date: DateTime(2026, 11, 1)));
      }
      expect(writes, 0);
      await s.flush();
      expect(writes, 1);
      // A save still waiting (offline) holds back the next one; the newest changes follow it as one write.
      final waiting = Completer<void>();
      final slow = (get: cloud().get, set: (Map<String, dynamic> m) async {
        await waiting.future;
        writes++;
        doc = m;
      });
      await s.sync(slow);
      s.setBudget('A', 1);
      final first = s.flush();
      s.setBudget('B', 1);
      await s.flush();
      s.setBudget('C', 1);
      await s.flush();
      waiting.complete();
      await first;
      expect(writes, 3); // 1 before, then the waiting save and one with B and C
      expect(doc!['data'], s.export());
      s.setBudget('Fun', 0); // no budget before either
      await s.flush();
      await s.flush();
      expect(writes, 3);
      s.stopSync();
    });

    test("a new device takes the account's data without asking, even from before sync had revs", () async {
      doc = {'data': await otherDevice()}; // no rev
      SharedPreferences.setMockInitialValues({});
      final s = Store()..askKeepDevice = () => fail('should not ask');
      await s.open();
      await s.sync(cloud());
      expect(s.budgets, {'Fun': 999});
      expect(writes, 0);

      // Its own later change is sent, again without asking: the account has not changed since.
      s.setBudget('Rent', 5);
      await s.pull(force: true);
      expect(writes, 1);
      expect(doc!['data'], s.export());
      s.stopSync();
    });

    test('an unsent change survives a restart and is sent without asking', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.open();
      await s.sync(cloud());
      s.setBudget('Fun', 1); // app closed before the delayed write
      s.stopSync(); // stand-in for the process ending, minus forgetting the sync state:
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('syncedRev', doc!['rev'] as String);
      await prefs.setBool('unsent', true);

      final again = Store()..askKeepDevice = () => fail('should not ask');
      await again.open();
      await again.sync(cloud());
      expect(doc!['data'], again.export());
      expect(again.budgets, {'Fun': 1});
    });

    test('when both changed the user picks one', () async {
      for (final keep in [true, false]) {
        doc = {'data': await otherDevice(), 'rev': 'elsewhere'};
        final theirs = doc!['data'];
        SharedPreferences.setMockInitialValues({});
        final s = Store()..askKeepDevice = () async => keep;
        await s.open();
        s.setBudget('Mine', 1);
        await s.sync(cloud());
        expect(s.budgets, keep ? {'Mine': 1} : {'Fun': 999});
        expect(doc!['data'], keep ? s.export() : theirs);
        expect(s.unsent, isFalse);
        s.stopSync();
      }
    });

    test('a copy deleted on another device is never uploaded again', () async {
      SharedPreferences.setMockInitialValues({});
      var gone = 0;
      final s = Store()..onCloudGone = () async => gone++;
      await s.open();
      await s.sync(cloud());
      expect(doc, isNotNull);
      doc = null; // Delete account on another device
      s.setBudget('Fun', 7);
      await s.pull(force: true);
      expect((doc, writes, gone, s.syncing), (null, 1, 1, false));
      expect(s.budgets, {'Fun': 7}); // the budget stays on this device
    });

    test('a save refused because the copy is gone signs out instead of recreating it', () async {
      SharedPreferences.setMockInitialValues({});
      var gone = 0;
      final s = Store()..onCloudGone = () async => gone++;
      await s.open();
      await s.sync(cloud());
      // Firestore refuses to update a document that was deleted meanwhile.
      final refused = (
        get: cloud().get,
        set: (Map<String, dynamic> m) async => throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      );
      await s.sync(refused); // still matches the copy it reads
      s.setBudget('Fun', 7);
      await s.flush();
      expect((gone, s.syncing), (1, false));
      expect(s.budgets, {'Fun': 7});
    });

    test('pulls at most once a minute; signing out keeps or forgets the data', () async {
      SharedPreferences.setMockInitialValues({});
      final s = Store();
      await s.open();
      s.setBudget('Fun', 3);
      await s.sync(cloud());
      await s.pull();
      await s.pull();
      expect(reads, 1);

      s.stopSync();
      expect(s.budgets, {'Fun': 3});
      final reopened = Store();
      await reopened.open();
      expect(reopened.budgets, {'Fun': 3});
      reopened.stopSync(forget: true);
      expect(reopened.budgets, isEmpty);
      final fresh = Store();
      await fresh.open();
      expect(fresh.budgets, isEmpty);
    });
  });
}
