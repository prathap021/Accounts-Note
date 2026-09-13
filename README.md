# Income & Expense Tracker

A production-structured personal finance app built with **Flutter**, **Riverpod**,
and **Cloud Firestore**. This package contains the complete Dart/Flutter source
code, Firestore security rules, indexes, and unit tests.

> **Important:** this zip contains *source code*, not a compiled `.apk`.
> Compiling an Android APK requires the Flutter SDK + Android SDK/NDK +
> Gradle toolchain (several GB of native tooling), which isn't something
> that can be produced or embedded in a text/code deliverable. The good
> news: turning this source into an installed app on your phone is a
> 15-minute, three-command process described below — no code changes
> needed beyond adding your own Firebase project keys.

---

## 1. What's implemented

- **Auth**: Google Sign-In, Sign in with Apple, email/password fallback,
  session persistence (handled automatically by FirebaseAuth), account
  deletion (wipes Firestore data + the Auth account).
- **Transactions**: add/edit/delete income & expense, categories, notes,
  date/time, payment method, search, filter (date range / type / category),
  swipe-to-delete, offline-aware sync indicator.
- **Dashboard**: current balance, monthly income/expense totals, category
  breakdown pie chart, recent transactions, quick-add FAB.
- **Budgets**: overall or per-category monthly budgets, progress bars,
  over-budget / approaching-limit warnings.
- **Categories**: default seeded categories (created automatically on
  first sign-in) + custom categories with icon/color pickers; defaults are
  archived rather than hard-deleted so historical transactions keep their
  labels.
- **Reports**: week/month/year toggle, income vs. expense bar chart, CSV
  export + share sheet.
- **Settings**: profile, manage categories, sign out, delete account.
- **Security**: strict per-user Firestore rules (`firestore.rules`) — a
  user can only ever read/write documents under their own `uid`.
- **Offline**: Firestore's unlimited local cache is enabled in `main.dart`;
  reads/writes work offline and sync automatically on reconnect.
- **Tests**: repository unit tests using `fake_cloud_firestore`, model
  round-trip tests.

## 2. Architecture

```
Presentation (screens/widgets, features/*)
        │
Application/State (providers/*, Riverpod Notifiers)
        │
Domain (models/*)
        │
Data (data/repositories/*, Firestore/Auth SDKs)
```

- **Repository pattern**: `AuthRepository`, `TransactionRepository`,
  `CategoryRepository`, `BudgetRepository` are the only classes that touch
  Firebase SDKs directly. Everything returns a `Result<T>`
  (`core/utils/result.dart`) so the UI never deals with raw exceptions.
- **State management**: Riverpod `StreamProvider`/`FutureProvider` for
  reads, `StateNotifierProvider` for actions (add/edit/delete), keeping
  loading/error/success uniform across the app.
- **Firestore layout** — everything is nested under the user, so isolation
  is structural, not just rule-based:

```
users/{uid}
  ├─ (profile fields: email, displayName, currency, themeMode, ...)
  ├─ transactions/{transactionId}
  ├─ categories/{categoryId}
  ├─ budgets/{"yyyy-MM_categoryIdOrOverall"}
  ├─ recurringTransactions/{recurringId}
  ├─ settings/preferences
  └─ notifications/{notificationId}
```

## 3. Folder structure

```
lib/
  core/
    constants/app_constants.dart      # collection paths, enums, defaults
    router/app_router.dart            # GoRouter + auth-based redirects
    theme/app_theme.dart              # Material 3 light/dark theme
    utils/currency_formatter.dart
    utils/result.dart                 # Result<T>/AppFailure
  models/                             # Transaction, Category, Budget, AppUser
  data/repositories/                  # Firebase-touching classes
  providers/                          # Riverpod providers & notifiers
  features/
    splash/  auth/  dashboard/  transactions/
    budgets/ categories/ reports/ settings/
  widgets/                            # shared UI (tiles, cards, scaffold)
  main.dart
  firebase_options.dart               # PLACEHOLDER — regenerate, see below
firestore.rules
firestore.indexes.json
test/
```

## 4. Building this into a real installed app

### Step 0 — Prerequisites (one-time, on your own machine)
Install [Flutter](https://docs.flutter.dev/get-started/install) and Android
Studio (for the Android SDK). Run `flutter doctor` until it's happy.

### Step 1 — Scaffold the native Android/iOS projects
This source ships only the Dart code and configs; the native
`android/` and `ios/` runner folders are machine-generated boilerplate
that `flutter create` produces for your exact Flutter/Gradle version
(hand-writing them risks a mismatched, broken build):

```bash
flutter create --platforms=android,ios --org com.yourcompany income_expense_tracker
```

Then copy this zip's `lib/`, `pubspec.yaml`, `firestore.rules`,
`firestore.indexes.json`, `test/`, and `analysis_options.yaml` into the
newly created project, overwriting the generated `lib/` and `pubspec.yaml`.

### Step 2 — Create a Firebase project & connect it
1. Go to the [Firebase console](https://console.firebase.google.com),
   create a project.
2. Enable **Authentication** → Google, Apple, and Email/Password sign-in
   methods.
3. Enable **Cloud Firestore** (start in production mode).
4. Enable **Storage**, **Analytics**, and **Crashlytics** if you want them
   (all already wired into `main.dart`).
5. From the project root:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   This registers your Android/iOS app IDs and **overwrites the placeholder
   `lib/firebase_options.dart`** with real keys. It also drops
   `google-services.json` / `GoogleService-Info.plist` into the right
   native folders automatically.
6. Deploy the security rules and indexes:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase init firestore   # point it at the existing firestore.rules/.indexes.json
   firebase deploy --only firestore:rules,firestore:indexes
   ```

### Step 3 — Google/Apple sign-in platform setup
- **Google Sign-In (Android)**: add your debug & release SHA-1/SHA-256
  fingerprints in the Firebase console → Project settings → your Android
  app (`keytool -list -v -keystore ~/.android/debug.keystore`).
- **Sign in with Apple (iOS)**: in Xcode, open `ios/Runner.xcworkspace`,
  select the Runner target → Signing & Capabilities → **+ Capability** →
  add "Sign in with Apple".

### Step 4 — Install packages & run
```bash
flutter pub get
flutter run
```

### Step 5 — Build the release APK
```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```
For the Play Store, prefer an app bundle:
```bash
flutter build appbundle --release
```
(For a real release you'd also configure `android/app/build.gradle`
signing config with your own keystore — `flutter build apk --release`
will use a debug key otherwise, which installs fine on your own device
but isn't acceptable for the Play Store.)

### Step 6 — Run the tests
```bash
flutter test
```

## 5. Notes & next steps
- Recurring-transaction auto-generation and scheduled push notifications
  (budget warnings, monthly summaries) are modeled in Firestore
  (`recurringTransactions`, `notifications` collections) but need a small
  Cloud Function or scheduled job to actually fire FCM messages — that
  piece runs server-side and isn't part of the Flutter client.
- PDF export is listed as a dependency (`pdf`, `printing`) for you to wire
  up the same way CSV export is done in `reports_screen.dart`, if you want
  a formatted PDF report in addition to CSV.
