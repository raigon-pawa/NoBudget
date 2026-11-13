import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final store = Store();

const _key = 'data';

/// All data, held in memory and saved on this device as one JSON document
/// (app storage on Android, localStorage in a browser).
class Store extends ChangeNotifier {
  List<Account> accounts = [];
  List<Tx> txs = []; // newest first
  List<Goal> goals = [];
  Map<String, int> budgets = {}; // category -> monthly limit
  bool loaded = false;

  late SharedPreferences _prefs;

  Future<void> open() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_key);
    if (raw == null) {
      accounts = [for (final (i, a) in presets.indexed) Account.fromMap(newId(i), a.toMap())];
    } else {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      List<T> read<T>(String name, T Function(String id, Map<String, Object?> m) make) => [
        for (final e in (data[name] as Map<String, dynamic>).entries) make(e.key, e.value),
      ];
      accounts = read('accounts', Account.fromMap);
      txs = read('txs', Tx.fromMap);
      goals = read('goals', Goal.fromMap);
      budgets = (data['budgets'] as Map<String, dynamic>).cast();
    }
    loaded = true;
    notifyListeners();
  }

  void _changed() {
    // Same-day entries keep the newest on top: ids are creation timestamps.
    txs.sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.id!.compareTo(a.id!));
    notifyListeners();
    // shortcut: the whole dataset is rewritten on every change, and a browser caps it near 5 MB (roughly
    // 25,000 transactions); move to a real database when saving gets slow or the cap gets close.
    _prefs.setString(
      _key,
      jsonEncode({
        'accounts': {for (final a in accounts) a.id: a.toMap()},
        'txs': {for (final t in txs) t.id: t.toMap()},
        'goals': {for (final g in goals) g.id: g.toMap()},
        'budgets': budgets,
      }),
    );
  }

  Account? account(String? id) => accounts.where((a) => a.id == id).firstOrNull;

  /// Applies the balance changes of [t], or undoes them when [sign] is -1.
  void _applyBalances(Tx t, int sign) {
    final deltas = balanceDeltas(t, {for (final a in accounts) a.id!: a});
    accounts = [
      for (final a in accounts)
        Account.fromMap(a.id, {...a.toMap(), 'balance': a.balance + sign * (deltas[a.id] ?? 0)}),
    ];
  }

  void saveAccount(Account a) {
    final i = accounts.indexWhere((x) => x.id == a.id);
    i < 0 ? accounts.add(Account.fromMap(newId(), a.toMap())) : accounts[i] = a;
    _changed();
  }

  void deleteAccount(Account a) {
    accounts.removeWhere((x) => x.id == a.id);
    txs.removeWhere((t) => t.accountId == a.id || t.toAccountId == a.id);
    _changed();
  }

  void addTx(Tx t) {
    txs.add(Tx.fromMap(t.id ?? newId(), t.toMap()));
    _applyBalances(t, 1);
    _changed();
  }

  void deleteTx(Tx t) {
    txs.removeWhere((x) => x.id == t.id);
    _applyBalances(t, -1);
    _changed();
  }

  void replaceTx(Tx old, Tx t) {
    txs.removeWhere((x) => x.id == old.id);
    _applyBalances(old, -1);
    addTx(Tx.fromMap(old.id, t.toMap()));
  }

  void saveGoal(Goal g) {
    final i = goals.indexWhere((x) => x.id == g.id);
    i < 0 ? goals.add(Goal.fromMap(newId(), g.toMap())) : goals[i] = g;
    _changed();
  }

  void deleteGoal(Goal g) {
    goals.removeWhere((x) => x.id == g.id);
    _changed();
  }

  void setBudget(String category, int amount) {
    amount > 0 ? budgets[category] = amount : budgets.remove(category);
    _changed();
  }
}
