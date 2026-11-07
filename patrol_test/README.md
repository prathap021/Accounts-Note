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
patrol test                                         # the whole suite
patrol test -t patrol_test/auth_test.dart           # one file
patrol test --exclude patrol_test/settings_test.dart  # all but one file
patrol develop -t patrol_test/auth_test.dart        # hot-restart loop while writing a test
```

`flutter test` does **not** run these tests. Patrol needs its native test
runner to drive the device.

A full run takes 7 to 14 minutes on an emulator.

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

The stack trace about `Unknown package` at the very end of every run is
harmless. The orchestrator has already uninstalled the app when patrol_cli
tries to.

Each test gets a fresh install (`clearPackageData` plus the Android Test
Orchestrator), so no Hive box or preference carries over from one test to
the next.

## What is covered

[TEST_FLOWS.md](TEST_FLOWS.md) describes all 44 flows step by step, with
their starting state and expected results. In summary:

| File | Flows |
|---|---|
| `onboarding_test.dart` | First launch → intro pages → sign-in, shown only once; swiping between pages |
| `auth_test.dart` | Email sign-up → verification gate → dashboard; re-check on returning from the inbox app (native Home / reopen); duplicate address; switching account; validation; wrong then right password; session kept across restarts; password reset (address carried over, invalid address) |
| `transactions_test.dart` | Add income and expense from the dashboard and check balance, rows and cloud sync; amount validation; switching type changes categories; edit; delete with confirmation; offline entry queued, then synced on reconnect |
| `activity_test.dart` | History from another device pulled down; search with a total; type and category filters with a live preview; dashboard Income card opens a filtered Activity; swipe to delete with confirmation; last month's balance carried forward |
| `categories_budgets_test.dart` | Create a category (with validation) and spend in it; income and expense categories kept apart; remove a category; budget tracking against spend; overspent overall budget; delete a budget |
| `credit_cards_test.dart` | Add a card, keeping only the last 4 digits; card spend kept out of the cash balance; rename and delete; add a card from the payment picker while logging an expense |
| `settings_test.dart` | Currency, appearance (kept after a restart), display name; log out wipes the device and signing back in restores from the cloud; delete account (10-second guard, data and sign-in gone); cancelling the delete |
| `navigation_reports_test.dart` | Every bottom tab; Android back goes Home first, then asks before exiting; back closes a pushed screen; Reports totals and range switch |

### Not covered, on purpose

- **Google and Apple sign-in.** They open the provider's own account UI and
  need a real account, so they cannot run unattended. The email path covers
  the shared post-sign-in flow.
- **CSV export and "Backup & Delete".** These end in the system share sheet
  or a file save, which differs between devices. The backup step also reads
  `FirebaseAuth.instance` directly, which the fakes cannot reach.
- **Contribution payments.** These hand off to Stripe in a browser.

## Layout

| Path | Purpose |
|---|---|
| `support/fake_backend.dart` | The fakes. Auth keeps real accounts, rejects wrong passwords and reports verification, deletion and sign-out the way Firebase does. `FakeConnectivity` lets a test go offline on demand. |
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
