# NoBudget

A personal budgeting app for Android, built with Flutter. Everything is entered by hand and stored
locally in SQLite; there are no bank connections and no network access.

- **Overview**: net worth, cash, debt, credit left, and balances across bank accounts
  (CommBank, ANZ Plus, Wise, Revolut and Up are pre-created).
- **Spending**: expenses by category for each month, optional monthly budgets, transaction history.
- **Goals**: savings targets with an optional deadline and the weekly amount needed to hit it.
- **Debts**: BNPL, credit and loan accounts (Latitude, Klarna, Afterpay) with amount owed,
  available credit and repayments.

All amounts are in AUD.

## Build

```sh
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key, so it is for sideloading only.

## Layout

| File | What it holds |
|---|---|
| `lib/models.dart` | Accounts, transactions, goals and the money maths |
| `lib/store.dart` | SQLite database and the in-memory state the UI listens to |
| `lib/pages.dart` | The four tabs |
| `lib/sheets.dart` | Forms for transactions, accounts and goals |
| `lib/ui.dart` | Shared widgets, categories and formatting |
