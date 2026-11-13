import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

const _gap = SizedBox(height: 14);

Widget _label(String s) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Text(s, style: const TextStyle(color: dim, fontSize: 13)),
);

Widget _title(BuildContext context, String s) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: Text(s, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
);

Widget _accountChips(Iterable<Account> accounts, int? selected, ValueChanged<int> onPick) => Wrap(
  spacing: 8,
  children: [
    for (final a in accounts)
      ChoiceChip(
        avatar: CircleAvatar(backgroundColor: Color(a.color)),
        label: Text(a.name),
        selected: a.id == selected,
        showCheckmark: false,
        onSelected: (_) => onPick(a.id!),
      ),
  ],
);

Widget _dateChip(BuildContext context, DateTime? date, String empty, DateTime first, ValueChanged<DateTime> onPick) =>
    ActionChip(
      avatar: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(date == null ? empty : DateFormat('EEE d MMM y').format(date)),
      onPressed: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: date != null && date.isAfter(first) ? date : now, // a past deadline would assert
          firstDate: first,
          lastDate: DateTime(now.year + 10),
        );
        if (d != null) onPick(d);
      },
    );

// ---------------------------------------------------------------- transaction

class TxSheet extends StatefulWidget {
  const TxSheet({super.key, this.tx, this.type = TxType.expense, this.toAccountId});
  final Tx? tx;
  final TxType type;
  final int? toAccountId;

  @override
  State<TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends State<TxSheet> {
  late var type = widget.tx?.type ?? widget.type;
  late final amount = TextEditingController(text: centsText(widget.tx?.amount ?? 0));
  late final note = TextEditingController(text: widget.tx?.note);
  late int? to = widget.tx?.toAccountId ?? widget.toAccountId;
  // New entries start on the last used account; repayments start from a bank account.
  late int? from =
      widget.tx?.accountId ??
      (widget.toAccountId == null ? store.txs.firstOrNull?.accountId : null) ??
      store.accounts.where((a) => !a.isDebt).firstOrNull?.id;
  late var category = widget.tx?.type == TxType.expense ? widget.tx!.category : categories.keys.first;
  late var date = widget.tx?.date ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final cents = parseCents(amount.text);
    final transfer = type == TxType.transfer;
    final ok = cents != null && cents > 0 && from != null && (!transfer || (to != null && to != from));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TxType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TxType.expense, label: Text('Expense')),
            ButtonSegment(value: TxType.income, label: Text('Income')),
            ButtonSegment(value: TxType.transfer, label: Text('Transfer')),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() => type = s.first),
        ),
        _gap,
        AmountField(amount, 'Amount', autofocus: widget.tx == null, onChanged: (_) => setState(() {})),
        _label(switch (type) {
          TxType.expense => 'Paid with',
          TxType.income => 'Into',
          TxType.transfer => 'From',
        }),
        _accountChips(
          store.accounts.where((a) => a.type != AccountType.loan),
          from,
          (id) => setState(() => from = id),
        ),
        if (transfer) ...[
          _label('To (pick a debt to record a repayment)'),
          _accountChips(store.accounts.where((a) => a.id != from), to, (id) => setState(() => to = id)),
        ],
        if (type == TxType.expense) ...[
          _label('Category'),
          Wrap(
            spacing: 8,
            children: [
              for (final c in categories.entries)
                ChoiceChip(
                  avatar: Icon(c.value.$1, size: 16, color: c.value.$2),
                  label: Text(c.key),
                  selected: c.key == category,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => category = c.key),
                ),
            ],
          ),
        ],
        _gap,
        TextField(
          controller: note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        _gap,
        Row(
          children: [
            _dateChip(context, date, '', DateTime(2020), (d) => setState(() => date = d)),
            const Spacer(),
            if (widget.tx != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.pop(context);
                  store.deleteTx(widget.tx!);
                },
              ),
          ],
        ),
        _gap,
        FilledButton(
          onPressed: !ok
              ? null
              : () {
                  final t = Tx(
                    id: widget.tx?.id,
                    type: type,
                    amount: cents,
                    accountId: from!,
                    toAccountId: transfer ? to : null,
                    category: type == TxType.expense ? category : '',
                    note: note.text.trim(),
                    date: date,
                  );
                  Navigator.pop(context);
                  widget.tx == null ? store.addTx(t) : store.replaceTx(widget.tx!, t);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- account

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, this.account, this.debt = false});
  final Account? account;
  final bool debt; // new account opened from the Debts tab

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  late final name = TextEditingController(text: widget.account?.name);
  late final balance = TextEditingController(text: centsText(widget.account?.balance ?? 0));
  late final limit = TextEditingController(text: centsText(widget.account?.limit ?? 0));
  late var type = widget.account?.type ?? (widget.debt ? AccountType.credit : AccountType.bank);
  late var color = widget.account?.color ?? 0xFFB0B0B0;

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final bal = balance.text.trim().isEmpty ? 0 : parseCents(balance.text);
    final lim = limit.text.trim().isEmpty ? 0 : parseCents(limit.text);
    final ok = name.text.trim().isNotEmpty && bal != null && lim != null && lim >= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, a == null ? 'New account' : 'Edit ${a.name}'),
        if (a == null) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final p in presets.where((p) => p.isDebt == widget.debt))
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: Color(p.color)),
                  label: Text(p.name),
                  onPressed: () => setState(() {
                    name.text = p.name;
                    type = p.type;
                    color = p.color;
                  }),
                ),
            ],
          ),
          _gap,
        ],
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        _gap,
        SegmentedButton<AccountType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: AccountType.bank, label: Text('Bank')),
            ButtonSegment(value: AccountType.credit, label: Text('BNPL / credit')),
            ButtonSegment(value: AccountType.loan, label: Text('Loan')),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() => type = s.first),
        ),
        _gap,
        AmountField(
          balance,
          type == AccountType.bank ? 'Current balance' : 'Amount owed',
          autofocus: a != null,
          onChanged: (_) => setState(() {}),
        ),
        if (type != AccountType.bank) ...[
          _gap,
          AmountField(
            limit,
            type == AccountType.credit ? 'Credit limit' : 'Original loan amount',
            onChanged: (_) => setState(() {}),
          ),
        ],
        _gap,
        FilledButton(
          onPressed: !ok
              ? null
              : () {
                  Navigator.pop(context);
                  store.saveAccount(
                    Account(
                      id: a?.id,
                      name: name.text.trim(),
                      type: type,
                      balance: bal,
                      limit: type == AccountType.bank ? 0 : lim,
                      color: color,
                    ),
                  );
                },
          child: const Text('Save'),
        ),
        if (a != null)
          TextButton(
            onPressed: () async {
              if (!await confirm(context, 'Delete ${a.name} and all of its transactions?')) return;
              if (context.mounted) Navigator.pop(context);
              store.deleteAccount(a);
            },
            child: const Text('Delete account'),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------- goal

class GoalSheet extends StatefulWidget {
  const GoalSheet({super.key, this.goal});
  final Goal? goal;

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<GoalSheet> {
  late final name = TextEditingController(text: widget.goal?.name);
  late final target = TextEditingController(text: centsText(widget.goal?.target ?? 0));
  late final saved = TextEditingController(text: centsText(widget.goal?.saved ?? 0));
  late var deadline = widget.goal?.deadline;

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    final tgt = parseCents(target.text);
    final sav = saved.text.trim().isEmpty ? 0 : parseCents(saved.text);
    final ok = name.text.trim().isNotEmpty && tgt != null && tgt > 0 && sav != null && sav >= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, g == null ? 'New goal' : 'Edit goal'),
        TextField(
          controller: name,
          autofocus: g == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'What are you saving for?'),
        ),
        _gap,
        AmountField(target, 'Target', onChanged: (_) => setState(() {})),
        _gap,
        AmountField(saved, 'Saved so far', onChanged: (_) => setState(() {})),
        _gap,
        Row(
          children: [
            _dateChip(context, deadline, 'Add a deadline', DateTime.now(), (d) => setState(() => deadline = d)),
            if (deadline != null)
              IconButton(
                tooltip: 'Remove deadline',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => deadline = null),
              ),
          ],
        ),
        _gap,
        FilledButton(
          onPressed: !ok
              ? null
              : () {
                  Navigator.pop(context);
                  store.saveGoal(
                    Goal(id: g?.id, name: name.text.trim(), target: tgt, saved: sav, deadline: deadline),
                  );
                },
          child: const Text('Save'),
        ),
        if (g != null)
          TextButton(
            onPressed: () async {
              if (!await confirm(context, 'Delete the goal "${g.name}"?')) return;
              if (context.mounted) Navigator.pop(context);
              store.deleteGoal(g);
            },
            child: const Text('Delete goal'),
          ),
      ],
    );
  }
}
