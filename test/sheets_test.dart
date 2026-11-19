import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobudget/models.dart';
import 'package:nobudget/sheets.dart';
import 'package:nobudget/store.dart';
import 'package:nobudget/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [sheet] behind a button, the way the app opens it, so closing it and its messages work as in the app.
Widget _app(Widget sheet) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showSheet<void>(context, sheet),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.open();
  });

  testWidgets('a new account takes a ready-made colour or any custom hue', (tester) async {
    await tester.pumpWidget(_app(const AccountSheet()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Savings');
    await tester.tap(find.bySemanticsLabel('Blue'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.bySemanticsLabel('Custom colour'));
    await tester.pump();
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-400, 0)); // to the red end
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final a = store.accounts.firstWhere((a) => a.name == 'Savings');
    expect(HSVColor.fromColor(Color(a.color)).hue, lessThan(20));
    expect(a.color, isNot(0xFF4AA8FF));
  });

  testWidgets('the hue slider keeps its place at the end, and a bank suggestion leaves Custom', (tester) async {
    await tester.pumpWidget(_app(const AccountSheet()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Custom colour'));
    await tester.pump();
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(800, 0)); // past the right end: hue 360 is the same red as 0
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, 360);
    await tester.tap(find.text('CommBank'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
    expect(tester.getSemantics(find.bySemanticsLabel('Yellow')), containsSemantics(isSelected: true));
  });

  testWidgets('deleting a transaction from its editor can be undone', (tester) async {
    final bank = store.accounts.first;
    store.addTx(Tx(type: TxType.income, amount: 5000, accountId: bank.id!, date: DateTime(2026, 11, 1)));
    final t = store.txs.single;
    await tester.pumpWidget(_app(TxSheet(tx: t)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(store.txs, isEmpty);
    expect(store.account(bank.id)!.balance, bank.balance);
    expect(find.text('Transaction deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.txs.single.id, t.id);
    expect(store.account(bank.id)!.balance, bank.balance + 5000);
  });
}
