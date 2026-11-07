/**
 * Cloud Functions for Accounts Note.
 *
 * Uses 1st-gen functions so the mobile app can call them without Cloud Run
 * IAM (Gen2 allUsers invoker is blocked on this project).
 *
 * - Subscriptions (./subscriptions.ts): verifying Google Play and App Store
 *   purchases and following the stores' renewal/cancellation notifications.
 * - Account deletion.
 */
import * as functions from "firebase-functions/v1";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {releaseLinks} from "./subscriptions";

initializeApp();
const db = getFirestore();

export {
  appStoreNotifications,
  playBillingNotifications,
  refreshSubscription,
  verifySubscription,
} from "./subscriptions";

/**
 * Deletes the caller's cloud data and then their Auth account.
 *
 * Runs server-side with the Admin SDK on purpose: deleting a user from the
 * client requires a recent sign-in, which forces people to re-authenticate in
 * the middle of leaving. The caller's ID token already proves who they are, so
 * this needs no second prompt.
 *
 * Order matters — data first, account last. If the account went first the
 * client would lose the credentials needed to clean up whatever data remained.
 */
export const deleteAccountAndData = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
  })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in required.",
      );
    }

    const uid = context.auth.uid;

    try {
      // 1. Cloud data: the user document and every subcollection under it,
      // and the claim on any store subscription, so it can be used again
      // (the store keeps billing until the user cancels there).
      await db.recursiveDelete(db.collection("users").doc(uid));
      await releaseLinks(uid);
    } catch (err) {
      console.error(`Failed deleting data for ${uid}`, err);
      throw new functions.https.HttpsError(
        "internal",
        "Could not remove your data. Nothing was deleted; please try again.",
      );
    }

    try {
      // 2. Auth account, now that nothing references it.
      await getAuth().deleteUser(uid);
    } catch (err) {
      console.error(`Failed deleting auth user ${uid}`, err);
      throw new functions.https.HttpsError(
        "internal",
        "Your data was removed, but the account could not be closed. " +
          "Please contact support.",
      );
    }

    return {deleted: true};
  });
