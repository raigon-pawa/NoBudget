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

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: tab,
    builder: (context, index, _) => Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.loaded
              ? const [Overview(), Spending(), Goals(), Debts()][index]
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add transaction',
        onPressed: () => showSheet(context, const TxSheet()),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => tab.value = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.donut_large_outlined), label: 'Spending'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Goals'),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon: Icon(Icons.credit_card),
            label: 'Debts',
          ),
        ],
      ),
    ),
  );
}
