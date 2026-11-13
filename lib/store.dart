import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

final store = Store();

/// Local SQLite database plus an in-memory copy the UI listens to.
class Store extends ChangeNotifier {
  late final Database _db;
  List<Account> accounts = [];
  List<Tx> txs = []; // newest first
  List<Goal> goals = [];
  Map<String, int> budgets = {}; // category -> monthly limit

  Future<void> open() async {
    _db = await openDatabase(
      'nobudget.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL, '
          'balance INTEGER NOT NULL, credit_limit INTEGER NOT NULL, color INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE txs(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, amount INTEGER NOT NULL, '
          'account_id INTEGER NOT NULL, to_account_id INTEGER, category TEXT NOT NULL, note TEXT NOT NULL, '
          'date INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE goals(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, target INTEGER NOT NULL, '
          'saved INTEGER NOT NULL, deadline INTEGER)',
        );
        await db.execute('CREATE TABLE budgets(category TEXT PRIMARY KEY, amount INTEGER NOT NULL)');
        for (final a in presets) {
          await db.insert('accounts', a.toMap());
        }
      },
    );
    await _reload();
  }

  Account? account(int? id) => accounts.where((a) => a.id == id).firstOrNull;

  // shortcut: every write re-reads all four tables, fine for a few thousand rows; page the txs query when it gets slow.
  Future<void> _reload() async {
    accounts = (await _db.query('accounts', orderBy: 'id')).map(Account.fromMap).toList();
    txs = (await _db.query('txs', orderBy: 'date DESC, id DESC')).map(Tx.fromMap).toList();
    goals = (await _db.query('goals', orderBy: 'id')).map(Goal.fromMap).toList();
    budgets = {for (final r in await _db.query('budgets')) r['category'] as String: r['amount'] as int};
    notifyListeners();
  }

  Future<void> _write(Future<void> Function(Transaction) f) async {
    try {
      await _db.transaction(f);
    } finally {
      await _reload();
    }
  }

  Future<void> _put(String table, Map<String, Object?> row) =>
      _write((d) => d.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace));

  Future<void> _applyBalances(Transaction d, Tx t, int sign) async {
    final deltas = balanceDeltas(t, {for (final a in accounts) a.id!: a});
    for (final e in deltas.entries) {
      await d.rawUpdate('UPDATE accounts SET balance = balance + ? WHERE id = ?', [sign * e.value, e.key]);
    }
  }

  Future<void> saveAccount(Account a) => _put('accounts', a.toMap());

  Future<void> deleteAccount(Account a) => _write((d) async {
    await d.delete('txs', where: 'account_id = ? OR to_account_id = ?', whereArgs: [a.id, a.id]);
    await d.delete('accounts', where: 'id = ?', whereArgs: [a.id]);
  });

  Future<void> addTx(Tx t) => _write((d) async {
    await d.insert('txs', t.toMap());
    await _applyBalances(d, t, 1);
  });

  Future<void> deleteTx(Tx t) {
    // Drop it from memory first: a swiped-away Dismissible must leave the tree on the next frame.
    txs = txs.where((x) => x.id != t.id).toList();
    notifyListeners();
    return _write((d) async {
      await d.delete('txs', where: 'id = ?', whereArgs: [t.id]);
      await _applyBalances(d, t, -1);
    });
  }

  Future<void> replaceTx(Tx old, Tx t) => _write((d) async {
    await d.delete('txs', where: 'id = ?', whereArgs: [old.id]);
    await _applyBalances(d, old, -1);
    await d.insert('txs', t.toMap());
    await _applyBalances(d, t, 1);
  });

  Future<void> saveGoal(Goal g) => _put('goals', g.toMap());

  Future<void> deleteGoal(Goal g) => _write((d) => d.delete('goals', where: 'id = ?', whereArgs: [g.id]));

  Future<void> setBudget(String category, int amount) => amount > 0
      ? _put('budgets', {'category': category, 'amount': amount})
      : _write((d) => d.delete('budgets', where: 'category = ?', whereArgs: [category]));
}
