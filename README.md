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
- **Categories**: default seeded categories + custom icon/color categories
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
  ├─ recurringTransactions/{recurringId}
  ├─ settings/preferences
  └─ notifications/{notificationId}
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

### 4. Run

```bash
flutter pub get
flutter run
```

### 5. Release build

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

Configure your own signing keystore for Play Store releases.

### 6. Tests

```bash
flutter test
```

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

## Contributions (Stripe — one-time)

No subscription. Freemium + optional contribution:

| Tier | Limit |
|------|--------|
| Free | **7 transactions/day** |
| After contributing | **Unlimited** (one-time unlock) |

Contribution amounts (USD):
- Presets: **$5 · $10 · $25**
- Or any custom amount (**minimum $5**)

### Setup
1. Stripe Dashboard → enable Checkout (one-time payments)
2. Put **publishable** key only in `functions/.env` (gitignored)
3. Put **secret** keys in `functions/.secret.local` (gitignored) for local/emulator
4. Production secrets (already set for this project):
   ```bash
   firebase functions:secrets:set STRIPE_SECRET_KEY
   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
   ```
5. Deploy:
   ```bash
   cd functions && npm install && npm run build && cd ..
   firebase deploy --only functions,hosting,firestore:rules
   ```
6. Stripe webhook endpoint (copy Signing secret → update `STRIPE_WEBHOOK_SECRET`):

`https://stripewebhook-xsmfilywxa-uc.a.run.app`

   Event: `checkout.session.completed`

**Never commit** `.env`, `.secret.local`, or real `sk_` / `whsec_` values. Only `functions/.env.example` is safe to commit.

### In the app
- **You → Contribute**, or the paywall after 7 daily transactions
- Success/cancel pages deep-link via `accountsnote://stripe-success`

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
