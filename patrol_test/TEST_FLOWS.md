# End-to-end test flows

This document lists every user flow the Patrol suite in `patrol_test/`
covers: where each flow starts, what the test does, and what it checks.
For how to run the suite and how the test harness works, see
[README.md](README.md).

**Last full run:** 69 of 71 passed, 8 Nov 2026, on the `Pixel` Android emulator
(Android 7.1.1, API 25), in one app session, in about 9 minutes, after the
colourful redesign. The two failures (TXN-04, TXN-06) checked the balance
after scrolling down to a row; the taller dashboard header had scrolled it
out of view. The tests now scroll back up to it, and `transactions_test.dart`
passes in full (6 of 6). (`screenshots_test.dart` is reported as skipped: it
only runs when asked for; see the README.)

## How to read this

- Each flow has an **ID** (`AUTH-06`), the **test file**, and the **test
  name** exactly as it appears in the run output. Run one file with
  `patrol test -t patrol_test/<file>`.
- All flows run one after another in a single app session, like
  `integration_test`: the app is launched once, not reinstalled per test
  (run with `--dart-define-from-file=patrol_test/single_session.json`).
  Each test first wipes the local ledger and preferences, so it still
  starts from the same state as a fresh install.
- **Starts from** is the state before the first step. Unless it says
  otherwise, that is a freshly wiped app with onboarding already seen.
- **Step** is what the user does. **Expected** is what the test asserts.
  Assertions marked _(cloud)_ are checked against the fake Firestore, not
  the screen.
- **Native** flows use Patrol's device automation (the Home button,
  reopening the app, Android back) on top of in-app taps.

## Shared test data

| Item | Value |
|---|---|
| Returning user | **Asha Rao**, `asha@example.com`, password `correct-horse`, email verified |
| Her categories | The app's defaults. Expense: Food, Transport, Shopping, Bills, Entertainment, Health, Education, Other. Income: Salary, Business, Investment, Other |
| Currency | INR (₹) unless the flow changes it |
| Network | Online unless the flow switches it off |
| "Cloud" | In-memory fakes of Firebase Auth and Firestore. Nothing reaches the real project |
| Store | A fake app store selling the three plans at $1.00, $2.00 and $3.00 (a dollar storefront). Purchases go through at once, and a fake verifier writes the plan to the profile the way the `verifySubscription` Cloud Function does |

Seeded transactions are written to the cloud before launch, as if logged
on another device. The app pulls them down through its normal sync.

## Flow index

| ID | Flow | File | Native |
|---|---|---|:-:|
| [ONB-01](#onb-01--first-launch-shows-onboarding-once) | First launch shows onboarding once | `onboarding_test.dart` | ✓ |
| [ONB-02](#onb-02--swiping-between-intro-pages) | Swiping between intro pages | `onboarding_test.dart` | |
| [AUTH-01](#auth-01--new-email-account-must-confirm-its-address) | New email account must confirm its address | `auth_test.dart` | |
| [AUTH-02](#auth-02--returning-from-the-inbox-re-checks-verification) | Returning from the inbox re-checks verification | `auth_test.dart` | ✓ |
| [AUTH-03](#auth-03--an-address-already-in-use-is-refused) | An address already in use is refused | `auth_test.dart` | |
| [AUTH-04](#auth-04--switching-account-from-the-verification-screen) | Switching account from the verification screen | `auth_test.dart` | |
| [AUTH-05](#auth-05--sign-in-form-validation) | Sign-in form validation | `auth_test.dart` | |
| [AUTH-06](#auth-06--wrong-password-then-right-password) | Wrong password, then right password | `auth_test.dart` | |
| [AUTH-07](#auth-07--session-survives-a-restart) | Session survives a restart | `auth_test.dart` | |
| [AUTH-08](#auth-08--password-reset) | Password reset | `auth_test.dart` | |
| [AUTH-09](#auth-09--password-reset-rejects-an-invalid-address) | Password reset rejects an invalid address | `auth_test.dart` | |
| [TXN-01](#txn-01--log-income-and-an-expense) | Log income and an expense | `transactions_test.dart` | |
| [TXN-02](#txn-02--an-amount-is-required) | An amount is required | `transactions_test.dart` | |
| [TXN-03](#txn-03--switching-type-switches-categories) | Switching type switches categories | `transactions_test.dart` | |
| [TXN-04](#txn-04--edit-a-transaction) | Edit a transaction | `transactions_test.dart` | |
| [TXN-05](#txn-05--delete-a-transaction-from-its-edit-screen) | Delete a transaction from its edit screen | `transactions_test.dart` | |
| [TXN-06](#txn-06--offline-entry-syncs-on-reconnect) | Offline entry syncs on reconnect | `transactions_test.dart` | |
| [ACT-01](#act-01--history-from-another-device-is-listed) | History from another device is listed | `activity_test.dart` | |
| [ACT-02](#act-02--search) | Search | `activity_test.dart` | |
| [ACT-03](#act-03--filter-by-type) | Filter by type | `activity_test.dart` | |
| [ACT-04](#act-04--filter-by-category) | Filter by category | `activity_test.dart` | |
| [ACT-05](#act-05--dashboard-income-card-opens-filtered-activity) | Dashboard Income card opens filtered Activity | `activity_test.dart` | |
| [ACT-06](#act-06--swipe-to-delete) | Swipe to delete | `activity_test.dart` | |
| [ACT-07](#act-07--balance-carries-over-from-last-month) | Balance carries over from last month | `activity_test.dart` | |
| [CAT-01](#cat-01--create-a-category-and-spend-in-it) | Create a category and spend in it | `categories_budgets_test.dart` | |
| [CAT-02](#cat-02--income-and-expense-categories-are-separate) | Income and expense categories are separate | `categories_budgets_test.dart` | |
| [CAT-03](#cat-03--remove-a-category) | Remove a category | `categories_budgets_test.dart` | |
| [BUD-01](#bud-01--category-budget-tracks-spending) | Category budget tracks spending | `categories_budgets_test.dart` | |
| [BUD-02](#bud-02--overspent-overall-budget) | Overspent overall budget | `categories_budgets_test.dart` | |
| [BUD-03](#bud-03--delete-a-budget) | Delete a budget | `categories_budgets_test.dart` | |
| [CARD-01](#card-01--add-a-card-last-4-digits-only) | Add a card, last 4 digits only | `credit_cards_test.dart` | |
| [CARD-02](#card-02--card-spending-stays-out-of-the-cash-balance) | Card spending stays out of the cash balance | `credit_cards_test.dart` | |
| [CARD-03](#card-03--rename-and-delete-a-card) | Rename and delete a card | `credit_cards_test.dart` | |
| [CARD-04](#card-04--add-a-card-while-logging-an-expense) | Add a card while logging an expense | `credit_cards_test.dart` | |
| [SET-01](#set-01--change-currency) | Change currency | `settings_test.dart` | |
| [SET-02](#set-02--change-appearance) | Change appearance | `settings_test.dart` | |
| [SET-03](#set-03--edit-display-name) | Edit display name | `settings_test.dart` | |
| [SET-04](#set-04--log-out-and-restore-from-the-cloud) | Log out and restore from the cloud | `settings_test.dart` | |
| [SET-05](#set-05--any-play-currency-found-by-search) | Any Play currency, found by search | `settings_test.dart` | |
| [SET-06](#set-06--rate-the-app-and-check-for-updates) | Rate the app and check for updates | `settings_test.dart` | |
| [SET-07](#set-07--move-transactions-to-another-account-with-a-backup) | Move transactions to another account with a backup | `settings_test.dart` | |
| [NAV-01](#nav-01--bottom-navigation-tabs) | Bottom navigation tabs | `navigation_reports_test.dart` | |
| [NAV-02](#nav-02--android-back-from-a-tab) | Android back from a tab | `navigation_reports_test.dart` | ✓ |
| [NAV-03](#nav-03--android-back-from-a-pushed-screen) | Android back from a pushed screen | `navigation_reports_test.dart` | ✓ |
| [REP-01](#rep-01--reports-totals-and-ranges) | Reports totals and ranges | `navigation_reports_test.dart` | |
| [REP-02](#rep-02--custom-period-from-past-history-and-export) | Custom period from past history, and export | `navigation_reports_test.dart` | |
| [SUB-01](#sub-01--daily-limit-then-upgrade) | Daily limit, then upgrade | `subscriptions_test.dart` | |
| [SUB-02](#sub-02--plans-status-and-todays-use) | Plans, status and today's use | `subscriptions_test.dart` | |
| [SUB-03](#sub-03--upgrade-a-plan) | Upgrade a plan | `subscriptions_test.dart` | |
| [SUB-04](#sub-04--restore-after-a-reinstall) | Restore after a reinstall | `subscriptions_test.dart` | |
| [SUB-05](#sub-05--cancelled-plan-keeps-its-limits-until-it-ends) | Cancelled plan keeps its limits until it ends | `subscriptions_test.dart` | |
| [SUB-06](#sub-06--yearly-plans) | Yearly plans | `subscriptions_test.dart` | |
| [EVD-01](#evd-01--a-deleted-entry-comes-back-with-undo) | A deleted entry comes back with Undo | `everyday_test.dart` | |
| [EVD-02](#evd-02--swipe-right-to-edit) | Swipe right to edit | `everyday_test.dart` | |
| [EVD-03](#evd-03--step-through-months-and-hide-amounts) | Step through months and hide amounts | `everyday_test.dart` | |
| [EVD-04](#evd-04--pay-day-month-start) | Pay-day month start | `everyday_test.dart` | |
| [EVD-05](#evd-05--removing-a-used-category-moves-its-entries-to-other) | Removing a used category moves its entries to Other | `everyday_test.dart` | |
| [EVD-06](#evd-06--clear-all-data) | Clear all data | `everyday_test.dart` | |
| [AUTO-01](#auto-01--recurring-entries-catch-up-and-pause) | Recurring entries catch up, and pause | `automation_test.dart` | |
| [AUTO-02](#auto-02--repeat-from-the-add-form) | Repeat from the add form | `automation_test.dart` | |
| [AUTO-03](#auto-03--daily-reminder) | Daily reminder | `automation_test.dart` | |
| [AUTO-04](#auto-04--budget-alert-at-80) | Budget alert at 80% | `automation_test.dart` | |
| [SEC-01](#sec-01--pin-lock-on-launch) | PIN lock on launch | `security_test.dart` | |
| [SEC-02](#sec-02--fingerprint-unlock) | Fingerprint unlock | `security_test.dart` | |
| [SEC-03](#sec-03--forgot-pin) | Forgot PIN | `security_test.dart` | |
| [ACC-01](#acc-01--accounts-opening-balances-and-transfers) | Accounts, opening balances and transfers | `accounts_test.dart` | |
| [ACC-02](#acc-02--an-expense-from-an-account) | An expense from an account | `accounts_test.dart` | |
| [INS-01](#ins-01--spending-by-category-tap-through-and-day) | Spending by category, tap-through, and Day | `insights_test.dart` | |
| [INS-02](#ins-02--receipt-photo) | Receipt photo | `insights_test.dart` | |
| [INS-03](#ins-03--import-from-csv) | Import from CSV | `insights_test.dart` | |
| [INS-04](#ins-04--the-dashboard-chart-shows-only-your-categories) | The dashboard chart shows only your categories | `insights_test.dart` | |

71 flows in total. NAV-02 and NAV-03 are skipped automatically when not
running on Android.

---

## 1. Onboarding

### ONB-01 · First launch shows onboarding once

`onboarding_test.dart` › _first launch walks through onboarding to sign-in, and only once_
**Starts from:** freshly wiped app, onboarding never seen.

| # | Step | Expected |
|---|---|---|
| 1 | Open the app | "Welcome to Accounts Note" page, listing "Log in seconds" |
| 2 | Tap **Next** | "Privacy first" page |
| 3 | Tap **Get started** | "Set your currency", explaining the location stays on the phone |
| 4 | **Use my location**, then allow it in the system dialog _(native)_ | The currency is set from the country ("Currency set to …"), or, where the emulator cannot name its country, "Couldn't find your location" and the region's currency is kept |
| 5 | Continue | Sign-in screen ("Continue with Email") |
| 6 | Close the app and open it again | Sign-in screen straight away. The intro is not shown again |

### ONB-02 · Swiping between intro pages

`onboarding_test.dart` › _swiping through the intro pages works as well as the buttons_
**Starts from:** freshly wiped app, onboarding never seen.

| # | Step | Expected |
|---|---|---|
| 1 | Swipe the first page to the left | "Privacy first" page, offering **Get started** |

## 2. Sign up, sign in and password reset

### AUTH-01 · New email account must confirm its address

`auth_test.dart` › _Sign up a new email account must confirm its address before reaching the app_
**Starts from:** sign-in screen, no account.

| # | Step | Expected |
|---|---|---|
| 1 | **Continue with Email** → **Sign up** → enter `new.person@example.com` and a password → **Create account** | "Confirm your email" screen naming the address. **Resend** shows a countdown. Exactly one verification email sent |
| 2 | Tap **I've confirmed it** without opening the link | Error toast: "That address isn't confirmed yet…". Stays on the screen |
| 3 | Open the link (simulated), then tap **I've confirmed it** | Dashboard opens |
| 4 | — | _(cloud)_ Profile created with all 12 default categories |

### AUTH-02 · Returning from the inbox re-checks verification

`auth_test.dart` › _Sign up returning from the inbox app re-checks verification without a tap_ · **Native**
**Starts from:** sign-in screen, no account.

| # | Step | Expected |
|---|---|---|
| 1 | Sign up with `inbox.return@example.com` | "Confirm your email" screen |
| 2 | Press the device **Home** button, open the link in the mail app (simulated), reopen the app | Dashboard opens without tapping anything |

### AUTH-03 · An address already in use is refused

`auth_test.dart` › _Sign up an address that already has an account is refused_
**Starts from:** sign-in screen. Asha's account exists.

| # | Step | Expected |
|---|---|---|
| 1 | Sign up with `asha@example.com` | "An account already exists with this email." Stays on "Create your account" |

### AUTH-04 · Switching account from the verification screen

`auth_test.dart` › _Sign up choosing a different account from the verification screen signs out_
**Starts from:** sign-in screen, no account.

| # | Step | Expected |
|---|---|---|
| 1 | Sign up with a mistyped address | "Confirm your email" screen |
| 2 | Tap **Use a different account** | Back on the sign-in screen |

### AUTH-05 · Sign-in form validation

`auth_test.dart` › _Sign in the form explains what is wrong before contacting the server_
**Starts from:** sign-in screen.

| # | Step | Expected |
|---|---|---|
| 1 | **Continue with Email** → **Sign in** with both fields empty | "Enter a valid email" and "Password must be at least 6 characters" |

### AUTH-06 · Wrong password, then right password

`auth_test.dart` › _Sign in a wrong password is rejected, then the right one signs in_
**Starts from:** sign-in screen. Asha's account exists.

| # | Step | Expected |
|---|---|---|
| 1 | Sign in as `asha@example.com` with a wrong password | "Incorrect email or password." Stays on the form |
| 2 | Correct the password → **Sign in** | Dashboard greets "Asha Rao" |

### AUTH-07 · Session survives a restart

`auth_test.dart` › _Sign in a signed-in session survives the app being closed_
**Starts from:** sign-in screen. Asha's account exists.

| # | Step | Expected |
|---|---|---|
| 1 | Sign in as Asha | Dashboard |
| 2 | Close the app and open it again | Dashboard straight away, with no sign-in screen |

### AUTH-08 · Password reset

`auth_test.dart` › _Password reset the address typed on the sign-in form is carried into the reset sheet_
**Starts from:** sign-in screen. Asha's account exists.

| # | Step | Expected |
|---|---|---|
| 1 | **Continue with Email** → type `asha@example.com` → **Forgot password?** | "Reset your password" sheet |
| 2 | **Send reset link** without retyping the address | "Check your inbox: We sent a reset link to asha@example.com…" _(cloud)_ Exactly one reset requested, for that address |
| 3 | **Done** | Sheet closes. Back on "Sign in with email" |

### AUTH-09 · Password reset rejects an invalid address

`auth_test.dart` › _Password reset an invalid address is caught in the sheet_
**Starts from:** sign-in screen.

| # | Step | Expected |
|---|---|---|
| 1 | **Continue with Email** → **Forgot password?** → type `not-an-email` → **Send reset link** | "Enter a valid email" in the sheet. _(cloud)_ No reset requested |

## 3. Transactions

All flows start signed in as Asha.

### TXN-01 · Log income and an expense

`transactions_test.dart` › _logging income and an expense updates the dashboard and syncs to the cloud_
**Starts from:** empty ledger ("No transactions yet").

| # | Step | Expected |
|---|---|---|
| 1 | **Add** → **Income** → 5000, **Salary**, note "November pay" → **Add transaction** | "Transaction added" |
| 2 | **Add** → **Expense** → 250, **Food**, note "Groceries" → **Add transaction** | "Transaction added" |
| 3 | — | Balance ₹ 4,750.00. Income ₹5,000.00 and Expenses ₹250.00. Today's activity lists +₹5,000.00 and −₹250.00 |
| 4 | — | _(cloud)_ Both entries saved |

### TXN-02 · An amount is required

`transactions_test.dart` › _an expense cannot be saved without a valid amount_

| # | Step | Expected |
|---|---|---|
| 1 | **Add** → **Expense** → **Add transaction** with no amount | "Enter a valid amount". Stays on "Add expense". _(cloud)_ Nothing saved |

### TXN-03 · Switching type switches categories

`transactions_test.dart` › _switching the form to income offers income categories instead_

| # | Step | Expected |
|---|---|---|
| 1 | **Add** → **Expense** | Expense categories offered (e.g. Food) |
| 2 | Switch the form to **Income** | Title "Add income". Salary offered, Food gone |

### TXN-04 · Edit a transaction

`transactions_test.dart` › _editing a transaction changes it everywhere_

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: 120, **Transport**, "Cab home" | Listed under Today's activity |
| 2 | Tap it | "Edit transaction", prefilled with 120.00 |
| 3 | Change the amount to 180 and the note to "Cab home (late night)" → **Save changes** | "Transaction updated". Row shows −₹180.00. Balance -₹ 180.00 |
| 4 | — | _(cloud)_ One entry of 180, updated in place rather than duplicated |

### TXN-05 · Delete a transaction from its edit screen

`transactions_test.dart` › _deleting a transaction from its edit screen asks first, then removes it_

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: 75, **Food**, "Coffee" | _(cloud)_ Saved |
| 2 | Open it → delete icon | "Delete transaction?" |
| 3 | **Cancel** | Still on "Edit transaction" |
| 4 | Delete icon → **Delete** | Back on the dashboard: "No transactions yet". _(cloud)_ Removed |

### TXN-06 · Offline entry syncs on reconnect

`transactions_test.dart` › _entries made offline are kept on the device and sync when back online_
**Starts from:** device offline.

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: 60, **Food**, "Chai on the train" | Saved at once. Row marked "Syncing". Balance -₹ 60.00. _(cloud)_ Nothing yet |
| 2 | Open **Activity** | Sync chip reads "Pending · 1" |
| 3 | Device comes back online | _(cloud)_ Entry arrives. Chip reads "Synced" and the "Syncing" mark is gone |

## 4. Activity

ACT-01 to ACT-06 start signed in as Asha, with this history already in
the cloud, all dated today:

| Entry | Type | Amount | Category |
|---|---|---|---|
| Monthly salary | Income | 50,000 | Salary |
| Team lunch | Expense | 450 | Food |
| Metro card top-up | Expense | 120 | Transport |

### ACT-01 · History from another device is listed

`activity_test.dart` › _history logged on another device is pulled down and listed_

| # | Step | Expected |
|---|---|---|
| 1 | Open the app | Balance ₹ 49,430.00 |
| 2 | Open **Activity** | All three entries listed. Sync chip "Synced" |

### ACT-02 · Search

`activity_test.dart` › _search narrows the list and shows the total for what matched_

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → type "lunch" in search | Only "Team lunch", with a "Total spent" card |
| 2 | Clear the search | All entries back |

### ACT-03 · Filter by type

`activity_test.dart` › _filtering by type previews the total before applying, then clears_

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → filter icon | "Filter activity" sheet: "Tap any filter to see its total here." |
| 2 | Choose **Expense** | Sheet previews ₹570.00 |
| 3 | **Apply** | "Total spent" card shows ₹570.00. Salary hidden. Removable "Expense" chip shown |
| 4 | **Clear all** | All entries back, no filter chips |

### ACT-04 · Filter by category

`activity_test.dart` › _filtering by category narrows to that category alone_

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → filter icon → **Transport** → **Apply** | Only "Metro card top-up" |

### ACT-05 · Dashboard Income card opens filtered Activity

`activity_test.dart` › _tapping Income on the dashboard opens Activity filtered to income_

| # | Step | Expected |
|---|---|---|
| 1 | Tap the **Income** card on the dashboard | Activity with "Total received", showing only "Monthly salary" |
| 2 | Go back to **Home** | Balance still ₹ 49,430.00. The filter applies to Activity only |

### ACT-06 · Swipe to delete

`activity_test.dart` › _swiping a row away asks for confirmation before deleting it_

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → swipe "Team lunch" left | "Delete this transaction?" |
| 2 | **Cancel** | Row returns |
| 3 | Swipe again → **Delete** | "Team lunch" gone. "Metro card top-up" still listed. _(cloud)_ Only that entry deleted |

### ACT-07 · Balance carries over from last month

`activity_test.dart` › _the dashboard balance carries over last month's leftover_
**Starts from:** signed in. Cloud holds 10,000 income (Salary) and 6,000
expense (Bills) from last month, plus a 500 Food expense "Dinner" today.

| # | Step | Expected |
|---|---|---|
| 1 | Open the app | Balance ₹ 3,500.00, with a "carried over" caption |
| 2 | Look at Today's activity | "Dinner" listed. Last month's Bills entry is not |

## 5. Categories and budgets

All flows start signed in as Asha.

### CAT-01 · Create a category and spend in it

`categories_budgets_test.dart` › _Categories a new category can be created and used for an expense_

| # | Step | Expected |
|---|---|---|
| 1 | Profile → **Manage categories** → **New category** → **Create category** with no name | "Give this category a name" |
| 2 | Name it "Pets" → **Create category** | "Pets" listed |
| 3 | Back to the dashboard → add an expense: 900, **Pets**, "Vet visit" | Entry listed under Pets |

### CAT-02 · Income and expense categories are separate

`categories_budgets_test.dart` › _Categories income and expense categories are kept apart_

| # | Step | Expected |
|---|---|---|
| 1 | **Manage categories** | Expense tab: Food listed, Salary not |
| 2 | **Income** tab | Salary listed, Food not |

### CAT-03 · Remove a category

`categories_budgets_test.dart` › _Categories removing a category asks first and takes it off the list_

| # | Step | Expected |
|---|---|---|
| 1 | **Manage categories** → remove icon on "Education" | 'Remove "Education"?' |
| 2 | **Remove** | "Education" gone from the list |

### BUD-01 · Category budget tracks spending

`categories_budgets_test.dart` › _Budgets a category budget tracks spending against its limit_

| # | Step | Expected |
|---|---|---|
| 1 | **Budgets** | "No budgets this month" |
| 2 | **New budget** → **Save budget** with no limit | "Enter a limit greater than zero" |
| 3 | Category **Food**, limit 1000 → **Save budget** | "₹0.00 of ₹1,000.00" |
| 4 | **Home** → add an expense: 250, **Food** → **Budgets** | "₹250.00 of ₹1,000.00", 25%, "₹750.00 left" |

### BUD-02 · Overspent overall budget

`categories_budgets_test.dart` › _Budgets an overspent overall budget says by how much_
**Starts from:** a 1,500 Shopping expense this month.

| # | Step | Expected |
|---|---|---|
| 1 | **Budgets** → **New budget** → limit 1000, no category → **Save budget** | "Overall budget", "₹500.00 over" |

### BUD-03 · Delete a budget

`categories_budgets_test.dart` › _Budgets deleting a budget asks first_

| # | Step | Expected |
|---|---|---|
| 1 | Create an overall budget of 2000 | "Overall budget" |
| 2 | Delete icon → **Delete** | "Delete this budget?", then "No budgets this month" |

## 6. Credit cards

All flows start signed in as Asha, with no cards.

### CARD-01 · Add a card, last 4 digits only

`credit_cards_test.dart` › _a card is added with only its last four digits_

| # | Step | Expected |
|---|---|---|
| 1 | Profile → **Credit cards** | "No credit cards yet" |
| 2 | **Add card** → paste `4111111111111111` into "Last 4 digits" | Field keeps only `4111` |
| 3 | Name "HDFC Millennia", last 4 `4242`, limit 50000 → **Add card** | Card listed. Empty state gone, **Add card** button appears |

### CARD-02 · Card spending stays out of the cash balance

`credit_cards_test.dart` › _card spending is tracked separately from the cash balance_

| # | Step | Expected |
|---|---|---|
| 1 | Add a card "Travel Card" (last 4 `1234`) | Card listed |
| 2 | Dashboard → add income: 3000, **Salary** | Balance ₹ 3,000.00 |
| 3 | Add an expense: 1200, **Shopping**, "New shoes", payment method **Travel Card** | Balance stays ₹ 3,000.00. Credit cards section: "₹1,200.00 charged this month" |
| 4 | — | _(cloud)_ Saved with the Credit Card payment method, linked to the card |

### CARD-03 · Rename and delete a card

`credit_cards_test.dart` › _a card can be renamed and deleted from its options menu_

| # | Step | Expected |
|---|---|---|
| 1 | Add a card "Old Name" | Card listed |
| 2 | Card options → **Edit** → rename to "Renamed Card" → save | "Renamed Card" listed, "Old Name" gone |
| 3 | Card options → **Delete** → **Delete** | 'Delete "Renamed Card"?', then "No credit cards yet" |

### CARD-04 · Add a card while logging an expense

`credit_cards_test.dart` › _a card can be added from the payment method picker mid-expense_

| # | Step | Expected |
|---|---|---|
| 1 | **Add** → **Expense** → 499 → **Payment method** → **Add your first credit card** | "New credit card" form |
| 2 | Name "Amazon Pay" → **Add card** | Back on "Add expense", paying with Amazon Pay |
| 3 | **Add transaction** | "Transaction added". Dashboard: "₹499.00 charged this month" |

## 7. Settings and account

All flows start signed in as Asha.

### SET-01 · Change currency

`settings_test.dart` › _changing the currency reformats every amount_
**Starts from:** 1,200 income this month (balance ₹ 1,200.00).

| # | Step | Expected |
|---|---|---|
| 1 | Profile → **Currency** → **US Dollar** | Setting reads "US Dollar · $" |
| 2 | Back to the dashboard | Balance $ 1,200.00. No ₹ amount left |

### SET-02 · Change appearance

`settings_test.dart` › _the chosen appearance applies at once and survives a restart_

| # | Step | Expected |
|---|---|---|
| 1 | — | Theme follows the system |
| 2 | Profile → **Appearance** → **Dark** | App switches to dark at once |
| 3 | Close the app and open it again | Still dark |

### SET-03 · Edit display name

`settings_test.dart` › _editing the display name updates the greeting_

| # | Step | Expected |
|---|---|---|
| 1 | — | Dashboard greets "Asha Rao" |
| 2 | Profile → **Edit name** → "Asha R." → **Save** | Profile shows "Asha R." and stays on Settings |
| 3 | Back to the dashboard | Greets "Asha R." |

Step 2 guards a fixed bug: saving used to throw the user out of
Settings (see [Bugs these flows found](#bugs-these-flows-found)).

### SET-04 · Log out and restore from the cloud

`settings_test.dart` › _logging out clears the device, and signing back in restores from the cloud_

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: 340, **Bills**, "Electricity" | _(cloud)_ Saved |
| 2 | Profile → **Log out** → **Log out** | "Log out?", then the sign-in screen |
| 3 | Sign in as Asha again | Dashboard shows "Electricity" and a balance of -₹ 340.00, rebuilt from the cloud |

### SET-05 · Any Play currency, found by search

`settings_test.dart` › _every Play currency can be found and used, with its own format_
**Starts from:** ₹1,500 salary this month.

| # | Step | Expected |
|---|---|---|
| 1 | Profile → **Currency** | The full list: "Suggested" (current, the phone's own, then popular ones), then "All currencies" |
| 2 | Search "yen" → **Japanese Yen** | "Japanese Yen · ¥" |
| 3 | Back to the dashboard | The balance reads "¥ 1,500", with no decimals, as the yen has none |

### SET-06 · Rate the app and check for updates

`settings_test.dart` › _About offers rating the app and checking for updates_

| # | Step | Expected |
|---|---|---|
| 1 | Profile → About | "Rate Accounts Note" ("Leave a review on Google Play") and "Check for updates" |
| 2 | Tap **Check for updates** | "Updates are only available for the Google Play version of the app.": the test build is not installed from Play |

### SET-07 · Move transactions to another account with a backup

`settings_test.dart` › _a backup moves every transaction into another account_
**Starts from:** Asha signed in, with 25,000 salary ("October salary") and a 640 Food expense ("Groceries"); a second account, Ravi, exists.

| # | Step | Expected |
|---|---|---|
| 1 | Profile → **Back up now** | "Backup ready with 2 transactions."; the file `accounts_note_backup_<date>.json` goes to the share sheet |
| 2 | **Log out** → sign in as Ravi | Ravi's empty dashboard |
| 3 | Profile → **Import a backup** → pick the file | "Import this backup?" with "2 transactions" |
| 4 | **Import** | "Imported 2 transactions." |
| 5 | Open **Activity** | "October salary" and "Groceries" are in Ravi's account. _(cloud)_ Asha still has hers |

The share sheet and file picker are the system's; a fake hands the shared
file to the picker, and a fake server stands in for `createBackup` /
`importBackup` (their signing and merging are tested on the Firestore
emulator in `functions/test/`).

## 8. Navigation and reports

All flows start signed in as Asha.

### NAV-01 · Bottom navigation tabs

`navigation_reports_test.dart` › _every tab in the bottom bar opens its screen_

| # | Step | Expected |
|---|---|---|
| 1 | Tap **Activity**, **Budgets**, **Reports**, **Home** in turn | Each opens its screen: "Your ledger", "No budgets this month", "Nothing to report yet", then the dashboard |

### NAV-02 · Android back from a tab

`navigation_reports_test.dart` › _Android back returns to Home first, then asks before leaving_ · **Native**, Android only

| # | Step | Expected |
|---|---|---|
| 1 | Open **Reports** → press the device **Back** button | Dashboard, with no exit prompt |
| 2 | Press **Back** again | "Press back again to exit". The app stays open |

### NAV-03 · Android back from a pushed screen

`navigation_reports_test.dart` › _Android back closes a pushed screen instead of the app_ · **Native**, Android only

| # | Step | Expected |
|---|---|---|
| 1 | Open the profile (Settings) → press the device **Back** button | Dashboard, with no exit prompt |

### REP-01 · Reports totals and ranges

`navigation_reports_test.dart` › _Reports totals the period and switches ranges_
**Starts from:** 20,000 income (Salary) and 8,000 expense (Bills) this month.

| # | Step | Expected |
|---|---|---|
| 1 | Open **Reports** | "This month so far": Income ₹20,000.00, Expenses ₹8,000.00, plus the "Income vs expenses" chart |
| 2 | Switch to **Year** | "This year so far", still including the ₹20,000.00 |

### REP-02 · Custom period from past history, and export

`navigation_reports_test.dart` › _Reports cover a past period picked on the calendar, and export it_
**Starts from:** last March: 15,000 income (10 Mar) and 6,000 expense (31 Mar, 9 pm); this month: 1,234 income.

| # | Step | Expected |
|---|---|---|
| 1 | Open **Reports** → tap **Custom** | The calendar, "Select report period" |
| 2 | Close it without choosing | Still "This month so far" with ₹1,234.00 |
| 3 | **Custom** → switch to typing → 1 March to 31 March last year → **Generate** | "Custom range", "1 Mar – 31 Mar" of last year, ₹15,000.00 and ₹6,000.00 (the last day counts in full); this month's ₹1,234.00 is not included |
| 4 | Tap **Export report** | "Export report" for the period, "· 2 transactions", with PDF document, Excel spreadsheet and CSV file |

## 9. Subscriptions and daily limits

All flows start signed in as Asha. "Today's count" is the server's per-day
counter, seeded as if entries had already been uploaded. The Firestore
rules that enforce the limits on the server are tested separately, in
`rules_test/`.

### SUB-01 · Daily limit, then upgrade

`subscriptions_test.dart` › _a free user gets 14 a day in any mix, then is offered the plans_
**Starts from:** Free plan, 8 income and 5 expenses already counted today.

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: ₹450, Food | "Transaction added". That was the 14th, the last one free |
| 2 | Tap **Add** → **Income** | "Daily limit reached", "You've added 14 of 14 entries today (income and expense together) on the Free plan. Upgrade for up to 200 a day…". The form does not open |
| 3 | **Not now** → **Add** → **Expense** | "Daily limit reached" again: one allowance for both types |
| 4 | **See plans** → **Subscribe** on Basic | "You're on Basic. Thank you!" |
| 5 | Back, add an expense: ₹120, Transport | "Transaction added": Basic allows 60 a day |

### SUB-02 · Plans, status and today's use

`subscriptions_test.dart` › _the plan screen shows every plan, the current status and today's use_
**Starts from:** Free plan, 2 income and 5 expenses counted today.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Subscription** | "Free", "No subscription", today "7 of 14", "2 income · 5 expense" |
| 2 | Scroll through the plans | Basic $1.00, Standard $2.00, Premium $3.00, each with its transactions a month (1,800, 3,600, 6,000), "Income or expense, in any mix" |
| 3 | **Subscribe** on Premium | "You're on Premium. Thank you!". _(store)_ one purchase, acknowledged once verified |
| 4 | Back to the top | "Renews on …", today "7 of 200" |
| 5 | Back to Settings | The tile reads "Premium · 6,000 transactions a month" |

### SUB-03 · Upgrade a plan

`subscriptions_test.dart` › _upgrading replaces the current plan in the store_
**Starts from:** on Basic, bought on this device.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Subscription** | Basic shows "Current plan" |
| 2 | **Upgrade** on Standard | "You're on Standard. Thank you!". _(store)_ the purchase replaced the Basic subscription, as Google Play needs to switch plans in place |

### SUB-04 · Restore after a reinstall

`subscriptions_test.dart` › _restore brings back a subscription after a reinstall_
**Starts from:** Free on the profile, but the store account holds a Standard subscription.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Subscription** | "Free" |
| 2 | **Restore purchases** | "Subscription restored.", then Standard with "Renews on …". _(cloud)_ the Standard purchase was verified |

### SUB-05 · Cancelled plan keeps its limits until it ends

`subscriptions_test.dart` › _a cancelled subscription keeps its limits until the month is up_
**Starts from:** Standard, cancelled but paid for 30 more days; 14 expenses counted today.

| # | Step | Expected |
|---|---|---|
| 1 | Add an expense: ₹99, Food | "Transaction added": past the free 14, still within Standard's 120 |
| 2 | Settings → **Subscription** | "Cancelled · Standard until …", today "15 of 120" |

### SUB-06 · Yearly plans

`subscriptions_test.dart` › _a plan can be bought yearly, for twelve months less $1_

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Subscription** → **Yearly · save $1** | Basic $11.00, Standard $23.00, Premium $35.00 " / year", each "Save $1.00 a year" |
| 2 | **Subscribe** on Standard | "You're on Standard. Thank you!". _(store)_ the yearly product was bought |
| 3 | Switch to **Monthly** | Standard offers "Switch to monthly" rather than a new purchase |

---

## 10. Everyday polish

### EVD-01 · A deleted entry comes back with Undo

`everyday_test.dart` › _a deleted entry comes back with Undo_
**Starts from:** A Food expense "Team lunch".

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → swipe the entry left → confirm | "Deleted Food entry" with **Undo**; the entry is gone |
| 2 | Tap **Undo** | "Team lunch" is back, and is still in the cloud _(cloud)_ |

### EVD-02 · Swipe right to edit

`everyday_test.dart` › _swiping right opens the entry to edit_
**Starts from:** A Food expense "Team lunch".

| # | Step | Expected |
|---|---|---|
| 1 | **Activity** → swipe the entry right | "Edit transaction" opens |

### EVD-03 · Step through months and hide amounts

`everyday_test.dart` › _the dashboard steps through months and can hide amounts_
**Starts from:** 9,000 income last month.

| # | Step | Expected |
|---|---|---|
| 1 | Tap **Previous month** on the dashboard | "BALANCE AT MONTH END" and last month's name; ₹9,000.00 income |
| 2 | Tap the month name | Back to "AVAILABLE BALANCE" |
| 3 | Tap **Hide amounts**, then **Show amounts** | "••••••" replaces the balance, then it shows again |

### EVD-04 · Pay-day month start

`everyday_test.dart` › _a pay-day month start re-cuts the month everywhere_
**Starts from:** A fresh account.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Month starts on** → 25 | "The 25th, e.g. your pay day"; the dashboard shows the month running from the 25th |

### EVD-05 · Removing a used category moves its entries to Other

`everyday_test.dart` › _removing a used category moves its entries to Other_
**Starts from:** A Shopping expense "Running shoes".

| # | Step | Expected |
|---|---|---|
| 1 | Categories → remove **Shopping** → confirm | "Removed \"Shopping\". 1 moved to Other." |
| 2 | Open **Activity** | "Running shoes" is listed under Other |

### EVD-06 · Clear all data

`everyday_test.dart` › _clear all data starts over, after typing DELETE_
**Starts from:** Some transactions.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Clear all data** | "Clear all data?"; the button stays off until DELETE is typed |
| 2 | Type DELETE → **Clear everything** | The app starts over and the cloud has no transactions _(cloud)_ |

## 11. Recurring, reminders and alerts

### AUTO-01 · Recurring entries catch up, and pause

`automation_test.dart` › _a repeating expense is added when it comes due, and can pause_
**Starts from:** A monthly 15,000 rent rule started two months ago, last added on its start day.

| # | Step | Expected |
|---|---|---|
| 1 | Open the app | "Added 2 recurring entries that came due."; Activity lists "Flat rent" twice |
| 2 | Settings → **Recurring transactions** → **Pause** | "Paused", and the button reads **Resume** |

### AUTO-02 · Repeat from the add form

`automation_test.dart` › _turning on Repeat in the form sets up the rule_
**Starts from:** A fresh account.

| # | Step | Expected |
|---|---|---|
| 1 | Add an 899 Bills expense "Phone plan" with **Repeat** on (Monthly) | "Transaction added. It repeats monthly." |
| 2 | Settings → **Recurring transactions** | "Phone plan", "Monthly · Bills" |

### AUTO-03 · Daily reminder

`automation_test.dart` › _the daily reminder is set, and tapping it opens a new expense_
**Starts from:** A fresh account.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Daily reminder** on | "Every day at 9:00 PM"; scheduled for 21:00 |
| 2 | Tap the reminder notification | "Add expense" opens |

### AUTO-04 · Budget alert at 80%

`automation_test.dart` › _spending past 80% of a budget raises an alert_
**Starts from:** A 1,000 Food budget this month, alert at 80%.

| # | Step | Expected |
|---|---|---|
| 1 | Add an 850 Food expense | A "Food budget 80% used" notification |
| 2 | Tap it | Budgets opens |

## 12. App lock

The fingerprint reader is a fake that answers as the test sets it.

### SEC-01 · PIN lock on launch

`security_test.dart` › _with a PIN set, the app opens locked and the PIN unlocks it_
**Starts from:** A fresh account.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **App lock** → choose 2468, repeat it | "App lock is on." |
| 2 | Restart the app | "Enter your PIN" |
| 3 | Type 1111 | "Wrong PIN. 4 tries left before a short wait." |
| 4 | Type 2468 | The dashboard |

### SEC-02 · Fingerprint unlock

`security_test.dart` › _fingerprint unlock opens the app without the PIN_
**Starts from:** A phone with a fingerprint set up.

| # | Step | Expected |
|---|---|---|
| 1 | Turn on App lock, then **Unlock with fingerprint** | The fingerprint is asked for once to confirm it works |
| 2 | Restart the app | The fingerprint is asked for and the dashboard opens, with no PIN typed |

### SEC-03 · Forgot PIN

`security_test.dart` › _forgot PIN signs out, and signing back in needs no PIN_
**Starts from:** App lock on with PIN 2468.

| # | Step | Expected |
|---|---|---|
| 1 | Restart → **Forgot PIN?** → **Sign out** | The sign-in screen |
| 2 | Sign in again | The dashboard, with no lock screen |

## 13. Accounts and transfers

### ACC-01 · Accounts, opening balances and transfers

`accounts_test.dart` › _accounts start from their opening balance, and a transfer moves money between them without changing the total_
**Starts from:** A fresh account.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Accounts** → **Add account**: SBI savings, 10000 | "SBI savings" with ₹10,000.00 |
| 2 | **Add account**: Cash in hand (Cash), no opening balance | Total in accounts ₹10,000.00 |
| 3 | **Transfer** 2,000 from SBI savings to Cash in hand | "Moved ₹2,000.00 to Cash in hand"; SBI ₹8,000.00, Cash ₹2,000.00; the total is still ₹10,000.00 |
| 4 | Delete the transfer | "Transfer deleted"; SBI is back to ₹10,000.00 |

### ACC-02 · An expense from an account

`accounts_test.dart` › _an expense paid from an account lowers its balance, and the next entry starts on the same account_
**Starts from:** Accounts SBI savings (5,000) and Cash in hand (1,000).

| # | Step | Expected |
|---|---|---|
| 1 | Add a 450 Food expense, account **Cash in hand** | The dashboard's Accounts list: Cash in hand ₹550.00, SBI ₹5,000.00 |
| 2 | Start another expense | The Account row already shows Cash in hand |

## 14. Insights, receipts and CSV import

### INS-01 · Spending by category, tap-through, and Day

`insights_test.dart` › _reports break spending down by category, and a category opens its entries_
**Starts from:** Today: Food 450 "Lunch" and 300 "Dinner", Bills 2,000 "Power bill".

| # | Step | Expected |
|---|---|---|
| 1 | Open **Reports** | "Spending by category": Food ₹750.00, Bills ₹2,000.00 |
| 2 | Tap **Food** | Activity lists Lunch and Dinner, not Power bill |
| 3 | Reports → **Day** | The period reads today to today, with ₹2,750.00 spent |

### INS-02 · Receipt photo

`insights_test.dart` › _a receipt photo is attached to an expense and opens full size_
**Starts from:** A fresh account; the gallery returns a photo.

| # | Step | Expected |
|---|---|---|
| 1 | Add a 640 Food expense "Team dinner" → **Add a photo** → **Choose from gallery** | A thumbnail in the form; "Transaction added" |
| 2 | Activity | The entry's line says Receipt |
| 3 | Open it, tap the thumbnail | The photo full size |

### INS-03 · Import from CSV

`insights_test.dart` › _entries are imported from a CSV file, once_
**Starts from:** A CSV file with one expense and one income dated today.

| # | Step | Expected |
|---|---|---|
| 1 | Settings → **Import from CSV** | "Import 2 entries?", "1 income · 1 expense" |
| 2 | **Import** | "Imported 2 entries."; Activity lists both |
| 3 | Import the same file again | "Imported 0 entries (2 already here)." |

### INS-04 · The dashboard chart shows only your categories

`insights_test.dart` › _the dashboard chart lists only your own categories_
**Starts from:** this month's spending in seven categories: Rent 18,000, Shopping 2,499, Food 1,690, Bills 1,150, Health 800, Entertainment 649, Transport 320.

| # | Step | Expected |
|---|---|---|
| 1 | Scroll to **Where your money went** | Rent ₹18,000 and the other largest categories, each with its own icon and colour; no "Everything else" row |
| 2 | Tap **Show all 7 categories** | Transport is listed as itself; still no "Everything else" |

## Bugs these flows found

All four are fixed in `lib/`, and the flows above guard against their
return.

| Found by | Problem | Fix |
|---|---|---|
| INS-04 | The dashboard chart rolled every category past the sixth into an "Everything else" row, which read as a category the user did not have and hid real ones (Transport, here). Slices were also coloured by rank, not by the category's own colour | `features/dashboard/dashboard_screen.dart` and `features/reports/report_charts.dart`: one slice per real category in its own colour; a long legend shows the top six with **Show all** |
| SET-03 | The router was rebuilt every time Firebase's `userChanges()` emitted. That happens on every profile reload and on the roughly hourly ID-token refresh. Saving a display name, or simply staying signed in, threw the user back to the dashboard | `core/router/app_router.dart`: one router for the app's lifetime. Auth state is read inside `redirect`, and changes reach it through `GoRouterRefreshStream` |
| CARD-01, CARD-03 | "No credit cards yet" overflowed by 5.8px when the add-card form raised the keyboard | `features/credit_cards/credit_cards_screen.dart`: the empty state scrolls |
| SET-01 | The currency picker overflowed by 32px on 16:9 phones, clipping the last currency | `features/settings/settings_screen.dart`: the sheet can grow and scroll |
| TXN-01, CARD-02 | The "What would you like to add?" sheet overflowed by 47px while closing, because the next form's autofocused amount field raised the keyboard | `widgets/add_transaction_sheet.dart`: the sheet scrolls |

## Not covered

| Flow | Why |
|---|---|
| Google and Apple sign-in | They open the provider's own account UI and need a real account, so they can't run unattended. They share the post-sign-in path with email, which is covered |
| Saving or sharing an exported report | The PDF, Excel and CSV files end in the system share sheet, which differs between devices. The flows check the format choice; the files themselves are checked by unit tests |
| The real store purchase sheet | Google Play and the App Store show their own payment UI, which needs a signed-in store account and a licence tester. The flows use a fake store; the purchase handling around it is real. Test real purchases with a Play internal testing track and App Store sandbox accounts |
| Server-side verification | The `verifySubscription` and notification functions call Google's and Apple's APIs. The flows use a fake verifier that writes the same profile fields |
| Profile photo | Needs the camera or a gallery with images in it. Receipt photos use a fake picker (INS-02) |
| The real fingerprint prompt, notifications shade and file picker | System UI. The flows use fakes behind the same interfaces |
| The CSV import and backup functions | Run on the server; tested against the Firestore emulator in `functions/test/` |
| iOS | Only Android's native test runner is set up. iOS needs Patrol's `RunnerUITests` target in Xcode before this suite can run there |

## Adding a flow

1. Write the test in the matching `*_test.dart` file (see "Writing a new
   test" in [README.md](README.md)).
2. Give it the next free ID in its area, and add a row to the
   [flow index](#flow-index).
3. Add its section here: test name, starting state, steps, expected
   results.
