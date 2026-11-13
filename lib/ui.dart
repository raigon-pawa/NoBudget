import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'sheets.dart';
import 'store.dart';

final tab = ValueNotifier(0);
final messenger = GlobalKey<ScaffoldMessengerState>();

const panelColor = Color(0xFF111111);
const dim = Color(0xFF8A8A8A);
const green = Color(0xFF8FD0A0);

final _aud = NumberFormat.currency(locale: 'en_AU', symbol: '\$');
String money(int cents) => _aud.format(cents / 100);
String centsText(int cents) => cents == 0 ? '' : (cents / 100).toStringAsFixed(2);

const categories = <String, (IconData, Color)>{
  'Groceries': (Icons.shopping_basket_outlined, Color(0xFF8FBF9F)),
  'Eating out': (Icons.restaurant_outlined, Color(0xFFE0A070)),
  'Transport': (Icons.directions_bus_outlined, Color(0xFF7FB2D0)),
  'Bills': (Icons.receipt_long_outlined, Color(0xFFD0C080)),
  'Rent': (Icons.home_outlined, Color(0xFFB09FD0)),
  'Shopping': (Icons.shopping_bag_outlined, Color(0xFFE090B0)),
  'Fun': (Icons.sports_esports_outlined, Color(0xFF90D0D0)),
  'Health': (Icons.favorite_outline, Color(0xFFE08080)),
  'Subscriptions': (Icons.autorenew, Color(0xFFA0A0E0)),
  'Travel': (Icons.flight_outlined, Color(0xFF80C0A0)),
  'Other': (Icons.more_horiz, Color(0xFF909090)),
};
(IconData, Color) cat(String name) => categories[name] ?? categories['Other']!;

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: panelColor,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Colors.white10),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.color, {super.key, this.letter, this.icon});
  final Color color;
  final String? letter;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: color.withValues(alpha: .16),
    child: icon != null
        ? Icon(icon, color: color, size: 20)
        : Text(
            letter!.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
  );
}

class Header extends StatelessWidget {
  const Header(this.title, {super.key, this.action, this.page = false});
  final String title;
  final Widget? action;
  final bool page;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: page ? 4 : 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: (page ? t.headlineSmall : t.titleMedium)?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(height: 40, child: action),
        ],
      ),
    );
  }
}

class Bar extends StatelessWidget {
  const Bar(this.value, {super.key, this.color = Colors.white});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.isFinite ? value.clamp(0, 1) : 0),
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => LinearProgressIndicator(
      value: v,
      minHeight: 8,
      color: color,
      backgroundColor: Colors.white10,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(this.cents, {super.key, this.style});
  final int cents;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: cents.toDouble()),
    duration: const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text(money(v.round()), style: style, maxLines: 1),
  );
}

class Stat extends StatelessWidget {
  const Stat(this.label, this.cents, {super.key, this.onTap});
  final String label;
  final int cents;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: dim, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(cents, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}

class TxTile extends StatelessWidget {
  const TxTile(this.t, {super.key});
  final Tx t;

  @override
  Widget build(BuildContext context) {
    final from = store.account(t.accountId)?.name ?? '?';
    final (icon, color, title, sign) = switch (t.type) {
      TxType.expense => (cat(t.category).$1, cat(t.category).$2, t.category, '-'),
      TxType.income => (Icons.south_west, green, 'Income', '+'),
      TxType.transfer => (Icons.swap_horiz, dim, 'Transfer', ''),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Avatar(color, icon: icon),
      title: Text(t.note.isEmpty ? title : t.note, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${t.type == TxType.transfer ? '$from → ${store.account(t.toAccountId)?.name ?? '?'}' : from}'
        ' · ${DateFormat('d MMM').format(t.date)}',
        style: const TextStyle(color: dim),
      ),
      trailing: Text(
        '$sign${money(t.amount)}',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.type == TxType.income ? green : null),
      ),
      onTap: () => showSheet(context, TxSheet(tx: t)),
    );
  }
}

Future<T?> showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: panelColor,
  builder: (context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: SingleChildScrollView(child: child),
  ),
);

class AmountField extends StatelessWidget {
  const AmountField(this.controller, this.label, {super.key, this.onChanged, this.autofocus = false, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: onChanged,
    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
    decoration: InputDecoration(labelText: label, prefixText: '\$ ', helperText: hint, helperMaxLines: 2),
  );
}

/// Asks for a dollar amount. Null when cancelled, 0 when left empty.
Future<int?> askAmount(BuildContext context, String title, {int initial = 0, String? hint}) {
  final c = TextEditingController(text: centsText(initial));
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: AmountField(c, 'Amount', autofocus: true, hint: hint),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, parseCents(c.text) ?? 0), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String question, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
