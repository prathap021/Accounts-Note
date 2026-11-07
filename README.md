# Accounts Note

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Open-source** personal finance app to track income and expenses. Built with
**Flutter**, **Riverpod**, and **Cloud Firestore**.

Anyone is welcome to use, fork, improve, and contribute.

Repository: [github.com/prathap021/Accounts-Note](https://github.com/prathap021/Accounts-Note)

---

## Features

- **Auth**: Google Sign-In, Sign in with Apple, email/password, session
  persistence, log out
- **Currencies**: every currency Google Play bills in, searchable. On first
  launch the app offers to use the phone's approximate location (once, on
  the device) to pick the currency; otherwise it uses the phone's region
- **Updates and reviews**: Google Play in-app updates (in the background,
  with a restart prompt; blocking only for high-priority releases) and the
  store's in-app rating prompt, plus "Rate Accounts Note" and "Check for
  updates" in Settings
- **Transactions**: add/edit/delete income & expense, categories, notes,
  date/time, payment method, search, filters, swipe-to-delete, offline sync
- **Dashboard**: balance, monthly totals, category pie chart, recent activity
- **Budgets**: overall or per-category monthly budgets with progress warnings
- **Credit cards**: add any number of cards (name, colour, optional limit, and
  only the last 4 digits — never the full number), pick a card as the payment
  method when logging an expense, see each card's spend this month, and filter
  Activity by one card or all cards. Every filter shows its total, live in the
  filter sheet as you tap
- **Categories**: default seeded categories + custom icon/color categories
- **Subscriptions**: free accounts can add 14 transactions a day, income and
  expense in any mix. Three plans raise that: Basic 60 a day (1,800 a month),
  Standard 120 (3,600) and Premium 200 (6,000), paid monthly (₹99 / ₹199 /
  ₹299 in India, $1 / $2 / $3 elsewhere) or yearly for twelve months less
  ₹99 / $1. Bought through Google Play Billing
  or the App Store, verified by Cloud Functions, and enforced by the
  Firestore rules, so a modified app cannot get round the limits
- **Backup and import**: one tap saves every transaction, category, card
  and budget to a file; importing it adds them to any account, the same one
  or another, without using up the day's allowance. Files are signed by the
  server, so an edited file is refused
- **Accounts and transfers**: cash, bank, UPI and wallet accounts with
  opening balances and live balances; pick one when logging an entry; move
  money between them with transfers, which are neither income nor expense
- **Receipts**: attach a photo (camera or gallery) to any entry; stored
  compressed in `users/{uid}/receipts/{txId}` and fetched only when opened
- **Import from CSV**: another app's export, a bank statement or this app's
  own report. The app previews the file; the `importCsvRows` function writes
  the entries, up to the plan's monthly total per calendar month, and the
  same file imported twice adds nothing
- **App lock**: optional 4-digit PIN and fingerprint/face unlock; locks on
  launch and after 30 s in the background
- **Reports**: day/week/month/year or any custom period picked on a calendar
  (including past history), spending and income by category (tap one to see
  its entries), a trend chart, and export as PDF, Excel or CSV
- **Security**: per-user Firestore rules — users only access their own data
- **Offline**: Firestore unlimited local cache; syncs when back online
- **Tests**: repository and model unit tests

---

## Architecture

```
Presentation (screens/widgets, features/*)
        │
Application/State (providers/*, Riverpod Notifiers)
        │
Domain (models/*)
        │
Data (data/repositories/*, Firestore/Auth SDKs)
```

- **Repository pattern**: only repositories talk to Firebase; they return
  `Result<T>` so the UI never handles raw exceptions
- **State**: Riverpod providers/notifiers for reads and actions
- **Firestore layout** (everything under the signed-in user):

```
users/{uid}
  ├─ profile fields
  ├─ transactions/{transactionId}
  ├─ categories/{categoryId}
  ├─ budgets/{budgetId}
  ├─ creditCards/{cardId}
  ├─ accounts/{accountId}        cash, bank, UPI and wallet accounts
  ├─ transfers/{transferId}      money moved between accounts
  ├─ receipts/{transactionId}    a receipt photo (bytes)
  ├─ recurringTransactions/{recurringId}
  ├─ settings/preferences
  ├─ notifications/{notificationId}
  ├─ usage/{yyyy-MM-dd}          entries added that day (daily limit)
  └─ importUsage/{yyyy-MM}       CSV rows imported that month (Cloud Functions only)

subscriptionLinks/{linkId}       which account owns each store subscription
                                 (Cloud Functions only)
```

---

## Folder structure

```
lib/
  core/           # constants, router, theme, utils
  models/         # Transaction, Category, Budget, AppUser
  data/repositories/
  providers/      # Riverpod
  features/       # splash, auth, dashboard, transactions, budgets, …
  widgets/
  main.dart
  firebase_options.dart          # gitignored — create locally
  firebase_options.dart.example  # placeholder
android/app/google-services.json.example
firebase.json.example
firestore.rules
firestore.indexes.json
test/
```

---

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Android Studio / Xcode as needed
- A [Firebase](https://console.firebase.google.com) project

Run `flutter doctor` until your toolchain looks healthy.

### 1. Clone the repo

```bash
git clone https://github.com/prathap021/Accounts-Note.git
cd Accounts-Note
```

### 2. Connect your own Firebase project

Firebase keys are **not** in this open-source repo (on purpose).

1. Create a Firebase project
2. Enable **Authentication** (Google, Apple, Email/Password)
3. Enable **Cloud Firestore** (production mode)
4. Optionally enable Storage, Analytics, Crashlytics
5. From the project root:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

That generates `lib/firebase_options.dart`,
`android/app/google-services.json`, and (on macOS)
`ios/Runner/GoogleService-Info.plist`.

6. Deploy rules and indexes:

```bash
npm install -g firebase-tools
firebase login
firebase init firestore   # use existing firestore.rules / firestore.indexes.json
firebase deploy --only firestore:rules,firestore:indexes
```

### 3. Platform sign-in setup

- **Google (Android)**: add debug/release SHA-1 and SHA-256 in Firebase →
  Project settings → your Android app, then re-download
  `google-services.json` so `oauth_client` is populated
- **Apple (iOS)**: in Xcode add the **Sign in with Apple** capability

### 4. Subscriptions (in-app purchases)

Each plan is an auto-renewing subscription, monthly or yearly, with these
product ids, the same in both stores (they are defined in
`lib/models/subscription_plan.dart`, `firestore.rules` and
`functions/src/subscriptions.ts`, which must agree). The limit is one
allowance per day for income and expense together:

| Plan | Product id | India | Elsewhere | Transactions a day (a month) |
|---|---|---:|---:|---:|
| Basic | `accounts_note_basic_monthly` | ₹99 | $1 | 60 (1,800) |
| | `accounts_note_basic_yearly` | ₹1,089 | $11 | |
| Standard | `accounts_note_standard_monthly` | ₹199 | $2 | 120 (3,600) |
| | `accounts_note_standard_yearly` | ₹2,289 | $23 | |
| Premium | `accounts_note_premium_monthly` | ₹299 | $3 | 200 (6,000) |
| | `accounts_note_premium_yearly` | ₹3,489 | $35 | |

Yearly is twelve months less ₹99 / $1. Free accounts get 14 a day. The app
shows the store's own price for the buyer's country, so set the prices
there: in Play Console the India price and the USD base price that Play
converts for other countries (likewise per storefront in App Store
Connect). Until the
store answers, the app shows the list price: rupees when the user keeps
accounts in INR, dollars otherwise.

**Google Play**

1. In Play Console → Monetize → Subscriptions, create the six products:
   each monthly one with a monthly auto-renewing base plan, each yearly one
   with a yearly base plan. Activate the base plans.
2. Give the Cloud Functions service account
   (`PROJECT_ID@appspot.gserviceaccount.com`) access in Play Console → Users
   and permissions, with "View financial data" and "Manage orders and
   subscriptions". The functions use it to read purchases; no key file is
   needed.
3. Real-time notifications: Play Console → Monetize → Monetization setup →
   topic `projects/PROJECT_ID/topics/play-billing-notifications`. Grant
   `google-play-developer-notifications@system.gserviceaccount.com` the Pub/Sub
   Publisher role on that topic (deploying the functions creates it).

**App Store**

1. In App Store Connect, create one subscription group with the six
   products, ordered Premium, Standard, Basic (highest first; within a plan,
   yearly above monthly), so moving between them is treated as an upgrade or
   downgrade.
2. Create an In-App Purchase key (Users and Access → Integrations) and set:

```bash
# functions/.env
APPLE_IAP_KEY_ID=XXXXXXXXXX
APPLE_IAP_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APPLE_BUNDLE_ID=com.example.incomeExpenseTracker
```

```bash
firebase functions:secrets:set APPLE_IAP_PRIVATE_KEY < SubscriptionKey_XXXXXXXXXX.p8
```

   Not shipping on iOS yet? Set the secret to `unset`; deploying needs it to
   exist, and iOS verification then reports that it is not set up.
3. App Store Server Notifications (V2): point both the production and sandbox
   URLs at the `appStoreNotifications` function's URL.
4. In Xcode, add the **In-App Purchase** capability.

**Deploy**

```bash
cd functions && npm install && cd ..
firebase deploy --only functions,firestore:rules
```

Two things that broke the first deploy, in case they come back:

- **`npm ci` fails in Cloud Build** ("package.json and package-lock.json
  … are not in sync", missing `@emnapi/*`): Cloud Build uses Node 22's
  npm 10, and a lock file written by npm 11 leaves those out. Regenerate it
  with `cd functions && npx npm@10 install`.
- **The app gets HTTP 403 from a callable function.** Firebase makes a
  callable public (the function checks the user itself) only when it is
  first created. If a create failed and a later deploy "updated" it, it
  stays private: delete it (`firebase functions:delete NAME`) and deploy
  again. Unauthenticated, a working callable answers "Sign in required."

The app's own check stops the user as soon as a limit is reached, even
offline. The Firestore rules are what enforce it: a new transaction is
accepted only in the same write as a +1 to that day's counter, within the
plan's limit, and the plan fields can only be written by the functions.
Entries made offline are accepted up to 3 days late.

**Backups** need one more secret, a long random string that signs backup
files (changing it later makes older files unimportable):

```bash
openssl rand -hex 32 > /tmp/k && \
  firebase functions:secrets:set BACKUP_SIGNING_KEY --data-file /tmp/k && rm /tmp/k
```

The signing and merging are tested on the Firestore emulator:

```bash
(cd functions && npm run build)
firebase emulators:exec --only firestore --project demo-accounts-note \
  "node --test functions/test/backup.test.mjs"
```

**Going live: if purchases do not work**

Live purchases need every one of these; any one missing breaks them:

- [ ] The functions are deployed. `firebase functions:list` must show
      `verifySubscription`, `refreshSubscription`, `playBillingNotifications`
      and `appStoreNotifications`. Without them the app cannot confirm a
      purchase, no plan is granted, and it retries on every launch.
- [ ] The new `firestore.rules` are deployed (same command), or uploads of
      new entries are checked against the old rules.
- [ ] A real package name. Google Play does not accept `com.example.*`:
      change `applicationId` in `android/app/build.gradle.kts` (and
      `AppLinks.androidPackage`, `PLAY_PACKAGE_NAME`), register that package
      in Firebase, and download the new `google-services.json`.
- [ ] A release signing key. Release builds are signed with the debug key
      today, which Play rejects. Create an upload keystore and point
      `signingConfigs` at it.
- [ ] The app uploaded to a Play track (internal testing is enough) with
      the `in_app_purchase` build, and the six products created and
      activated in Play Console with exactly the ids above.
- [ ] Testers added under Settings → License testing, and the test build
      installed from the Play testing link (not side-loaded) with that
      Google account signed in to the Play Store.
- [ ] Google Play Android Developer API enabled in the Firebase project's
      Google Cloud console, and the functions' service account invited in
      Play Console with financial and orders permissions (step 2 above).
      Without it `verifySubscription` answers "Could not reach Google Play".
- [ ] For the App Store: the Paid Apps agreement signed, the products ready
      for review, the API key secret set, and testing done with a sandbox
      account.

### 5. Run

```bash
flutter pub get
flutter run
```

### 6. Release build

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

Configure your own signing keystore for Play Store releases.

### 7. Tests

```bash
flutter test                                   # unit and widget tests
patrol test --dart-define-from-file=patrol_test/single_session.json
                                               # end-to-end, on a device
(cd rules_test && npm install)                 # once
firebase emulators:exec --only firestore --project demo-accounts-note \
  "npm --prefix rules_test test"               # Firestore rules
```

See [patrol_test/README.md](patrol_test/README.md) for the end-to-end suite.

---

## Contributing

Contributions are welcome — bug fixes, features, docs, and tests.

1. Fork the repository
2. Create a branch: `git checkout -b feature/your-idea`
3. Make your changes and add/update tests when useful
4. Run `flutter analyze` and `flutter test`
5. Open a Pull Request describing **what** and **why**

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

Ideas that help a lot:

- Bug reports with steps to reproduce
- UI/UX polish and accessibility
- Extra export formats (e.g. PDF reports)
- Recurring transactions / FCM budget reminders (Cloud Functions)
- Better docs and translations

---

## Security & secrets

Do **not** commit:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `firebase.json` / `.firebaserc`
- Keystores (`.jks` / `.keystore`) or `key.properties`
- `.env` or service-account JSON files

Use the `*.example` files as templates. See `.gitignore`.

---

## License

This project is open source under the [MIT License](LICENSE).

You are free to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the software, provided the license and copyright
notice are included.

Copyright (c) 2026 prathap021

---

## Notes / roadmap

- Recurring transactions and scheduled push notifications are modeled in
  Firestore but need a Cloud Function (or similar) to send FCM
- PDF export dependencies (`pdf`, `printing`) are available; wire them
  similarly to CSV export in `reports_screen.dart` if you want formatted PDFs
