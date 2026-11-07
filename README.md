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
  persistence, account deletion (wipes Firestore data + Auth account)
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
- **Subscriptions**: free accounts can add 7 income and 7 expense entries a
  day. Three monthly plans raise that: Basic ₹99 (30 + 30), Standard ₹199
  (60 + 60) and Premium ₹299 (100 + 100). Bought through Google Play Billing
  or the App Store, verified by Cloud Functions, and enforced by the
  Firestore rules, so a modified app cannot get round the limits
- **Reports**: week/month/year views, charts, CSV export & share
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
  ├─ recurringTransactions/{recurringId}
  ├─ settings/preferences
  ├─ notifications/{notificationId}
  └─ usage/{yyyy-MM-dd}          entries added that day, per type (limits)

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

The plans are monthly auto-renewing subscriptions with these product ids,
the same in both stores (they are defined in
`lib/models/subscription_plan.dart`, `firestore.rules` and
`functions/src/subscriptions.ts`, which must agree):

| Plan | Product id | Price | Income / expense per day |
|---|---|---:|---:|
| Basic | `accounts_note_basic_monthly` | ₹99 | 30 / 30 |
| Standard | `accounts_note_standard_monthly` | ₹199 | 60 / 60 |
| Premium | `accounts_note_premium_monthly` | ₹299 | 100 / 100 |

Free accounts get 7 / 7. Prices shown in the app come from the store, so set
them there.

**Google Play**

1. In Play Console → Monetize → Subscriptions, create the three products,
   each with one monthly auto-renewing base plan.
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

1. In App Store Connect, create one subscription group with the three
   products, ordered Premium, Standard, Basic (highest first), so moving
   between them is treated as an upgrade or downgrade.
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

The app's own check stops the user as soon as a limit is reached, even
offline. The Firestore rules are what enforce it: a new transaction is
accepted only in the same write as a +1 to that day's counter, within the
plan's limit, and the plan fields can only be written by the functions.
Entries made offline are accepted up to 3 days late.

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
