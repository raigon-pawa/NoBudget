import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

final store = Store();

typedef _Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

/// The signed-in user's data, mirrored live from Cloud Firestore (users/{uid}/...).
/// Firestore keeps an on-device copy, so reads and writes also work offline and sync later.
class Store extends ChangeNotifier {
  List<Account> accounts = [];
  List<Tx> txs = []; // newest first
  List<Goal> goals = [];
  Map<String, int> budgets = {}; // category -> monthly limit
  bool loaded = false;

  /// Told about writes the server rejected (they are rolled back on screen).
  void Function(String message)? onError;

  List<StreamSubscription<void>> _subs = [];

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      FirebaseFirestore.instance.collection('users/${FirebaseAuth.instance.currentUser!.uid}/$name');

  /// Follows sign-in and sign-out: each user only ever sees their own collections.
  void open() => FirebaseAuth.instance.authStateChanges().listen((user) {
    for (final s in _subs) {
      s.cancel();
    }
    accounts = [];
    txs = [];
    goals = [];
    budgets = {};
    loaded = false;
    _subs = user == null
        ? []
        : [
            // Ids are creation timestamps, so the default id order is the order things were added.
            _listen(_col('accounts'), (docs) {
              accounts = [for (final d in docs) Account.fromMap(d.id, d.data())];
              loaded = true;
            }),
            // shortcut: every transaction is loaded (one billed read each per app start), fine for a few
            // thousand; query by month when the free 50,000 reads a day gets tight.
            _listen(_col('txs').orderBy('date', descending: true), (docs) {
              txs = [for (final d in docs) Tx.fromMap(d.id, d.data())];
            }),
            _listen(_col('goals'), (docs) {
              goals = [for (final d in docs) Goal.fromMap(d.id, d.data())];
            }),
            _listen(_col('budgets'), (docs) {
              budgets = {for (final d in docs) d.id: d.data()['amount'] as int};
            }),
          ];
    notifyListeners();
  });

  StreamSubscription<void> _listen(Query<Map<String, dynamic>> query, void Function(_Docs) apply) =>
      query.snapshots().listen((s) {
        apply(s.docs);
        notifyListeners();
      }, onError: _failed);

  void _failed(Object e) {
    debugPrint('Firestore: $e');
    if (FirebaseAuth.instance.currentUser != null) onError?.call('Could not sync: $e');
  }

  Account? account(String? id) => accounts.where((a) => a.id == id).firstOrNull;

  // Writes show up through the listeners straight away; the future only completes once the server has them.
  Future<void> _commit(WriteBatch b) => b.commit().catchError(_failed);

  WriteBatch get _batch => FirebaseFirestore.instance.batch();

  Map<String, int> _deltas(Tx t, int sign) =>
      balanceDeltas(t, {for (final a in accounts) a.id!: a}).map((id, v) => MapEntry(id, sign * v));

  void _applyBalances(WriteBatch b, Map<String, int> deltas) {
    for (final e in deltas.entries) {
      if (e.value != 0) b.update(_col('accounts').doc(e.key), {'balance': FieldValue.increment(e.value)});
    }
  }

  /// The starting accounts for a newly registered user.
  Future<void> seedPresets() {
    final b = _batch;
    for (final (i, a) in presets.indexed) {
      b.set(_col('accounts').doc(newId(i)), a.toMap());
    }
    return _commit(b);
  }

  Future<void> saveAccount(Account a) => _commit(_batch..set(_col('accounts').doc(a.id ?? newId()), a.toMap()));

  Future<void> deleteAccount(Account a) {
    final b = _batch..delete(_col('accounts').doc(a.id));
    for (final t in txs.where((t) => t.accountId == a.id || t.toAccountId == a.id)) {
      b.delete(_col('txs').doc(t.id));
    }
    return _commit(b);
  }

  Future<void> addTx(Tx t) {
    final b = _batch..set(_col('txs').doc(t.id ?? newId()), t.toMap());
    _applyBalances(b, _deltas(t, 1));
    return _commit(b);
  }

  Future<void> deleteTx(Tx t) {
    // Drop it from memory first: a swiped-away Dismissible must leave the tree on the next frame.
    txs = txs.where((x) => x.id != t.id).toList();
    notifyListeners();
    final b = _batch..delete(_col('txs').doc(t.id));
    _applyBalances(b, _deltas(t, -1));
    return _commit(b);
  }

  Future<void> replaceTx(Tx old, Tx t) {
    final deltas = _deltas(old, -1);
    _deltas(t, 1).forEach((id, v) => deltas[id] = (deltas[id] ?? 0) + v);
    final b = _batch..set(_col('txs').doc(old.id), t.toMap());
    _applyBalances(b, deltas);
    return _commit(b);
  }

  Future<void> saveGoal(Goal g) => _commit(_batch..set(_col('goals').doc(g.id ?? newId()), g.toMap()));

  Future<void> deleteGoal(Goal g) => _commit(_batch..delete(_col('goals').doc(g.id)));

  Future<void> setBudget(String category, int amount) {
    final doc = _col('budgets').doc(category);
    return _commit(amount > 0 ? (_batch..set(doc, {'amount': amount})) : (_batch..delete(doc)));
  }
}
