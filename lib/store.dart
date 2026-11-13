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
  List<Recurring> recurring = [];
  bool loaded = false;

  late SharedPreferences _prefs;

  Future<void> open([DateTime? now]) async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_key);
    if (raw == null) {
      accounts = [for (final (i, a) in presets.indexed) Account.fromMap(newId(i), a.toMap())];
    } else {
      _load(raw);
    }
    _sort();
    _addDue(now ?? DateTime.now());
    loaded = true;
    notifyListeners();
  }

  /// Reads a saved document. Everything is parsed before anything is replaced, so bad input changes nothing.
  void _load(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    // Sections added in later versions are missing from older documents.
    List<T> read<T>(String name, T Function(String id, Map<String, Object?> m) make) => [
      for (final e in (data[name] as Map<String, dynamic>? ?? {}).entries) make(e.key, e.value),
    ];
    final a = read('accounts', Account.fromMap), t = read('txs', Tx.fromMap), g = read('goals', Goal.fromMap);
    final r = read('recurring', Recurring.fromMap);
    final b = Map<String, int>.from(data['budgets'] as Map? ?? {});
    accounts = a;
    txs = t;
    goals = g;
    recurring = r;
    budgets = b;
  }

  /// Adds every repeating transaction that has come due since the app last ran.
  // shortcut: only checked at start, so a tab left open past midnight catches up on its next load;
  // also run it when the app resumes if that ever matters.
  void _addDue(DateTime now) {
    var added = 0;
    for (final (i, first) in recurring.indexed) {
      var r = first;
      while (!r.next.isAfter(now)) {
        final t = Tx.fromMap(newId(added++), {...r.tx.toMap(), 'date': r.next.millisecondsSinceEpoch});
        txs.add(t);
        _applyBalances(t, 1);
        r = Recurring(id: r.id, tx: r.tx, every: r.every, done: r.done + 1);
      }
      recurring[i] = r;
    }
    if (added > 0) _changed();
  }

  // Same-day entries keep the newest on top: ids are creation timestamps.
  void _sort() => txs.sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.id!.compareTo(a.id!));

  void _changed() {
    _sort();
    notifyListeners();
    // shortcut: the whole dataset is rewritten on every change, and a browser caps it near 5 MB (roughly
    // 25,000 transactions); move to a real database when saving gets slow or the cap gets close.
    _prefs.setString(_key, export());
  }

  /// Everything as one piece of text: what is saved on the device, and what a backup is.
  String export() => jsonEncode({
    'accounts': {for (final a in accounts) a.id: a.toMap()},
    'txs': {for (final t in txs) t.id: t.toMap()},
    'goals': {for (final g in goals) g.id: g.toMap()},
    'budgets': budgets,
    'recurring': {for (final r in recurring) r.id: r.toMap()},
  });

  /// Replaces all data with a backup made by [export]. Throws, changing nothing, if [backup] is not one.
  void restore(String backup, [DateTime? now]) {
    if (jsonDecode(backup) case {'accounts': Map _, 'txs': Map _}) {
      _load(backup);
      _addDue(now ?? DateTime.now());
      _changed();
    } else {
      throw const FormatException('Not a NoBudget backup');
    }
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
    recurring.removeWhere((r) => r.tx.accountId == a.id || r.tx.toAccountId == a.id);
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

  /// Repeats [t], which has just been added as the first occurrence.
  void addRecurring(Tx t, Repeat every) {
    recurring.add(Recurring(id: newId(), tx: t, every: every, done: 1));
    _changed();
  }

  void deleteRecurring(Recurring r) {
    recurring.removeWhere((x) => x.id == r.id);
    _changed();
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
