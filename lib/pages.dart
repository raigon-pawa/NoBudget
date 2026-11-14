import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'sheets.dart';
import 'store.dart';
import 'ui.dart';

const _empty = TextStyle(color: dim);

Widget _addButton(BuildContext context, String tooltip, Widget sheet) => IconButton(
  tooltip: tooltip,
  icon: const Icon(Icons.add_circle_outline),
  onPressed: () => showSheet(context, sheet),
);

/// Cards in reading order: one column on a phone, dealt alternately into two on a wide screen.
Widget _cardPage(BuildContext context, List<Widget> top, List<Widget> cards) {
  final wide = isWide(context);
  return PageColumns(
    top: top,
    left: [
      for (final (i, c) in cards.indexed)
        if (!wide || i.isEven) c,
    ],
    right: [
      for (final (i, c) in cards.indexed)
        if (wide && i.isOdd) c,
    ],
  );
}

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(width: _snackWidth(context), content: Text(message)));

/// On a wide screen a message is a small box, not a bar across the whole window.
double? _snackWidth(BuildContext context) => isWide(context) ? 420 : null;

// shortcut: a backup travels through the clipboard, which needs no file-access dependency but tops out
// around 1 MB on Android (several thousand transactions); save and open a file instead when that gets close.
Future<void> _backup(BuildContext context) async {
  await Clipboard.setData(ClipboardData(text: store.export()));
  if (context.mounted) _say(context, 'Backup copied. Paste it somewhere safe, like a note to yourself.');
}

Future<void> _currencies(BuildContext context) => showSheet(context, const CurrencySheet());

Future<void> _signOut(BuildContext context) async {
  final email = FirebaseAuth.instance.currentUser?.email;
  if (await confirm(context, 'Sign out of $email?', action: 'Sign out')) await FirebaseAuth.instance.signOut();
}

Future<void> _restore(BuildContext context) async {
  final c = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore a backup'),
      content: SizedBox(
        width: 440, // long backup text would otherwise stretch the dialog across the screen
        child: TextField(
          controller: c,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste the backup text here',
            helperText: 'This replaces everything in the app now.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Restore')),
      ],
    ),
  );
  if (text == null || !context.mounted) return;
  try {
    store.restore(text);
    _say(context, 'Backup restored.');
  } catch (_) {
    _say(context, 'That is not a NoBudget backup. Nothing was changed.');
  }
}

// ------------------------------------------------------------------- overview

class Overview extends StatelessWidget {
  const Overview({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final banks = store.accounts.where((a) => !a.isDebt).toList();
      // Totals are in the home currency; each account and transaction shows its own.
      final all = store.homeAccounts;
      final month = store.inHome(store.txs.where((t) => sameMonth(t.date, DateTime.now())));
      int sum(TxType type) => month.where((t) => t.type == type).fold(0, (s, t) => s + t.amount);
      final spent = sum(TxType.expense), income = sum(TxType.income);
      final cash = all.cash, debt = all.debt;

      // shortcut: past days are valued at today's rates, so the line shows saving and spending, not
      // currency swings; keep a rate history if those ever need to show.
      final trend = netWorthTrend(cash - debt, store.inHome(store.txs), DateTime.now());
      final change = trend.last - trend.first;
      // A chart is only worth showing once something happened before today.
      final charted = trend.take(trend.length - 1).any((v) => v != trend.first);

      return PageColumns(
        top: [
          Stack(
            fit: StackFit.passthrough, // the card keeps the full width
            children: [
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Net worth', style: TextStyle(color: dim)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AnimatedMoney(
                              cash - debt,
                              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1),
                            ),
                          ),
                          if (change != 0)
                            Row(
                              spacing: 6,
                              children: [
                                Icon(
                                  change >= 0 ? Icons.trending_up : Icons.trending_down,
                                  size: 18,
                                  color: change >= 0 ? green : red,
                                ),
                                Text(
                                  '${change >= 0 ? '+' : '-'}${money(change.abs())} in the last 30 days',
                                  style: const TextStyle(color: dim, fontSize: 13),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (charted)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, t, _) =>
                            CustomPaint(size: const Size(double.infinity, 64), painter: _Spark(trend, t)),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: PopupMenuButton<Future<void> Function(BuildContext)>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz, color: dim),
                  onSelected: (action) => action(context),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _currencies, child: Text('Currencies')),
                    PopupMenuItem(value: _backup, child: Text('Copy a backup')),
                    PopupMenuItem(value: _restore, child: Text('Restore a backup')),
                    PopupMenuItem(value: _signOut, child: Text('Sign out')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              Stat('Cash', cash),
              Stat('Debt', debt, onTap: () => tab.value = 3),
              Stat('Credit left', all.availableCredit, onTap: () => tab.value = 3),
            ],
          ),
        ],
        left: [
          Header('Accounts', action: _addButton(context, 'Add account', const AccountSheet())),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                if (banks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No accounts yet', style: _empty),
                  ),
                // Where the cash sits, one segment per account.
                if (cash > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 8,
                        child: Row(
                          spacing: 2,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final a in banks)
                              if (a.balance > 0)
                                Expanded(
                                  flex: store.convert(a.balance, a.currency),
                                  child: ColoredBox(color: Color(a.color)),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final a in banks)
                  ListTile(
                    leading: Avatar(Color(a.color), letter: a.name),
                    title: Text(a.name),
                    trailing: Text(
                      money(a.balance, a.currency),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => showSheet(context, AccountSheet(account: a)),
                  ),
              ],
            ),
          ),
        ],
        right: [
          const Header('This month'),
          Panel(
            onTap: () => tab.value = 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Row(
                  children: [
                    Expanded(child: _Figure('Spent', money(spent))),
                    Expanded(child: _Figure('Income', money(income), color: green)),
                    Expanded(child: _Figure('Left', money(income - spent), color: income < spent ? red : null)),
                  ],
                ),
                if (income > 0) ...[
                  Bar(spent / income, color: spent > income ? red : Colors.white),
                  Text(
                    '${(spent / income * 100).round()}% of income spent',
                    style: const TextStyle(color: dim, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Header(
            'Recent',
            action: TextButton(onPressed: () => tab.value = 1, child: const Text('See all')),
          ),
          if (store.txs.isEmpty)
            const Empty(Icons.receipt_long_outlined, 'Nothing yet.\nAdd your first transaction to get started.')
          else
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(children: [for (final t in store.txs.take(6)) TxTile(t)]),
            ),
        ],
      );
    },
  );
}

/// Line chart with a soft fill, drawn in from the left as [t] goes 0..1.
class _Spark extends CustomPainter {
  _Spark(this.values, this.t);
  final List<int> values;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(min), span = max(1, values.reduce(max) - lo);
    Offset at(int i) =>
        Offset(size.width * i / (values.length - 1), 4 + (size.height - 12) * (1 - (values[i] - lo) / span));
    final line = Path()..moveTo(0, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    canvas.drawPath(
      Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white24, Colors.transparent],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Spark old) => old.t != t || !listEquals(old.values, values);
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: dim, fontSize: 12)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------------- spending

class Spending extends StatefulWidget {
  const Spending({super.key});

  @override
  State<Spending> createState() => _SpendingState();
}

class _SpendingState extends State<Spending> {
  var month = DateTime(DateTime.now().year, DateTime.now().month);
  String? filter; // category picked on the donut or its legend
  final search = TextEditingController();

  void _shift(int by) => setState(() {
    month = DateTime(month.year, month.month + by);
    filter = null;
  });

  Future<void> _editBudget(String category) async {
    final v = await askAmount(
      context,
      '$category budget',
      initial: store.budgets[category] ?? 0,
      hint: 'Per month. Leave empty to remove.',
    );
    if (v != null) store.setBudget(category, v);
  }

  Future<void> _pickBudget() async {
    final c = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Budget for'),
        children: [
          for (final c in categories.keys)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c)),
        ],
      ),
    );
    if (c != null) _editBudget(c);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final txs = store.txs.where((t) => sameMonth(t.date, month)).toList();
      final spend = spendByCategory(store.inHome(txs));
      final total = spend.values.fold(0, (s, v) => s + v);
      final budgetTotal = store.budgets.values.fold(0, (s, v) => s + v);
      // Biggest spend first, then categories that only have a budget.
      final cats = {...spend.keys, ...store.budgets.keys}.toList()
        ..sort((a, b) => (spend[b] ?? 0).compareTo(spend[a] ?? 0));
      final slices = cats.where((c) => (spend[c] ?? 0) > 0).toList();
      // A search looks through every month: note, category, account names and amount.
      final query = search.text.trim().toLowerCase();
      bool matches(Tx t) => [
        t.note,
        t.category,
        t.type.name,
        store.account(t.accountId)?.name,
        store.account(t.toAccountId)?.name,
        store.account(t.accountId)?.currency,
        (t.amount / 100).toStringAsFixed(2),
      ].any((s) => s != null && s.toLowerCase().contains(query));
      final shown = query.isNotEmpty
          ? store.txs.where(matches).toList()
          : filter == null
          ? txs
          : txs.where((t) => t.type == TxType.expense && t.category == filter).toList();

      return PageColumns(
        top: [
          Row(
            children: [
              IconButton(tooltip: 'Previous month', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(
                  DateFormat('MMMM y').format(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(tooltip: 'Next month', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
        ],
        left: [
          Center(
            child: GestureDetector(
              onTapUp: (d) {
                // Angle of the tap, clockwise from 12 o'clock, picks the slice.
                final o = d.localPosition - const Offset(_donutSize / 2, _donutSize / 2);
                var angle = (atan2(o.dy, o.dx) + pi / 2) % (2 * pi) / (2 * pi) * total;
                String? hit;
                for (final c in slices) {
                  if (angle < spend[c]!) {
                    hit = c;
                    break;
                  }
                  angle -= spend[c]!;
                }
                setState(() => filter = hit == filter ? null : hit);
              },
              child: TweenAnimationBuilder<double>(
                key: ValueKey(month),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => CustomPaint(
                  painter: _Donut([for (final c in slices) (cat(c).$2, spend[c]!)], slices.indexOf(filter ?? ''), t),
                  child: child,
                ),
                child: SizedBox.square(
                  dimension: _donutSize,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(filter ?? 'Spent', style: const TextStyle(color: dim)),
                      AnimatedMoney(
                        filter == null ? total : spend[filter] ?? 0,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      if (filter == null && budgetTotal > 0)
                        Text('of ${money(budgetTotal)}', style: const TextStyle(color: dim, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in cats) _categoryRow(c, spend[c] ?? 0, store.budgets[c] ?? 0),
                TextButton.icon(
                  onPressed: _pickBudget,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Set a budget'),
                ),
              ],
            ),
          ),
          if (store.recurring.isNotEmpty) ...[
            const Header('Repeating'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final r in store.recurring)
                    TxTile(
                      r.tx,
                      detail: '${repeatLabel(r.every)} · next ${DateFormat('d MMM').format(r.next)}',
                      onTap: () async {
                        if (await confirm(
                          context,
                          'Stop repeating this? Transactions it already added stay.',
                          action: 'Stop',
                        )) {
                          store.deleteRecurring(r);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
        right: [
          Header(
            query.isNotEmpty ? '${shown.length} found' : filter ?? 'Transactions',
            action: filter == null || query.isNotEmpty
                ? null
                : TextButton(onPressed: () => setState(() => filter = null), child: const Text('Show all')),
          ),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search all transactions',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(search.clear),
                    ),
            ),
          ),
          if (shown.isEmpty)
            Empty(
              Icons.receipt_long_outlined,
              query.isNotEmpty ? 'Nothing matches "${search.text.trim()}".' : 'No transactions this month.',
            ),
          for (final (i, t) in shown.indexed) ...[
            if (i == 0 || !sameDay(shown[i - 1].date, t.date))
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2, left: 4, right: 4),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: dim, fontSize: 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(DateFormat(query.isEmpty ? 'EEEE d MMM' : 'EEEE d MMM y').format(t.date))),
                      // What the day cost.
                      if (spendByCategory(store.inHome(shown.where((x) => sameDay(x.date, t.date)))).values
                              .fold(0, (s, v) => s + v)
                          case final spentThatDay && > 0)
                        Text('-${money(spentThatDay)}'),
                    ],
                  ),
                ),
              ),
            Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: const Color(0xFF4A1C1C), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.delete_outline, semanticLabel: 'Delete'),
              ),
              onDismissed: (_) {
                store.deleteTx(t);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      width: _snackWidth(context),
                      persist: false,
                      content: const Text('Transaction deleted'),
                      action: SnackBarAction(label: 'Undo', onPressed: () => store.addTx(t)),
                    ),
                  );
              },
              child: TxTile(t, showDate: false),
            ),
          ],
        ],
      );
    },
  );

  Widget _categoryRow(String c, int spent, int budget) {
    final (icon, color) = cat(c);
    final over = budget > 0 && spent > budget;
    return InkWell(
      onTap: () => setState(() => filter = filter == c ? null : c),
      child: Container(
        color: filter == c ? Colors.white10 : null,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(c)),
                Text(money(spent), style: const TextStyle(fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () => _editBudget(c),
                  child: Text(
                    budget > 0 ? 'of ${money(budget)}' : 'Budget',
                    style: TextStyle(color: over ? red : dim, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (budget > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: Bar(spent / budget, color: over ? red : color),
              ),
          ],
        ),
      ),
    );
  }
}

const _donutSize = 190.0;

class _Donut extends CustomPainter {
  _Donut(this.parts, this.selected, this.t);
  final List<(Color, int)> parts;
  final int selected; // -1 for none
  final double t; // 0..1 sweep-in animation

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 12);
    final paint = Paint()..style = PaintingStyle.stroke;
    final total = parts.fold(0, (s, p) => s + p.$2);
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        2 * pi,
        false,
        paint
          ..color = Colors.white10
          ..strokeWidth = 14,
      );
      return;
    }
    var start = -pi / 2;
    for (final (i, (color, value)) in parts.indexed) {
      final sweep = value / total * 2 * pi * t;
      paint
        ..color = selected < 0 || selected == i ? color : color.withValues(alpha: .25)
        ..strokeWidth = selected == i ? 22 : 14;
      // Small gap between slices, unless there is only one.
      final gap = parts.length > 1 ? .02 : 0.0;
      canvas.drawArc(rect, start + gap, max(sweep - 2 * gap, .01), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => true;
}

// ---------------------------------------------------------------------- goals

class Goals extends StatelessWidget {
  const Goals({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final saved = store.goals.fold(0, (s, g) => s + g.saved);
      final target = store.goals.fold(0, (s, g) => s + g.target);
      return _cardPage(
        context,
        [
          Header('Goals', page: true, action: _addButton(context, 'Add goal', const GoalSheet())),
          if (store.goals.isEmpty)
            Empty(
              Icons.flag_outlined,
              'No goals yet.\nStart saving for something.',
              action: FilledButton.tonal(
                onPressed: () => showSheet(context, const GoalSheet()),
                child: const Text('New goal'),
              ),
            )
          else ...[
            Text('${money(saved)} saved of ${money(target)}', style: _empty),
            const SizedBox(height: 8),
            Bar(saved / target, color: saved >= target ? green : Colors.white),
          ],
        ],
        [
          for (final g in store.goals)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Panel(
                onTap: () => showSheet(context, GoalSheet(goal: g)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(g.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                        g.saved >= g.target
                            ? const Icon(Icons.check_circle, color: green)
                            : Text(
                                '${(g.saved / g.target * 100).floor()}%',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ],
                    ),
                    Bar(g.saved / g.target, color: g.saved >= g.target ? green : Colors.white),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${money(g.saved)} of ${money(g.target)}${switch (g.weeklyNeeded(DateTime.now())) {
                              null => '',
                              final w => '\n${money(w)} a week until ${DateFormat('d MMM y').format(g.deadline!)}',
                            }}',
                            style: _empty,
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final v = await askAmount(
                              context,
                              'Add to ${g.name}',
                              hint: 'Use a negative amount to take money out.',
                            );
                            if (v == null || v == 0) return;
                            store.saveGoal(
                              Goal(
                                id: g.id,
                                name: g.name,
                                target: g.target,
                                saved: max(0, g.saved + v),
                                deadline: g.deadline,
                              ),
                            );
                          },
                          child: const Text('Add funds'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------- debts

class Debts extends StatelessWidget {
  const Debts({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final debts = store.accounts.where((a) => a.isDebt).toList(), all = store.homeAccounts;
      return _cardPage(
        context,
        [
          Header('Debts & credit', page: true, action: _addButton(context, 'Add debt', const AccountSheet(debt: true))),
          Row(spacing: 8, children: [Stat('Total owed', all.debt), Stat('Available credit', all.availableCredit)]),
          if (debts.isEmpty) const Empty(Icons.celebration_outlined, 'No debts. Nice.'),
        ],
        [
          for (final a in debts)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Panel(
                onTap: () => showSheet(context, AccountSheet(account: a)),
                child: Column(
                  spacing: 10,
                  children: [
                    Row(
                      children: [
                        Avatar(Color(a.color), letter: a.name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              Text(a.type == AccountType.credit ? 'BNPL / credit' : 'Loan', style: _empty),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              money(a.balance, a.currency),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            const Text('owed', style: _empty),
                          ],
                        ),
                      ],
                    ),
                    // Credit shows how much of the limit is used; loans show how much is paid off.
                    if (a.limit > 0)
                      Bar(
                        a.type == AccountType.credit ? a.balance / a.limit : 1 - a.balance / a.limit,
                        color: Color(a.color),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.limit <= 0
                                ? 'Tap to set ${a.type == AccountType.credit ? 'the credit limit' : 'the loan amount'}'
                                : a.type == AccountType.credit
                                ? '${money(a.available, a.currency)} available of ${money(a.limit, a.currency)}'
                                : '${((1 - a.balance / a.limit) * 100).clamp(0, 100).floor()}% paid off of ${money(a.limit, a.currency)}',
                            style: _empty,
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => showSheet(context, TxSheet(type: TxType.transfer, toAccountId: a.id)),
                          child: const Text('Repay'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
