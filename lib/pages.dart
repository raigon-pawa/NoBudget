import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'sheets.dart';
import 'store.dart';
import 'ui.dart';

const _pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 96); // bottom clears the FAB
const _empty = TextStyle(color: dim);

Widget _addButton(BuildContext context, String tooltip, Widget sheet) => IconButton(
  tooltip: tooltip,
  icon: const Icon(Icons.add_circle_outline),
  onPressed: () => showSheet(context, sheet),
);

// ------------------------------------------------------------------- overview

class Overview extends StatelessWidget {
  const Overview({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final banks = store.accounts.where((a) => !a.isDebt).toList();
      final month = store.txs.where((t) => sameMonth(t.date, DateTime.now()));
      int sum(TxType type) => month.where((t) => t.type == type).fold(0, (s, t) => s + t.amount);
      final spent = sum(TxType.expense), income = sum(TxType.income);
      final cash = store.accounts.cash, debt = store.accounts.debt;

      return ListView(
        padding: _pagePadding,
        children: [
          const SizedBox(height: 12),
          const Text('Net worth', style: TextStyle(color: dim)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              cash - debt,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 8,
            children: [
              Stat('Cash', cash),
              Stat('Debt', debt, onTap: () => tab.value = 3),
              Stat('Credit left', store.accounts.availableCredit, onTap: () => tab.value = 3),
            ],
          ),
          Header('Accounts', action: _addButton(context, 'Add account', const AccountSheet())),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                if (banks.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No accounts yet', style: _empty)),
                for (final a in banks)
                  ListTile(
                    leading: Avatar(Color(a.color), letter: a.name),
                    title: Text(a.name),
                    trailing: Text(
                      money(a.balance),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => showSheet(context, AccountSheet(account: a)),
                  ),
              ],
            ),
          ),
          const Header('This month'),
          Panel(
            onTap: () => tab.value = 1,
            child: Column(
              spacing: 12,
              children: [
                Row(
                  children: [
                    Expanded(child: _Figure('Spent', money(spent))),
                    Expanded(child: _Figure('Income', money(income), color: green)),
                    Expanded(child: _Figure('Left', money(income - spent))),
                  ],
                ),
                if (income > 0) Bar(spent / income),
              ],
            ),
          ),
          Header(
            'Recent',
            action: TextButton(onPressed: () => tab.value = 1, child: const Text('See all')),
          ),
          if (store.txs.isEmpty) const Text('Nothing yet. Tap + to add your first transaction.', style: _empty),
          for (final t in store.txs.take(5)) TxTile(t),
        ],
      );
    },
  );
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
        child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
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
      final spend = spendByCategory(txs);
      final total = spend.values.fold(0, (s, v) => s + v);
      final budgetTotal = store.budgets.values.fold(0, (s, v) => s + v);
      // Biggest spend first, then categories that only have a budget.
      final cats = {...spend.keys, ...store.budgets.keys}.toList()
        ..sort((a, b) => (spend[b] ?? 0).compareTo(spend[a] ?? 0));
      final slices = cats.where((c) => (spend[c] ?? 0) > 0).toList();
      final shown = filter == null
          ? txs
          : txs.where((t) => t.type == TxType.expense && t.category == filter).toList();

      return ListView(
        padding: _pagePadding,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(
                  DateFormat('MMMM y').format(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
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
          Header(
            filter ?? 'Transactions',
            action: filter == null
                ? null
                : TextButton(onPressed: () => setState(() => filter = null), child: const Text('Show all')),
          ),
          if (shown.isEmpty) const Text('No transactions this month.', style: _empty),
          for (final (i, t) in shown.indexed) ...[
            if (i == 0 || !sameDay(shown[i - 1].date, t.date))
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2, left: 4),
                child: Text(DateFormat('EEEE d MMM').format(t.date), style: const TextStyle(color: dim, fontSize: 12)),
              ),
            Dismissible(
              key: ValueKey(t.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: const Color(0xFF4A1C1C), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                store.deleteTx(t);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      persist: false,
                      content: const Text('Transaction deleted'),
                      action: SnackBarAction(label: 'Undo', onPressed: () => store.addTx(t)),
                    ),
                  );
              },
              child: TxTile(t),
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
                    style: TextStyle(color: over ? const Color(0xFFE08080) : dim, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (budget > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: Bar(spent / budget, color: over ? const Color(0xFFE08080) : color),
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
      canvas.drawArc(rect, 0, 2 * pi, false, paint..color = Colors.white10..strokeWidth = 14);
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
      return ListView(
        padding: _pagePadding,
        children: [
          Header('Goals', page: true, action: _addButton(context, 'Add goal', const GoalSheet())),
          if (store.goals.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Text(
                'No goals yet.\nTap + above to start saving for something.',
                textAlign: TextAlign.center,
                style: _empty,
              ),
            )
          else
            Text('${money(saved)} saved of ${money(target)}', style: _empty),
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
      final debts = store.accounts.where((a) => a.isDebt).toList();
      return ListView(
        padding: _pagePadding,
        children: [
          Header(
            'Debts & credit',
            page: true,
            action: _addButton(context, 'Add debt', const AccountSheet(debt: true)),
          ),
          Row(
            spacing: 8,
            children: [
              Stat('Total owed', store.accounts.debt),
              Stat('Available credit', store.accounts.availableCredit),
            ],
          ),
          if (debts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Text('No debts. Nice.', textAlign: TextAlign.center, style: _empty),
            ),
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
                            Text(money(a.balance), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                                ? '${money(a.available)} available of ${money(a.limit)}'
                                : '${((1 - a.balance / a.limit) * 100).clamp(0, 100).floor()}% paid off of ${money(a.limit)}',
                            style: _empty,
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () =>
                              showSheet(context, TxSheet(type: TxType.transfer, toAccountId: a.id)),
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
