# Accounts Note privacy policy

_Last updated: 7 November 2026_

Accounts Note is a personal income and expense tracker. This page explains
what it stores, where, and why.

## What the app stores

- **Your account**: your email address, display name and profile photo, from
  the sign-in you choose (email and password, Google or Apple). Handled by
  Firebase Authentication.
- **Your ledger**: the transactions, categories, credit cards (a name, a
  colour, an optional limit and at most the last four digits, never the full
  card number) and budgets you enter. Stored on your phone and in your own
  area of Google Cloud Firestore, so they sync between your devices. No one
  else's account can read them.
- **Daily entry counts**: how many entries you add each day, to apply your
  plan's daily limit.
- **Your subscription**: the plan you bought and when it renews or ends,
  as confirmed by Google Play or the App Store. Payment details stay with
  the store; the app never sees them.
- **Settings**: currency, theme and similar preferences, on your phone.

## Location

When you first open the app it offers to use your **approximate location
once** to choose your currency. The location is turned into a country on
your phone and then discarded. It is never stored or sent anywhere. You can
decline, and the app uses your phone's region setting instead.

## Diagnostics

The app uses Firebase Crashlytics to report crashes and Firebase Analytics
for anonymous usage statistics in release builds. These contain no ledger
data.

## Backups

"Back up now" creates a file with your ledger and hands it to you to save or
send. Where it goes after that is your choice. The file is signed so that it
cannot be altered; it is not encrypted, so keep it somewhere private.

## Sharing

Your data is not sold or shared with third parties. It is processed by
Google (Firebase, Google Play) and Apple (App Store) only to provide sign-in,
storage, sync and purchases.

## Deleting your data

Settings → **Clear all data** removes every transaction, category, card and
budget from your phone and the cloud. To have your account itself removed,
open an issue at https://github.com/prathap021/Accounts-Note/issues or
contact the developer, and it will be deleted along with all its data.

## Contact

https://github.com/prathap021/Accounts-Note/issues
