import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final store = Store();

const _key = 'data', _revKey = 'syncedRev', _unsentKey = 'unsent', _noteKey = 'browserNoteClosed';
const _dailyKey = 'dailyRates', _dailyAtKey = 'dailyRatesFetched';

/// Published once a day by tools/rates/update-rates.py. GitHub serves it, so the app never contacts that machine.
const dailyRatesUrl = 'https://raw.githubusercontent.com/raigon-pawa/nobudget-rates/main/rates.json';

/// The signed-in user's copy in the cloud: one document holding `data` (the [Store.export] text) and `rev`
/// (an id that changes with every save). Firestore in the app, a map in the tests.
typedef Cloud = ({Future<Map<String, dynamic>?> Function() get, Future<void> Function(Map<String, dynamic>) set});

/// All data, held in memory and saved as one JSON document on this device. Signing in adds a copy in the
/// cloud, which is read when the app opens or comes back to the front and written a few seconds after
/// changes stop, to stay far inside Firebase's free daily limits.
// shortcut: everything is one document, which Firestore caps at 1 MiB (around 5,000 transactions), and when
// both this device and the cloud changed since they last met the user picks one whole; merge per record
// (balances worked out from transactions) if people edit offline on two devices.
class Store extends ChangeNotifier {
  List<Account> accounts = [];
  List<Tx> txs = []; // newest first
  List<Goal> goals = [];
  Map<String, int> budgets = {}; // category -> monthly limit
  List<Recurring> recurring = [];
  String home = 'AUD'; // the currency totals, budgets and goals are in
  Map<String, double> rates = {}; // units per US dollar, only for currencies whose rate the user changed
  Map<String, double> daily = {}; // units per US dollar from the daily rates, kept on this device only
  String? dailyDate; // the day those rates are from
  bool loaded = false;

  String? error; // why the data on this device could not be opened
  void Function(String message)? onError; // a sync that failed
  Future<bool> Function()? askKeepDevice; // both this device and the account changed: true keeps this device's
  Future<void> Function()? onCloudGone; // the account's cloud copy was deleted elsewhere: sign out

  late SharedPreferences _prefs;
  Cloud? _cloud;
  String? _uid;
  String? _rev; // the cloud's rev when this device last matched it
  bool _unsent = false; // changed since it last matched the cloud
  String? _matched; // the text it last matched, to skip saves that change nothing
  Timer? _timer;
  Future<void>? _pushing;
  DateTime? _pulledAt;
  bool _pulling = false;

  bool get syncing => _cloud != null;
  bool get unsent => _unsent;

  Future<void> open([DateTime? now]) async {
    _prefs = await SharedPreferences.getInstance();
    try {
      useDailyRates(_prefs.getString(_dailyKey));
    } catch (_) {} // a bad copy is replaced by the next download
    try {
      _start(_prefs.getString(_key), now ?? DateTime.now());
    } catch (e) {
      error = 'Could not read the data saved on this device: $e';
      notifyListeners();
    }
  }

  /// Downloads the daily rates, at most twice a day. Offline or refused, the last ones (or the built-in) stay.
  Future<void> refreshRates() async {
    final at = DateTime.fromMillisecondsSinceEpoch(_prefs.getInt(_dailyAtKey) ?? 0);
    if (DateTime.now().difference(at).inHours < 12) return;
    try {
      final r = await http.get(Uri.parse(dailyRatesUrl)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      useDailyRates(r.body);
      _prefs.setString(_dailyKey, r.body);
      _prefs.setInt(_dailyAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Takes the rates the app knows from a rates.json. Throws, changing nothing, if it is not one; a rate more
  /// than ten times off the built-in one is skipped, so a bad or tampered file cannot wreck the totals.
  @visibleForTesting
  void useDailyRates(String? body) {
    if (body == null) return;
    final data = jsonDecode(body) as Map<String, dynamic>;
    final date = data['date'] as String, all = data['rates'] as Map<String, dynamic>;
    daily = {
      for (final MapEntry(:key, :value) in currencies.entries)
        if (all[key] case final num v when v.isFinite && v > value.$2 / 10 && v < value.$2 * 10) key: v.toDouble(),
    };
    dailyDate = date;
    notifyListeners();
  }

  /// Whether the website's note that data lives only in this browser was closed.
  bool get browserNoteClosed => _prefs.getBool(_noteKey) ?? false;

  void closeBrowserNote() {
    _prefs.setBool(_noteKey, true);
    notifyListeners();
  }

  /// Starts keeping the signed-in user [uid]'s cloud copy in step with this device.
  Future<void> startSync(String uid) async {
    if (_uid == uid) return;
    final doc = FirebaseFirestore.instance.doc('users/$uid');
    _uid = uid;
    await sync((
      get: () async => (await doc.get(const GetOptions(source: Source.server))).data(),
      // After the first upload, update: it fails on a copy deleted elsewhere instead of recreating it.
      set: (m) => _rev == null ? doc.set(m) : doc.update(m),
    ));
  }

  @visibleForTesting
  Future<void> sync(Cloud cloud) async {
    _cloud = cloud;
    _rev = _prefs.getString(_revKey);
    // Never synced here: anything this device saved is still to be sent.
    _unsent = _prefs.getBool(_unsentKey) ?? _prefs.containsKey(_key);
    _matched = null;
    _pulledAt = null;
    if (!_prefs.containsKey(_key)) {
      // Nothing of its own on this device: show the account's data, not the starter accounts.
      loaded = false;
      notifyListeners();
    }
    await pull();
  }

  /// Stops syncing when the user signs out. The data stays on this device unless [forget].
  void stopSync({bool forget = false}) {
    _timer?.cancel();
    _cloud = null;
    _uid = null;
    _prefs.remove(_revKey);
    _prefs.remove(_unsentKey);
    if (forget) {
      _prefs.remove(_key);
      _start(null, DateTime.now());
    }
  }

  /// Reads the cloud copy, at most once a minute unless [force]: when the app opens or comes back to the front.
  Future<void> pull({bool force = false}) async {
    final cloud = _cloud, at = _pulledAt;
    if (cloud == null || _pulling || (!force && at != null && DateTime.now().difference(at).inMinutes < 1)) return;
    _pulling = true;
    try {
      // Our own save must land first, or it would look like a change made elsewhere.
      try {
        await _pushing;
      } catch (_) {}
      final m = await cloud.get();
      if (cloud != _cloud) return; // signed out meanwhile
      _pulledAt = DateTime.now();
      final raw = m?['data'] as String?, rev = m?['rev'] as String? ?? ''; // documents from before sync had no rev
      if (raw == null && _rev != null) {
        await _cloudGone(); // it matched a copy before, so the account was deleted elsewhere
      } else if (raw == null) {
        _setUnsent(true); // a new account starts from this device
        await flush();
      } else if (raw == export()) {
        _matchedCloud(rev, raw);
      } else if (rev == _rev || (_unsent && await askKeepDevice?.call() == true)) {
        // The cloud has not changed since this device last matched it, or the user keeps this device's.
        if (cloud != _cloud) return;
        _setUnsent(true);
        await flush();
      } else if (cloud == _cloud) {
        _start(raw, DateTime.now()); // parses first, so a bad document changes nothing
        _prefs.setString(_key, export());
        _matchedCloud(rev, raw);
      }
    } on FirebaseException catch (e) {
      if (e.code != 'unavailable') onError?.call('Could not sync: ${e.message}'); // offline: try again later
    } catch (e) {
      onError?.call('Could not read your synced data: $e');
    } finally {
      _pulling = false;
      if (!loaded) {
        loaded = true; // offline on a new device: start fresh, the account's data is asked for again later
        notifyListeners();
      }
    }
  }

  /// Sends unsent changes to the cloud now: a few seconds after the last change, or when the app goes away.
  Future<void> flush() async {
    _timer?.cancel();
    final cloud = _cloud, text = export();
    // One save at a time: offline, the newest changes follow when the waiting one lands, instead of a write each.
    if (cloud == null || !_unsent || _pushing != null) return;
    if (text == _matched) return _setUnsent(false);
    final rev = newId();
    final push = _pushing = cloud.set({'data': text, 'rev': rev});
    try {
      await push; // offline, Firestore keeps it and sends it once the connection is back
      _pushing = null;
      if (cloud != _cloud) return;
      _matchedCloud(rev, text);
      if (_unsent && !(_timer?.isActive ?? false)) await flush(); // changed meanwhile, and nothing else will send it
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return _cloudGone();
      onError?.call('Could not sync: ${e.message}'); // stays unsent, so it is tried again
    } finally {
      if (_pushing == push) _pushing = null;
    }
  }

  /// The cloud copy is gone (the account was deleted on another device): stop, and never upload it again.
  Future<void> _cloudGone() async {
    stopSync();
    onError?.call('Your synced copy was deleted, so this device signed out. Your budget is still here.');
    await onCloudGone?.call();
  }

  void _matchedCloud(String rev, String text) {
    _rev = rev;
    _matched = text;
    _prefs.setString(_revKey, rev);
    if (export() == text) _setUnsent(false); // not if it changed again meanwhile
  }

  void _setUnsent(bool v) {
    _unsent = v;
    _prefs.setBool(_unsentKey, v);
  }

  void _start(String? raw, DateTime now) {
    if (raw == null) {
      accounts = [for (final (i, a) in presets.indexed) Account.fromMap(newId(i), a.toMap())];
      txs = [];
      goals = [];
      budgets = {};
      recurring = [];
      home = 'AUD';
      rates = {};
    } else {
      _load(raw);
    }
    _sort();
    _addDue(now);
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
    final h = data['home'] as String? ?? 'AUD';
    final x = {for (final e in (data['rates'] as Map? ?? {}).entries) e.key as String: (e.value as num).toDouble()};
    if (![h, ...x.keys, ...a.map((y) => y.currency)].every(currencies.containsKey) || x.values.any((v) => !(v > 0))) {
      throw const FormatException('Unknown currency or bad rate');
    }
    home = h;
    rates = x;
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
    _prefs.setString(_key, export());
    if (_cloud != null) {
      _setUnsent(true);
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 10), flush);
    }
  }

  /// Everything as one piece of text: what is saved on the device, and what a backup is.
  String export() => jsonEncode({
    'accounts': {for (final a in accounts) a.id: a.toMap()},
    'txs': {for (final t in txs) t.id: t.toMap()},
    'goals': {for (final g in goals) g.id: g.toMap()},
    'budgets': budgets,
    'recurring': {for (final r in recurring) r.id: r.toMap()},
    'home': home,
    'rates': rates,
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

  double rate(String currency) => rates[currency] ?? daily[currency] ?? currencies[currency]!.$2;

  /// [cents] of [from] in [to], or in the home currency.
  int convert(int cents, String from, [String? to]) =>
      from == (to ?? home) ? cents : (cents * rate(to ?? home) / rate(from)).round();

  /// Accounts with their amounts turned into the home currency, so they can be added up.
  List<Account> get homeAccounts => [
    for (final a in accounts)
      Account.fromMap(a.id, {
        ...a.toMap(),
        'balance': convert(a.balance, a.currency),
        'limit': convert(a.limit, a.currency),
      }),
  ];

  /// [txs] with their amounts turned into the home currency, so they can be added up.
  Iterable<Tx> inHome(Iterable<Tx> txs) => txs.map(
    (t) => Tx.fromMap(t.id, {...t.toMap(), 'amount': convert(t.amount, account(t.accountId)?.currency ?? home)}),
  );

  /// Sets what one unit of [currency] is worth in the home currency.
  void setRate(String currency, double worth) {
    rates[currency] = rate(home) / worth;
    _changed();
  }

  /// Goes back to the daily rate for [currency].
  void clearRate(String currency) {
    rates.remove(currency);
    _changed();
  }

  // shortcut: budgets and goals keep their numbers when the home currency changes (500 stays 500);
  // convert them here if people turn out to switch after setting them up.
  void setHome(String currency) {
    home = currency;
    _changed();
  }

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

  /// Replaces a repeating transaction with [r], adding at once anything it makes due.
  void saveRecurring(Recurring r) {
    final i = recurring.indexWhere((x) => x.id == r.id);
    if (i >= 0) recurring[i] = r;
    _addDue(DateTime.now());
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
