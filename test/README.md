# Test suite

## Running

```bash
flutter test                 # everything: 155 tests, ~9s
flutter analyze              # static analysis; run this too
```

A green run means the behaviours below still hold.

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
| `unit/data/transaction_filter_test.dart` | The Activity filter flow: type, category, payment method, date range, search |
| `unit/data/aggregation_test.dart` | The numbers behind the dashboard, Reports and Budgets |
| `unit/data/offline_sync_test.dart` | Offline writes, tombstoned deletes, replay de-duplication, failure and retry |
| `unit/data/category_repository_test.dart` | Category CRUD and the delete-vs-archive rule |
| `unit/data/budget_repository_test.dart` | Budget upsert keying, period scoping |
| `unit/state/settings_provider_test.dart` | Theme, currency and onboarding persistence |
| `unit/state/sync_state_test.dart` | The Synced / Syncing / Pending / Failed labels |
| `unit/email_verification_test.dart` | Who is gated behind verification — email/password yes, Google and Apple never |
| `unit/password_reset_test.dart` | Reset failure wording, including the unregistered-address case |
| `unit/delete_account_test.dart` | Account deletion for email accounts, and that cloud data goes first |
| `widget/transaction_tile_test.dart` | Activity row content, amount sign and colour, category icon, swipe-to-delete confirmation |
| `widget/sync_status_chip_test.dart` | Sync chip and failure banner states |
| `widget/verify_email_screen_test.dart` | Email-verification gate: address shown, resend cooldown, silent re-check on resume vs. reporting on manual check |
| `widget/forgot_password_sheet_test.dart` | Password reset: validation, carried-over email, confirmation |
| `widget/delete_progress_test.dart` | Account-deletion progress: step sequencing, optional backup step, non-dismissible |
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
