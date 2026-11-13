# NoBudget

A personal budgeting app for Android and the web, built with Flutter. Everything is entered by hand
and stored on your own device (or in your browser). There are no bank connections, no accounts and
nothing is sent anywhere.

<p>
  <img src="docs/overview.png" width="200" alt="Overview: net worth and account balances">
  <img src="docs/spending.png" width="200" alt="Spending: donut chart, budgets and transactions">
  <img src="docs/goals.png" width="200" alt="Goals: savings target with a weekly amount">
  <img src="docs/debts.png" width="200" alt="Debts: amount owed and available credit">
</p>

On a wide screen the same app lays itself out in two columns with a side rail:

<p>
  <img src="docs/desktop.png" width="410" alt="Overview in a desktop browser">
  <img src="docs/desktop-spending.png" width="410" alt="Spending in a desktop browser">
</p>

## Features

- **Overview**: net worth with a 30-day trend, cash, debt and credit left, and balances across your
  bank accounts.
- **Spending**: expenses by category for each month, optional monthly budgets per category, and
  the full transaction history. Tap a slice of the chart to filter, swipe a transaction to delete it.
- **Goals**: savings targets with an optional deadline and the weekly amount needed to hit it.
- **Debts**: buy-now-pay-later, credit and loan accounts with the amount owed, available credit
  and one-tap repayments.
- **Repeating transactions**: mark rent, pay or a subscription as weekly, fortnightly or monthly and
  it is added for you when it falls due.
- **Search**: find any transaction by note, category, account or amount.
- **Backup**: copy everything as text from the menu on the net worth card, and paste it back to
  restore, on the same device or another one.
- **Transactions update balances for you**: paying with a BNPL account raises what you owe, and a
  transfer into a debt account counts as a repayment.

The app starts with a set of Australian accounts (CommBank, ANZ Plus, Wise, Revolut, Up, Latitude,
Klarna, Afterpay) that you can rename or delete. All amounts are in AUD.

NoBudget is not affiliated with any of the banks or lenders named above.

## Build

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install), plus an Android device or
emulator for the app, or Chrome for the website.

```sh
flutter pub get
flutter test

flutter run                      # Android: debug build on a connected device
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk

flutter run -d chrome            # web: debug in Chrome
flutter build web --release --no-web-resources-cdn    # build/web, static files for any web host
```

The Android release build is signed with the debug key, so it is for sideloading only. The web
build is a folder of static files; to try it locally, run `python3 -m http.server` inside
`build/web`. If it will be served from a sub-path, add `--base-href /that-path/` to the build.

Data stays where it was entered: the Android app and each browser keep their own copy, and clearing
a browser's site data removes it. Sign-in and cloud sync are in progress on the
[`firebase`](../../tree/firebase) branch.

## Code layout

| File | What it holds |
|---|---|
| `lib/models.dart` | Accounts, transactions, goals and the money maths |
| `lib/store.dart` | The in-memory state the UI listens to, saved on the device as one JSON document |
| `lib/main.dart` | Theme and the shell: bottom bar on a phone, side rail on a wide screen |
| `lib/pages.dart` | The four tabs |
| `lib/sheets.dart` | Forms for transactions, accounts and goals |
| `lib/ui.dart` | Shared widgets, categories and formatting |

Money is stored as integer cents.

## Licence

[MIT](LICENSE)
