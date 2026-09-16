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
| `widget/transaction_tile_test.dart` | Activity row content, amount sign and colour, category icon, swipe-to-delete confirmation |
| `widget/sync_status_chip_test.dart` | Sync chip and failure banner states |
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

> **Do not run it to "fix" a failing golden.**
>
> ```bash
> flutter test --run-skipped --update-goldens test/tools   # DESTRUCTIVE
> ```
>
> It overwrites `assets/branding/app_icon_generated.png` with whatever
> `AppLogo` renders *in the test environment*. Headless tests do not load the
> real `assets/branding/app_logo.png`, so `AppLogo` falls back to a plain
> coloured placeholder and the command replaces ~790 KB of real artwork with a
> ~6 KB flat image. The file keeps its 1024x1024 dimensions, so the damage is
> easy to miss in a diff — check the byte size.
>
> If it has already happened:
>
> ```bash
> git checkout -- assets/branding/app_icon_generated.png
> ```
>
> Only run it deliberately, on a machine where the branding asset loads, and
> inspect the resulting PNG before committing it.

## Adding tests

Put pure logic in `unit/`, anything that pumps a widget in `widget/`. Reuse the
fixtures rather than constructing models inline — a new required field should
break one file, not twenty.
