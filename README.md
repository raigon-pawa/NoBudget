# NoBudget

A personal budgeting app for Android, built with Flutter. Everything is entered by hand and stored
locally in SQLite. There are no bank connections, no accounts and no network access.

<p>
  <img src="docs/overview.png" width="200" alt="Overview: net worth and account balances">
  <img src="docs/spending.png" width="200" alt="Spending: donut chart, budgets and transactions">
  <img src="docs/goals.png" width="200" alt="Goals: savings target with a weekly amount">
  <img src="docs/debts.png" width="200" alt="Debts: amount owed and available credit">
</p>

## Features

- **Overview**: net worth, cash, debt and credit left, with balances across your bank accounts.
- **Spending**: expenses by category for each month, optional monthly budgets per category, and
  the full transaction history. Tap a slice of the chart to filter, swipe a transaction to delete it.
- **Goals**: savings targets with an optional deadline and the weekly amount needed to hit it.
- **Debts**: buy-now-pay-later, credit and loan accounts with the amount owed, available credit
  and one-tap repayments.
- **Transactions update balances for you**: paying with a BNPL account raises what you owe, and a
  transfer into a debt account counts as a repayment.

The app starts with a set of Australian accounts (CommBank, ANZ Plus, Wise, Revolut, Up, Latitude,
Klarna, Afterpay) that you can rename or delete. All amounts are in AUD.

NoBudget is not affiliated with any of the banks or lenders named above.

## Build

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) and an Android device or
emulator.

```sh
flutter pub get
flutter test
flutter run                      # debug build on a connected device
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key, so it is for sideloading only.

## Code layout

| File | What it holds |
|---|---|
| `lib/models.dart` | Accounts, transactions, goals and the money maths |
| `lib/store.dart` | SQLite database and the in-memory state the UI listens to |
| `lib/pages.dart` | The four tabs |
| `lib/sheets.dart` | Forms for transactions, accounts and goals |
| `lib/ui.dart` | Shared widgets, categories and formatting |

Money is stored as integer cents.

## Licence

[MIT](LICENSE)
