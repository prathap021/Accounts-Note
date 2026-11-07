/**
 * Cloud Functions for Accounts Note.
 *
 * Uses 1st-gen functions so the mobile app can call them without Cloud Run
 * IAM (Gen2 allUsers invoker is blocked on this project).
 *
 * - Subscriptions (./subscriptions.ts): verifying Google Play and App Store
 *   purchases and following the stores' renewal/cancellation notifications.
 * - Backups (./backup.ts): signed backup files, and importing them into any
 *   account.
 * - CSV import (./csvImport.ts): entries read from a CSV file, within a
 *   monthly allowance.
 */
import {initializeApp} from "firebase-admin/app";

initializeApp();

export {createBackup, importBackup} from "./backup";

export {importCsvRows} from "./csvImport";

export {
  appStoreNotifications,
  playBillingNotifications,
  refreshSubscription,
  verifySubscription,
} from "./subscriptions";
