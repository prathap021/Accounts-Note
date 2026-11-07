# End-to-end tests (Patrol)

These tests drive the real app on a real Android device or emulator: real
screens, router, Hive database, shared preferences and platform plugins.
Only the network is replaced. Firebase Auth, Firestore, Cloud Functions and
connectivity are swapped for in-memory fakes, so a run never touches the
production Firebase project and works without secrets.

`test/` holds the fast unit and widget tests. This folder checks that whole
user flows still work from end to end.

## Running

One-off setup:

```bash
flutter pub global activate patrol_cli
export ANDROID_HOME="$HOME/Android/Sdk"     # wherever your SDK lives
# The SDK's adb must come first. Gradle installs the APK with it, and a second
# adb of a different version (e.g. /usr/bin/adb from apt) restarts the server
# mid-install: "Failed to install-write all apks", then "Total: 0".
export PATH="$ANDROID_HOME/platform-tools:$PATH:$HOME/.pub-cache/bin"
```

Start an emulator (or plug in a device), then:

```bash
# The whole suite, in one app session (see "One app session" below)
patrol test --dart-define-from-file=patrol_test/single_session.json

# One file
patrol test -t patrol_test/auth_test.dart --dart-define-from-file=patrol_test/single_session.json

# Hot-restart loop while writing a test
patrol develop -t patrol_test/auth_test.dart
```

Run one `patrol test` at a time per device. A second run reinstalls the
app, which kills the first one mid-test ("Process crashed").

`flutter test` does **not** run these tests. Patrol needs its native test
runner to drive the device.

A full run (71 flows) takes about 10 minutes on an emulator.

**If a run reports `Total: 0` after about 4–5 minutes**, the APK never
installed. Check
`build/app/outputs/androidTest-results/connected/debug/*.xml`: it will say
`Failed to install-write all apks`. Two causes have been seen:

- Two adb versions on `PATH` (see the export above).
- A stale Gradle daemon. Every install then fails, even though
  `adb install` by hand works. It shows up reliably after the adb server
  restarts (`adb kill-server`, an emulator reboot, switching adb binaries),
  and now and then between back-to-back runs. Run
  `(cd android && ./gradlew --stop)` and try again. That has fixed it every
  time.

**"A SemanticsHandle was active at the end of the test"**, on a test whose
steps all passed, is a rare race in Patrol itself, not in the app.
UiAutomator turns Android accessibility on, and if that lands in the moment
before Patrol starts ignoring it, Flutter counts one extra semantics handle
(see leancodepl/patrol#1474). It has shown up once in roughly 400 test
executions. Re-run the file.

### Screenshots

`screenshots_test.dart` is a tour of the main screens with realistic data
(salary, rent, everyday spending, two accounts, a credit card and budgets),
in light and dark mode: useful for design review and for store
screenshots. It is skipped in normal runs and only runs when built with
`screenshots.json`. Each time it reaches a screen it prints `SHOT:<name>`
and holds still for three seconds, so a script on the computer can grab
the emulator's screen when that line reaches logcat:

```bash
mkdir -p shots
adb logcat -c
adb logcat -v raw -s flutter:I | while IFS= read -r line; do
  case "$line" in *SHOT:*) n="${line##*SHOT:}"
    adb exec-out screencap -p > "shots/${n//[^A-Za-z0-9_-]/}.png";; esac
done &
patrol test -t patrol_test/screenshots_test.dart \
  --dart-define-from-file=patrol_test/screenshots.json
kill %1
```

### One app session for the whole run

The app is launched once and all tests run in that session, one after
another, the way `integration_test` runs (no Android Test Orchestrator, no
reinstall between tests).

Patrol 4.11 only serves more than one test per app process when it is
built with `PATROL_BS_COVERAGE=true`, which is what
[`single_session.json`](single_session.json) sets. That flag belongs to
Patrol's device-farm coverage feature. Its only other effect here is a
small line-coverage snapshot of the app's own code after each test.
Without the file, the first test passes and every later one fails with
`PatrolAppServiceClientException: Invalid response 500`, because the app
service accepts only one test per process. `launchApp` puts the device back to a fresh
install at the start of every test: it unmounts the previous test's app,
deletes every Hive box and clears shared preferences. Each test also gets
its own `FakeBackend`, so no account or cloud data carries over.

A new test that writes somewhere else on the device (a file, a new
plugin's storage) has to clear it in `_wipeDeviceStorage` too, or the tests
after it will see it.

## What is covered

[TEST_FLOWS.md](TEST_FLOWS.md) describes all 71 flows step by step, with
their starting state and expected results. In summary:

| File | Flows |
|---|---|
| `onboarding_test.dart` | First launch → intro pages → currency from location (native permission) → sign-in, shown only once; swiping between pages |
| `auth_test.dart` | Email sign-up → verification gate → dashboard; re-check on returning from the inbox app (native Home / reopen); duplicate address; switching account; validation; wrong then right password; session kept across restarts; password reset (address carried over, invalid address) |
| `transactions_test.dart` | Add income and expense from the dashboard and check balance, rows and cloud sync; amount validation; switching type changes categories; edit; delete with confirmation; offline entry queued, then synced on reconnect |
| `activity_test.dart` | History from another device pulled down; search with a total; type and category filters with a live preview; dashboard Income card opens a filtered Activity; swipe to delete with confirmation; last month's balance carried forward |
| `categories_budgets_test.dart` | Create a category (with validation) and spend in it; income and expense categories kept apart; remove a category; budget tracking against spend; overspent overall budget; delete a budget |
| `credit_cards_test.dart` | Add a card, keeping only the last 4 digits; card spend kept out of the cash balance; rename and delete; add a card from the payment picker while logging an expense |
| `settings_test.dart` | Currency, appearance (kept after a restart), display name; log out wipes the device and signing back in restores from the cloud; every Play currency, found by search; rating the app and checking for updates; a backup moving every transaction into another account |
| `navigation_reports_test.dart` | Every bottom tab; Android back goes Home first, then asks before exiting; back closes a pushed screen; Reports totals and range switch; a custom past period picked on the calendar (and cancelled), and the PDF / Excel / CSV export choice |
| `subscriptions_test.dart` | The free 14-a-day limit, shared by income and expense, and the upgrade prompt; the plan screen (prices, limits, status, today's use); subscribe, upgrade, restore; yearly plans; a cancelled plan keeping its limits until it ends |
| `everyday_test.dart` | Undo a delete; swipe right to edit; step through months and hide amounts; a pay-day month start; removing a used category moves entries to Other; clear all data |
| `automation_test.dart` | Recurring entries caught up on launch, pause and resume; Repeat from the add form; the daily reminder and its tap; a budget alert at 80% |
| `security_test.dart` | PIN lock on launch with a wrong-PIN countdown; fingerprint unlock (fake reader); Forgot PIN signs out |
| `accounts_test.dart` | Accounts with opening balances; a transfer that moves money without changing the total, and deleting it; an expense from an account and the remembered default |
| `insights_test.dart` | Spending by category with tap-through to Activity, and the Day period; the dashboard chart listing only the user's own categories; a receipt photo (fake gallery) shown full size; CSV import, and importing the same file again |

### Not covered, on purpose

- **Google and Apple sign-in.** They open the provider's own account UI and
  need a real account, so they cannot run unattended. The email path covers
  the shared post-sign-in flow.
- **Saving or sharing an exported report.** The PDF, Excel and CSV files
  end in the system share sheet, which differs between devices. The flows
  check the format choice; unit tests check the files.
- **The real store purchase sheet and server verification.** Google Play
  and the App Store need real store accounts, and verification calls their
  APIs. A fake store and verifier stand in (`test/support/fake_subscriptions.dart`);
  the app's purchase handling around them is real. The server-side limits
  are covered by the Firestore rules tests in `rules_test/`.

## Layout

| Path | Purpose |
|---|---|
| `support/fake_backend.dart` | The fakes. Auth keeps real accounts, rejects wrong passwords and reports verification and sign-out the way Firebase does. `FakeConnectivity` lets a test go offline on demand. |
| `support/test_app.dart` | `launchApp` / `launchSignedIn` boot the real app with the fakes plugged into its Riverpod providers. `restartApp` simulates a cold start. The `Seeding` extension writes server-side data the way the app writes it. |
| `support/steps.dart` | Reusable user steps (`signInWithEmail`, `addTransaction`, `openTab`…) and money formatting helpers, so tests read as flows. |

## Writing a new test

- Start from `launchSignedIn($)`, or from `launchApp($)` for signed-out
  flows. Put any data that should already exist in the cloud in its `seed:`
  callback. The app then pulls it down through the real sync path.
- Find widgets by what the user sees (`$('Save changes')`) and scope them
  when a label repeats (`$.sheet.$('Income')`, `$.dialog.$('Delete')`).
- Build expected amounts with `money()` / `balance()` rather than typing
  `'₹1,000.00'`, so a formatting change breaks one helper, not every test.
- For anything that settles asynchronously (sync, streams), wait with
  `waitUntilVisible()` or `$.eventually(...)`. Never use a fixed sleep.

### Things that behave differently on a device

These all failed at least once while the suite was being written:

- **The soft keyboard is real.** It covers buttons and shrinks lists. Type
  with `$.typeInto(field, text)`, which dismisses the keyboard and waits for
  it to close. Tap inside sheets with `$.tapInSheet(...)`.
- **Bare `scrollTo()` drags the first `Scrollable` in the whole tree.** On a
  pushed screen that can be the screen underneath. Use `$.reveal(target)`,
  which scrolls a built widget into view from its own scrollable, or pass
  `view:` explicitly.
- **Tap a chip, not its label.** A Material chip hit-tests as one box, so
  `$(ChoiceChip).$('Food')` is never tappable. Use
  `$(ChoiceChip).containing('Food')`.
- **Lazy lists dispose what scrolls away**, so `$(TextFormField).at(1)`
  changes meaning as the list scrolls. Find fields by label, or by
  `.first` / `.last` where the order is fixed.
- **Labels may be drawn in capitals** (`SectionLabel`, the balance card).
  Match the text as rendered: `'AVAILABLE BALANCE'`.
- **A framework error fails the test**, even a 5px overflow behind a sheet.
  That is deliberate. Fix the layout rather than silencing it.
