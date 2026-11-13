import 'package:flutter/material.dart';

import 'pages.dart';
import 'sheets.dart';
import 'store.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  store.open();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NoBudget',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.white,
        secondaryContainer: Color(0xFF2C2C2C),
        onSecondaryContainer: Colors.white,
        surface: Colors.black,
        surfaceContainerLow: panelColor,
        surfaceContainer: panelColor,
        surfaceContainerHigh: Color(0xFF191919),
        surfaceContainerHighest: Color(0xFF1E1E1E),
        outline: Color(0xFF3A3A3A),
        outlineVariant: Color(0xFF2A2A2A),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2C2C2C),
        contentTextStyle: TextStyle(color: Colors.white),
        actionTextColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    ),
    home: const Shell(),
  );
}

const _tabs = [
  ('Overview', Icons.home_outlined, Icons.home),
  ('Spending', Icons.donut_large_outlined, Icons.donut_large),
  ('Goals', Icons.flag_outlined, Icons.flag),
  ('Debts', Icons.credit_card_outlined, Icons.credit_card),
];

/// Bottom navigation on a phone, a side rail on a wide screen.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: tab,
    builder: (context, index, _) {
      final wide = isWide(context), extended = MediaQuery.sizeOf(context).width >= 1200;
      void add() => showSheet(context, const TxSheet());
      final body = ListenableBuilder(
        listenable: store,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Fill the space: a short page would otherwise shrink and sit in the middle.
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: store.loaded
              ? KeyedSubtree(key: ValueKey(index), child: const [Overview(), Spending(), Goals(), Debts()][index])
              : const Center(child: CircularProgressIndicator()),
        ),
      );
      return Scaffold(
        body: SafeArea(
          child: !wide
              ? body
              : Row(
                  children: [
                    NavigationRail(
                      extended: extended,
                      labelType: extended ? null : NavigationRailLabelType.all,
                      backgroundColor: Colors.black,
                      selectedIndex: index,
                      onDestinationSelected: (i) => tab.value = i,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: extended
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 20,
                                children: [
                                  const Text(
                                    'NoBudget',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.5),
                                  ),
                                  FloatingActionButton.extended(
                                    elevation: 0,
                                    onPressed: add,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add transaction'),
                                  ),
                                ],
                              )
                            : FloatingActionButton(
                                elevation: 0,
                                tooltip: 'Add transaction',
                                onPressed: add,
                                child: const Icon(Icons.add),
                              ),
                      ),
                      destinations: [
                        for (final (label, icon, selected) in _tabs)
                          NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                ),
        ),
        floatingActionButton: wide
            ? null
            : FloatingActionButton(tooltip: 'Add transaction', onPressed: add, child: const Icon(Icons.add)),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => tab.value = i,
                destinations: [
                  for (final (label, icon, selected) in _tabs)
                    NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
                ],
              ),
      );
    },
  );
}
