# Test suite

## Running

```bash
flutter test                 # everything: 155 tests, ~9s
flutter analyze              # static analysis; run this too
```

A green run means the behaviours below still hold.

Whole user flows (sign-up, logging transactions, filters, budgets, cards,
settings, offline sync) are covered end-to-end on a device by the Patrol
suite in [`patrol_test/`](../patrol_test/README.md). Run it with
`patrol test`; `flutter test` covers only this folder.

### While working on one area

```bash
flutter test test/unit/data                            # one folder
flutter test test/unit/currency_formatter_test.dart    # one file
flutter test --plain-name "does not duplicate"         # one test, by name
flutter test --name "sync|offline"                     # by regex
```

`--reporter compact` keeps the output to a single line if the default is noisy.

### Before pushing

```bash
flutter analyze && flutter test
```

That is exactly what CI runs, so if it passes locally it passes there.

### Coverage

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html   # needs lcov installed
```

### Automatically, every time

- **On push / pull request** — already set up in
  `.github/workflows/tests.yml`. Nothing to configure: the suite needs no
  secrets, so it runs on forks and fresh clones too.
- **On commit** — install a pre-commit hook (one-off, per clone):

  ```bash
  cat > .git/hooks/pre-commit <<'HOOK'
  #!/bin/sh
  flutter analyze || exit 1
  flutter test || exit 1
  HOOK
  chmod +x .git/hooks/pre-commit
  ```

  Skip it for a single commit with `git commit --no-verify`.
- **On save** — `flutter test` has no watch mode. Use the IDE's test runner
  (VS Code: the play icon in the gutter; Android Studio: right-click a test),
  or re-run on file change with [`entr`](https://eradman.com/entrproject/):

  ```bash
  find lib test -name '*.dart' | entr -c flutter test
  ```

## Layout

| Path | Covers |
|---|---|
| `support/fixtures.dart` | Shared builders (`txFixture`, `categoryFixture`, `budgetFixture`) and the `HiveHarness` that opens a real, throwaway Hive box |
| `unit/currency_formatter_test.dart` | Money formatting: grouping per currency, decimals, the spaced symbol on the dashboard, amount-in-words |
| `unit/greeting_test.dart` | Time-of-day greeting buckets and display-name resolution |
| `unit/models/transaction_model_test.dart` | Hive and Firestore serialization round-trips, including maps written by older builds |
| `unit/data/local_store_test.dart` | Ordering, the pending queue, `watch()` notifications, cloud reconciliation, per-user isolation |
| `unit/data/transaction_filter_test.dart` | The Activity filter flow: type, category, payment method, credit card, date range, search |
| `unit/data/aggregation_test.dart` | The numbers behind the dashboard, Reports and Budgets |
| `unit/data/offline_sync_test.dart` | Offline writes, tombstoned deletes, replay de-duplication, failure and retry |
| `unit/data/category_repository_test.dart` | Category CRUD and the delete-vs-archive rule |
| `unit/data/budget_repository_test.dart` | Budget upsert keying, period scoping |
| `unit/data/credit_card_repository_test.dart` | Card CRUD, ordering, per-user isolation, and writes the server never acknowledges (offline) |
| `unit/models/credit_card_model_test.dart` | Card serialization, display name, and the guards that keep a full card number out |
| `unit/credit_card_totals_test.dart` | The total for a filter, and each card's spend this month across month boundaries |
| `unit/models/subscription_test.dart` | Plan prices and daily limits, which states keep a plan (cancelled until it ends; on hold, paused, expired never), parsing the profile, and the App Store account tag matching the backend's |
| `unit/data/daily_usage_test.dart` | Which local day an entry counts against, the on-device count of entries not yet uploaded, and that each new entry uploads with its day-counter bump |
| `unit/state/subscription_controller_test.dart` | The daily limit check (free, paid, expired, unsynced entries) and buying: verify-then-acknowledge, upgrades, cancelled and pending payments, refused purchases, restore, unconfirmed purchases picked up at launch |
| `unit/state/settings_provider_test.dart` | Theme, currency and onboarding persistence |
| `unit/state/sync_state_test.dart` | The Synced / Syncing / Pending / Failed labels |
| `unit/email_verification_test.dart` | Who is gated behind verification — email/password yes, Google and Apple never |
| `unit/password_reset_test.dart` | Reset failure wording, including the unregistered-address case |
| `widget/transaction_tile_test.dart` | Activity row content, amount sign and colour, category icon, card name, swipe-to-delete confirmation |
| `widget/credit_card_filter_test.dart` | Activity filtered by card: the live total in the filter sheet, the applied total, net with refunds, whole-day date ranges |
| `widget/credit_card_form_test.dart` | The add/edit card form: what it saves and hands back, digits-only last 4, refusing a card number |
| `widget/sync_status_chip_test.dart` | Sync chip and failure banner states |
| `widget/verify_email_screen_test.dart` | Email-verification gate: address shown, resend cooldown, silent re-check on resume vs. reporting on manual check |
| `widget/forgot_password_sheet_test.dart` | Password reset: validation, carried-over email, confirmation |
| `unit/currencies_test.dart` | Every Play currency listed once and formattable, country → currency, the country default for new installs only, and plan prices in rupees or dollars |
| `unit/review_and_update_test.dart` | When an update is blocking or background, the 3-day pause after "no", restart only on request, no Play → unavailable; and when the rating prompt appears |
| `widget/currency_setup_test.dart` | First-run currency: from the location when allowed, the region's otherwise, and "Not now" never asks for location |
| `unit/data/subscription_repository_test.dart` | Which verification failures are final: a function that is not deployed is always retried, so a purchase is never kept without its plan |
| `widget/backup_flow_test.dart` | Back up now (share sheet, unsynced-entries warning) and Import a backup (preview, currency switch, refused files, cancel) |
| `widget/report_period_test.dart` | Reports for any period: the Custom option, cancelling the calendar, a past period with both end days in full, an empty period, and the export format sheet |
| `unit/report_export_test.dart` | Report files: the period's entries and totals, CSV rows, the Excel summary and transactions sheets, a valid PDF, text the PDF fonts cannot draw |
| `unit/state/first_sync_test.dart` | When the dashboard shimmers: while the box opens and on a first sign-in until the first sync, but never over data already on the device |
| `widget/subscription_screen_test.dart` | The plan screen: three plans with prices and limits, status and today's use, subscribe/upgrade labels, no-store notice, restore; and the limit-reached sheet |
| `unit/app_lock_test.dart` | PIN stored only as a salted hash, every launch locks, 5 wrong tries → 30 s wait, relock after 30 s away, fingerprint must work before it is turned on, Forgot PIN dialog above the router |
| `unit/accounts_test.dart` | Account balances from opening balance, entries and transfers (card charges, deleted entries and closed accounts left out); accounts and transfers through Firestore; the account fields on a transaction |
| `unit/report_insights_test.dart` | Spending and income by category (adding up to the totals), the trend by day, week or month with empty slices kept, and the Day period |
| `unit/csv_import_test.dart` | Reading CSV files: this app's export, bank statements with title lines and Debit/Credit columns, signed amounts, Cr/Dr, date and amount formats, and files refused with a reason |
| `support/fake_subscriptions.dart` | A fake app store and purchase verifier, shared with the Patrol suite |
| `widget/responsive_test.dart` | Proportional sizing, and the fallback when ScreenUtil is not initialised |
| `widget/theme_scaling_test.dart` | Theme builds and type actually scales at non-1.0 factors |
| `widget/ui_smoke_test.dart` | Shared design-system widgets render in light and dark, including buttons under unbounded width |
| `tools/logo_test.dart` | **Not a test.** Regenerates the app icon PNG — destructive, see below |

## Conventions

- **Real Hive, fake Firestore.** The on-disk format is exactly what a
  regression would break, so Hive runs for real against a temp directory.
  Firestore is faked with `fake_cloud_firestore`; no test touches the network.
- **No wall-clock dependence.** Dates come from `fixedNow` in the fixtures, so
  a test cannot start failing overnight.
- **Drive sync explicitly.** Writes normally kick a background sync; tests
  construct `OfflineTransactionRepository(autoSync: false)` and call
  `syncNow()` themselves so assertions cannot race a fire-and-forget future.
- **Assert the reason, not the shape.** Prefer a `reason:` on assertions that
  encode a rule ("one account must never see another account's data") so a
  future failure explains itself.

## The `tools` tag

`tools/logo_test.dart` is a generator, not a regression test: it only passes
immediately after regenerating the committed PNG. It is tagged `tools` and
skipped by default (see `dart_test.yaml`) so a normal run stays a trustworthy
signal.

The generator is now safe to run: `AppLogo` draws the mark with a
`CustomPainter` rather than loading a PNG, so a headless run reproduces the
real artwork instead of a fallback placeholder. (It previously overwrote
~790 KB of real artwork with a ~6 KB flat image, which was easy to miss
because the dimensions stayed the same.)

It regenerates three exports, each scaled for the mask that will be applied
to it:

| Asset | Scale | Consumer |
|---|---|---|
| `app_icon_generated.png` | 0.66 tile | iOS icon, legacy splash |
| `app_adaptive_foreground.png` | 0.55, transparent | Android adaptive icon |
| `app_splash_icon.png` | 0.42, transparent | Android 12 splash |

```bash
flutter test --run-skipped --update-goldens test/tools
```

Afterwards, regenerate the platform resources:

```bash
dart run flutter_launcher_icons
dart pub add -d flutter_native_splash && dart run flutter_native_splash:create
dart pub remove flutter_native_splash   # it breaks the Android build if left in
```

## Adding tests

Put pure logic in `unit/`, anything that pumps a widget in `widget/`. Reuse the
fixtures rather than constructing models inline — a new required field should
break one file, not twenty.
