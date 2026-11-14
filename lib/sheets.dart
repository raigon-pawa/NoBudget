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

Widget _accountChips(Iterable<Account> accounts, String? selected, ValueChanged<String> onPick) => Wrap(
  spacing: 8,
  runSpacing: 4,
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

Widget _currencyPicker(String label, String value, ValueChanged<String> onPick, {String? hint}) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 420,
      dropdownColor: const Color(0xFF1E1E1E), // the default is the page's black, which hides the menu's edge
      borderRadius: BorderRadius.circular(14),
      decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 2),
      items: [for (final c in currencies.keys) DropdownMenuItem(value: c, child: Text(currencyLabel(c)))],
      onChanged: (c) => onPick(c!),
    );

// ---------------------------------------------------------------- transaction

class TxSheet extends StatefulWidget {
  const TxSheet({super.key, this.tx, this.type = TxType.expense, this.toAccountId});
  final Tx? tx;
  final TxType type;
  final String? toAccountId;

  @override
  State<TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends State<TxSheet> {
  late var type = widget.tx?.type ?? widget.type;
  late final amount = TextEditingController(text: centsText(widget.tx?.amount ?? 0));
  late final received = TextEditingController(text: centsText(widget.tx?.toAmount ?? 0));
  late var typedReceived = widget.tx?.toAmount != null; // otherwise it follows the amount at the saved rate
  late final note = TextEditingController(text: widget.tx?.note);
  late String? to = widget.tx?.toAccountId ?? widget.toAccountId;
  // New entries start on the last used account; repayments start from a bank account.
  late String? from =
      widget.tx?.accountId ??
      (widget.toAccountId == null ? store.txs.firstOrNull?.accountId : null) ??
      store.accounts.where((a) => !a.isDebt).firstOrNull?.id;
  late var category = widget.tx?.type == TxType.expense ? widget.tx!.category : categories.keys.first;
  late var date = widget.tx?.date ?? DateTime.now();
  var repeat = Repeat.never;

  /// Applies [change], then works out again what a transfer between currencies delivers.
  void _update(VoidCallback change) => setState(() {
    change();
    final a = store.account(from), b = store.account(to);
    if (typedReceived || a == null || b == null) return;
    received.text = centsText(store.convert(parseCents(amount.text) ?? 0, a.currency, b.currency));
  });

  @override
  Widget build(BuildContext context) {
    final cents = parseCents(amount.text), got = parseCents(received.text);
    final transfer = type == TxType.transfer;
    final fromCurrency = store.account(from)?.currency, toCurrency = store.account(to)?.currency;
    final cross = transfer && fromCurrency != null && toCurrency != null && fromCurrency != toCurrency;
    final ok =
        cents != null &&
        cents > 0 &&
        from != null &&
        (!transfer || (to != null && to != from)) &&
        (!cross || (got != null && got > 0));

    final save = !ok
        ? null
        : () {
            final t = Tx(
              id: widget.tx?.id,
              type: type,
              amount: cents,
              accountId: from!,
              toAccountId: transfer ? to : null,
              toAmount: cross ? got : null,
              category: type == TxType.expense ? category : '',
              note: note.text.trim(),
              date: date,
            );
            Navigator.pop(context);
            widget.tx == null ? store.addTx(t) : store.replaceTx(widget.tx!, t);
            if (repeat != Repeat.never) store.addRecurring(t, repeat);
          };

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
        AmountField(
          amount,
          'Amount',
          currency: fromCurrency,
          autofocus: widget.tx == null,
          onChanged: (_) => _update(() {}),
          onSubmitted: (_) => save?.call(),
        ),
        _label(switch (type) {
          TxType.expense => 'Paid with',
          TxType.income => 'Into',
          TxType.transfer => 'From',
        }),
        _accountChips(store.accounts.where((a) => a.type != AccountType.loan), from, (id) => _update(() => from = id)),
        if (transfer) ...[
          _label('To (pick a debt to record a repayment)'),
          _accountChips(store.accounts.where((a) => a.id != from), to, (id) => _update(() => to = id)),
          if (cross) ...[
            _gap,
            AmountField(
              received,
              'Arrives as',
              currency: toCurrency,
              hint: 'Worked out from your saved rate. Change it to what actually arrived.',
              onChanged: (_) => setState(() => typedReceived = true),
              onSubmitted: (_) => save?.call(),
            ),
          ],
        ],
        if (type == TxType.expense) ...[
          _label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
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
          onSubmitted: (_) => save?.call(),
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        _gap,
        Row(
          children: [
            _dateChip(context, date, '', DateTime(2020), (d) => setState(() => date = d)),
            // Only a new entry can be set to repeat; stop one from the Repeating list.
            if (widget.tx == null) ...[
              const SizedBox(width: 8),
              PopupMenuButton<Repeat>(
                tooltip: 'Repeat: ${repeatLabel(repeat)}',
                onSelected: (r) => setState(() => repeat = r),
                itemBuilder: (_) => [
                  for (final r in Repeat.values) PopupMenuItem(value: r, child: Text(repeatLabel(r))),
                ],
                // The tooltip already names this control and its state for screen readers.
                child: ExcludeSemantics(
                  child: Chip(
                    avatar: Icon(Icons.repeat, size: 16, color: repeat == Repeat.never ? dim : Colors.white),
                    label: Text(repeat == Repeat.never ? 'Repeat' : repeatLabel(repeat)),
                  ),
                ),
              ),
            ],
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
        FilledButton(onPressed: save, child: const Text('Save')),
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
  late var currency = widget.account?.currency ?? store.home;

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final bal = balance.text.trim().isEmpty ? 0 : parseCents(balance.text);
    final lim = limit.text.trim().isEmpty ? 0 : parseCents(limit.text);
    final ok = name.text.trim().isNotEmpty && bal != null && lim != null && lim >= 0;

    final save = !ok
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
                currency: currency,
              ),
            );
          };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, a == null ? 'New account' : 'Edit ${a.name}'),
        if (a == null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
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
        _currencyPicker('Country and currency', currency, (c) => setState(() => currency = c)),
        _gap,
        AmountField(
          balance,
          type == AccountType.bank ? 'Current balance' : 'Amount owed',
          currency: currency,
          autofocus: a != null,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => save?.call(),
        ),
        if (type != AccountType.bank) ...[
          _gap,
          AmountField(
            limit,
            type == AccountType.credit ? 'Credit limit' : 'Original loan amount',
            currency: currency,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => save?.call(),
          ),
        ],
        _gap,
        FilledButton(onPressed: save, child: const Text('Save')),
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

    final save = !ok
        ? null
        : () {
            Navigator.pop(context);
            store.saveGoal(Goal(id: g?.id, name: name.text.trim(), target: tgt, saved: sav, deadline: deadline));
          };

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
        AmountField(target, 'Target', onChanged: (_) => setState(() {}), onSubmitted: (_) => save?.call()),
        _gap,
        AmountField(saved, 'Saved so far', onChanged: (_) => setState(() {}), onSubmitted: (_) => save?.call()),
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
        FilledButton(onPressed: save, child: const Text('Save')),
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

// ----------------------------------------------------------------- currencies

/// Home country, and what each other currency in use is worth.
class CurrencySheet extends StatelessWidget {
  const CurrencySheet({super.key});

  Future<void> _editRate(BuildContext context, String currency) async {
    final c = TextEditingController(text: _worth(currency));
    double? typed() => switch (double.tryParse(c.text.replaceAll(',', ''))) {
      final v? when v > 0 && v.isFinite => v,
      _ => null,
    };
    final v = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('1 $currency is worth'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => Navigator.pop(context, typed()),
          decoration: InputDecoration(suffixText: store.home),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, typed()), child: const Text('OK')),
        ],
      ),
    );
    if (v != null) store.setRate(currency, v);
  }

  static String _worth(String currency) => (store.rate(store.home) / store.rate(currency)).toStringAsPrecision(5);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final foreign = {for (final a in store.accounts) a.currency}.difference({store.home});
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context, 'Currencies'),
          _currencyPicker(
            'Home country',
            store.home,
            store.setHome,
            hint: 'Totals, budgets and goals are in this currency.',
          ),
          _label('Exchange rates'),
          if (foreign.isEmpty)
            const Text('Add an account in another currency and its rate shows up here.', style: TextStyle(color: dim)),
          for (final c in foreign)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text(currencyLabel(c)),
              subtitle: Text('1 $c = ${_worth(c)} ${store.home}', style: const TextStyle(color: dim)),
              trailing: const Icon(Icons.edit_outlined, size: 18, color: dim),
              onTap: () => _editRate(context, c),
            ),
          if (foreign.isNotEmpty)
            const Text(
              'Rates are not updated for you. Tap one to change it.',
              style: TextStyle(color: dim, fontSize: 12),
            ),
          _gap,
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      );
    },
  );
}
