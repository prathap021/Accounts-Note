# Accounts Note privacy policy

_Last updated: 8 November 2026_

Accounts Note ("the app") is a personal income and expense tracker,
published by Prathap A. This policy explains what the app stores, where, why,
and the choices you have.

## What the app stores

- **Your account**: your email address, display name and profile photo,
  from the sign-in you choose (email and password, Google or Apple). Handled
  by Firebase Authentication.
- **Your ledger**: the transactions, categories, budgets, recurring
  entries, accounts (a name, a type and an opening balance) and transfers
  between them that you enter. Stored on your phone and in your own area of
  Google Cloud Firestore, so they sync between your devices. No one else's
  account can read them.
- **Credit cards**: a name, a colour, an optional limit and at most the last
  four digits. The full card number, expiry date and CVV are never asked for
  or stored.
- **Receipt photos**: a photo you choose to attach to an entry, from the
  camera or gallery, stored with your ledger. The app only opens the camera
  or gallery when you ask it to.
- **Daily entry counts**: how many entries you add each day, to apply your
  plan's limit.
- **Your subscription**: the plan you bought and when it renews or ends, as
  confirmed by Google Play or the App Store. Payment details stay with the
  store; the app never sees them.
- **Settings**: currency, theme, reminders, the month start day and similar
  preferences, on your phone.

## Data that stays on your phone

- **Location**: when you first open the app it offers to use your
  **approximate location once** to choose your currency. It is turned into a
  country on your phone and then discarded; it is never stored or sent
  anywhere. You can decline, and the app uses your phone's region setting
  instead.
- **App lock**: if you set a PIN, only a salted, one-way hash of it is kept,
  on your phone. Fingerprint or face unlock is handled entirely by your
  phone; the app never receives your biometric data.
- **Reminders**: daily, bill and budget reminders are scheduled on your
  phone as local notifications.

## Files you import or export

- **Backups**: "Back up now" creates a file with your ledger and hands it
  to you to save or send; where it goes after that is your choice. The file
  is signed so it cannot be altered, but it is not encrypted, so keep it
  somewhere private. Importing a backup adds its entries to the account you
  are signed in to.
- **CSV import** and **report exports** (PDF, Excel, CSV) work on files you
  choose. An imported file's rows are sent to the app's server only to be
  added to your ledger; the file itself is not kept.

## Diagnostics

The app uses Firebase Crashlytics to report crashes and Firebase Analytics
for anonymous usage statistics. These contain no ledger data.

## How your data is used and shared

Your data is used only to run the app's features for you. It is not sold,
rented or used for advertising, and the app shows no ads.

It is processed by these service providers, only to provide the app:

- **Google** (Firebase Authentication, Cloud Firestore, Cloud Functions,
  Crashlytics, Analytics, Google Play) for sign-in, storage, sync, backups,
  crash reports and purchases.
- **Apple** (Sign in with Apple, App Store) for sign-in and purchases on
  iPhone.

Data is encrypted in transit (HTTPS) and at rest on Google's servers.

## Keeping and deleting your data

Your data is kept while your account exists. Settings → **Clear all data**
removes every transaction, category, card, account, budget and receipt from
your phone and the cloud at once. To have your account itself deleted, email
the address below; it will be deleted with all its data within 30 days.

## Children

The app is not directed at children under 13 and does not knowingly collect
data from them.

## Changes

If this policy changes, the new version is posted here with a new "Last
updated" date.

## Contact

Prathap A — selflearner.dev@gmail.com
