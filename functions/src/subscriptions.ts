/**
 * Subscriptions: proving purchases with Google Play and the App Store, and
 * keeping the plan on each user's profile in step with the stores.
 *
 * The app never writes its own plan. It sends the store's proof of purchase
 * here; these functions ask the store directly and write the result to
 * users/{uid}. Firestore rules read that plan to set the daily limits, and
 * refuse the subscription fields from any client.
 *
 * Store notifications (renewals, cancellations, refunds, expiry) are treated
 * as hints only: each one names a purchase, and the purchase's real state is
 * then fetched from the store's own API. So a forged notification can at
 * worst make us re-read the truth.
 *
 * Configuration (see the README's "Subscriptions" section):
 *   PLAY_PACKAGE_NAME       env, defaults to the Android applicationId
 *   APPLE_BUNDLE_ID         env, defaults to the iOS bundle id
 *   APPLE_IAP_KEY_ID        env, App Store Connect API key id
 *   APPLE_IAP_ISSUER_ID     env, App Store Connect issuer id
 *   APPLE_IAP_PRIVATE_KEY   secret, the .p8 key's contents
 * Google Play uses the functions' own service account (Application Default
 * Credentials); grant it access in the Play Console.
 */
import * as functions from "firebase-functions/v1";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {createHash} from "crypto";
import {
  androidpublisher,
  auth as googleAuth,
} from "@googleapis/androidpublisher";
import {
  APIException,
  AppStoreServerAPIClient,
  Environment,
} from "@apple/app-store-server-library";

/** Pub/Sub topic that Google Play's real-time notifications publish to. */
export const PLAY_NOTIFICATIONS_TOPIC = "play-billing-notifications";

type Plan = "basic" | "standard" | "premium";

/** One set of states for both stores. The app reads the same names. */
type SubscriptionState =
  | "active"
  | "grace"
  | "canceled"
  | "on_hold"
  | "paused"
  | "expired";

type Platform = "android" | "ios";

/**
 * Store product id to plan. Must match SubscriptionPlan in
 * lib/models/subscription_plan.dart and the product ids set up in Google
 * Play and App Store Connect.
 */
export const PLAN_BY_PRODUCT: Record<string, Plan> = {
  "accounts_note_basic_monthly": "basic",
  "accounts_note_standard_monthly": "standard",
  "accounts_note_premium_monthly": "premium",
  "accounts_note_basic_yearly": "basic",
  "accounts_note_standard_yearly": "standard",
  "accounts_note_premium_yearly": "premium",
};

/** A subscription as the store reports it right now. */
export interface Entitlement {
  platform: Platform;
  /** subscriptionLinks/{linkId}: one per store subscription. */
  linkId: string;
  productId: string;
  plan: Plan;
  state: SubscriptionState;
  expiresAt: Date | null;
  autoRenewing: boolean;
  /**
   * Who the store says bought it: the Firebase uid on Google Play
   * (obfuscatedExternalAccountId), a UUID derived from it on the App Store
   * (appAccountToken). Missing for purchases made outside the app.
   */
  ownerHint: string | null;
  /** Google Play: the purchase this one replaced (upgrade/downgrade). */
  replacedPurchaseToken: string | null;
  storeRef: {purchaseToken?: string; transactionId?: string};
}

const db = () => getFirestore();

/**
 * Whether the plan's limits apply at [now]. Mirrors effectivePlan() in the
 * app and dailyLimit() in firestore.rules.
 * @param {Entitlement} e The store's view.
 * @param {Date} now The moment to check.
 * @return {boolean} True while the plan applies.
 */
export function isEntitled(e: Entitlement, now = new Date()): boolean {
  const live = e.state === "active" || e.state === "grace" ||
    e.state === "canceled";
  return live && e.expiresAt !== null && e.expiresAt > now;
}

/**
 * Doc id for a Google Play purchase token (tokens are long and opaque).
 * @param {string} purchaseToken The token.
 * @return {string} The subscriptionLinks doc id.
 */
export function androidLinkId(purchaseToken: string): string {
  return "android_" +
    createHash("sha256").update(purchaseToken).digest("hex");
}

/**
 * RFC 4122 version-5 UUID. The app tags App Store purchases with
 * uuidV5(URL namespace, "accountsnote:" + uid); see appAccountTokenFor() in
 * lib/data/subscriptions/subscription_store.dart.
 * @param {string} name The name to hash.
 * @param {string} namespace The namespace UUID.
 * @return {string} The UUID, lower case.
 */
export function uuidV5(
  name: string,
  namespace = "6ba7b811-9dad-11d1-80b4-00c04fd430c8",
): string {
  const ns = Buffer.from(namespace.replace(/-/g, ""), "hex");
  const hash = createHash("sha1")
    .update(Buffer.concat([ns, Buffer.from(name, "utf8")]))
    .digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = b.toString("hex");
  return [
    hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16),
    hex.slice(16, 20), hex.slice(20),
  ].join("-");
}

/**
 * The owner tag the app would have attached for [uid] on [platform].
 * @param {Platform} platform Store platform.
 * @param {string} uid Firebase uid.
 * @return {string} The expected tag.
 */
export function expectedOwnerHint(platform: Platform, uid: string): string {
  return platform === "android" ? uid : uuidV5(`accountsnote:${uid}`);
}

/**
 * The payload of a JWS returned by Apple's API. Not signature-checked: it
 * arrives over TLS from Apple in answer to our own authenticated request.
 * @param {string | undefined} jws Compact JWS.
 * @return {Record<string, unknown>} The decoded payload.
 */
function jwsPayload(jws: string | undefined): Record<string, unknown> {
  if (!jws) return {};
  const part = jws.split(".")[1] ?? "";
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

// ---------------------------------------------------------------- Google Play

/**
 * Google's states, folded into ours.
 * @param {string | null | undefined} state subscriptionsv2 state.
 * @return {SubscriptionState} Ours.
 */
export function mapPlayState(state: string | null | undefined):
  SubscriptionState {
  switch (state) {
  case "SUBSCRIPTION_STATE_ACTIVE": return "active";
  case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": return "grace";
  case "SUBSCRIPTION_STATE_CANCELED": return "canceled";
  case "SUBSCRIPTION_STATE_ON_HOLD": return "on_hold";
  case "SUBSCRIPTION_STATE_PAUSED": return "paused";
  default: return "expired";
  }
}

const playPackage = () =>
  process.env.PLAY_PACKAGE_NAME || "com.example.income_expense_tracker";

/**
 * Reads a subscription purchase from the Google Play Developer API.
 * @param {string} purchaseToken Token from the app's purchase.
 * @return {Promise<Entitlement>} Its current state.
 */
export async function fetchPlaySubscription(
  purchaseToken: string,
): Promise<Entitlement> {
  const client = androidpublisher({
    version: "v3",
    auth: new googleAuth.GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    }),
  });

  let data;
  try {
    ({data} = await client.purchases.subscriptionsv2.get({
      packageName: playPackage(),
      token: purchaseToken,
    }));
  } catch (err) {
    const status = (err as {code?: number}).code;
    if (status === 400 || status === 404 || status === 410) {
      throw new functions.https.HttpsError(
        "invalid-argument", "Google Play does not recognise this purchase.");
    }
    console.error("Play Developer API call failed", err);
    throw new functions.https.HttpsError(
      "unavailable", "Could not reach Google Play. Please try again.");
  }

  const item = data.lineItems?.[0];
  const productId = item?.productId ?? "";
  const plan = PLAN_BY_PRODUCT[productId];
  if (!plan) {
    throw new functions.https.HttpsError(
      "invalid-argument", `Unknown subscription product ${productId}.`);
  }
  const state = mapPlayState(data.subscriptionState);
  let expiresAt = item?.expiryTime ? new Date(item.expiryTime) : null;
  if (state === "grace") {
    // Play keeps access open while it retries the payment; the next
    // notification (recovered, or on hold) settles it.
    const floor = new Date(Date.now() + 24 * 60 * 60 * 1000);
    if (!expiresAt || expiresAt < floor) expiresAt = floor;
  }

  return {
    platform: "android",
    linkId: androidLinkId(purchaseToken),
    productId,
    plan,
    state,
    expiresAt,
    autoRenewing: item?.autoRenewingPlan?.autoRenewEnabled ?? false,
    ownerHint:
      data.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    replacedPurchaseToken: data.linkedPurchaseToken ?? null,
    storeRef: {purchaseToken},
  };
}

// ------------------------------------------------------------------ App Store

/**
 * Apple's API clients, production first. A transaction that production does
 * not know is tried against the sandbox (TestFlight, App Review).
 * @return {AppStoreServerAPIClient[]} The clients.
 */
function appleClients(): AppStoreServerAPIClient[] {
  const key = process.env.APPLE_IAP_PRIVATE_KEY;
  const keyId = process.env.APPLE_IAP_KEY_ID;
  const issuerId = process.env.APPLE_IAP_ISSUER_ID;
  const bundleId =
    process.env.APPLE_BUNDLE_ID || "com.example.incomeExpenseTracker";
  if (!key || !keyId || !issuerId || key === "unset") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "App Store purchases are not set up on the server yet.");
  }
  return [Environment.PRODUCTION, Environment.SANDBOX].map(
    (env) => new AppStoreServerAPIClient(key, keyId, issuerId, bundleId, env));
}

/**
 * Apple's status codes (getAllSubscriptionStatuses), folded into ours.
 * @param {number | undefined} status Apple's status.
 * @param {boolean} autoRenewing Whether auto-renew is on.
 * @return {SubscriptionState} Ours.
 */
export function mapAppleState(
  status: number | undefined,
  autoRenewing: boolean,
): SubscriptionState {
  switch (status) {
  case 1: return autoRenewing ? "active" : "canceled";
  case 3: return "on_hold"; // billing retry, no grace period
  case 4: return "grace";
  default: return "expired"; // 2 expired, 5 revoked
  }
}

/**
 * Reads a subscription from the App Store Server API.
 * @param {string} transactionId Any transaction of the subscription.
 * @return {Promise<Entitlement>} Its current state.
 */
export async function fetchAppleSubscription(
  transactionId: string,
): Promise<Entitlement> {
  for (const client of appleClients()) {
    try {
      const info = await client.getTransactionInfo(transactionId);
      const original =
        String(jwsPayload(info.signedTransactionInfo).originalTransactionId);
      const statuses = await client.getAllSubscriptionStatuses(original);

      for (const group of statuses.data ?? []) {
        for (const last of group.lastTransactions ?? []) {
          if (last.originalTransactionId !== original) continue;
          const tx = jwsPayload(last.signedTransactionInfo);
          const renewal = jwsPayload(last.signedRenewalInfo);
          const productId = String(tx.productId ?? "");
          const plan = PLAN_BY_PRODUCT[productId];
          if (!plan) {
            throw new functions.https.HttpsError(
              "invalid-argument", `Unknown subscription product ${productId}.`);
          }
          const autoRenewing = renewal.autoRenewStatus === 1;
          const state = mapAppleState(last.status, autoRenewing);
          const until = state === "grace" ?
            Number(renewal.gracePeriodExpiresDate ?? tx.expiresDate) :
            Number(tx.expiresDate);
          return {
            platform: "ios",
            linkId: `ios_${original}`,
            productId,
            plan,
            state,
            expiresAt: Number.isFinite(until) ? new Date(until) : null,
            autoRenewing,
            ownerHint: typeof tx.appAccountToken === "string" ?
              tx.appAccountToken.toLowerCase() : null,
            replacedPurchaseToken: null,
            storeRef: {transactionId: original},
          };
        }
      }
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The App Store has no subscription for this purchase.");
    } catch (err) {
      if (err instanceof APIException && err.httpStatusCode === 404) {
        continue; // Not in this environment; try the next.
      }
      if (err instanceof functions.https.HttpsError) throw err;
      console.error("App Store Server API call failed", err);
      throw new functions.https.HttpsError(
        "unavailable", "Could not reach the App Store. Please try again.");
    }
  }
  throw new functions.https.HttpsError(
    "invalid-argument", "The App Store does not recognise this purchase.");
}

// ------------------------------------------------------- Linking and applying

/**
 * The profile fields the app and the rules read. Only this file writes them.
 * @param {Entitlement} e The store's view.
 * @return {Record<string, unknown>} Fields for users/{uid}.
 */
function profileFields(e: Entitlement): Record<string, unknown> {
  return {
    subscriptionPlan: e.plan,
    subscriptionStatus: e.state,
    subscriptionExpiresAt: e.expiresAt ? Timestamp.fromDate(e.expiresAt) : null,
    subscriptionAutoRenewing: e.autoRenewing,
    subscriptionPlatform: e.platform,
    subscriptionProductId: e.productId,
    subscriptionLinkId: e.linkId,
    subscriptionUpdatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Ties the store subscription to [uid] and, where it is the one that should
 * count, writes it to the profile.
 *
 * A store subscription belongs to one account: the first that verifies it,
 * or the one the store says bought it. Another account presenting it is
 * refused, so one purchase cannot unlock several accounts.
 *
 * The profile follows the newest subscription that is live. A notification
 * about an older one (a plan the user upgraded from, now replaced) only
 * updates its link, never overwrites the plan.
 * @param {string} uid Account claiming the subscription.
 * @param {Entitlement} e The store's view of it.
 */
export async function linkAndApply(uid: string, e: Entitlement): Promise<void> {
  if (e.ownerHint && e.ownerHint !== expectedOwnerHint(e.platform, uid)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "This subscription was bought from a different Accounts Note account.");
  }

  const linkRef = db().collection("subscriptionLinks").doc(e.linkId);
  const userRef = db().collection("users").doc(uid);
  const replacedRef = e.replacedPurchaseToken ?
    db().collection("subscriptionLinks")
      .doc(androidLinkId(e.replacedPurchaseToken)) :
    null;

  await db().runTransaction(async (t) => {
    const [link, user, replaced] = await Promise.all([
      t.get(linkRef),
      t.get(userRef),
      replacedRef ? t.get(replacedRef) : Promise.resolve(null),
    ]);
    const owner = link.data()?.uid ?? replaced?.data()?.uid;
    if (owner && owner !== uid) {
      throw new functions.https.HttpsError(
        "already-exists",
        "This subscription is already used by another Accounts Note " +
        "account. Sign in to that account to use it.");
    }

    t.set(linkRef, {
      uid,
      platform: e.platform,
      productId: e.productId,
      storeRef: e.storeRef,
      state: e.state,
      expiresAt: e.expiresAt ? Timestamp.fromDate(e.expiresAt) : null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const current = user.data() ?? {};
    const currentLink = current.subscriptionLinkId as string | undefined;
    const currentExpiry =
      (current.subscriptionExpiresAt as Timestamp | null | undefined)?.toDate();
    const currentLive =
      ["active", "grace", "canceled"].includes(current.subscriptionStatus) &&
      currentExpiry !== undefined && currentExpiry > new Date();

    const isCurrent = !currentLink || currentLink === e.linkId ||
      (replacedRef !== null && currentLink === replacedRef.id);
    if (isCurrent || isEntitled(e) || !currentLive) {
      t.set(userRef, profileFields(e), {merge: true});
    }
  });
}

/**
 * Finds whose subscription a store notification is about.
 * @param {Entitlement} e The store's view.
 * @return {Promise<string | null>} The uid, or null if unknown.
 */
async function ownerOf(e: Entitlement): Promise<string | null> {
  const link = await db().collection("subscriptionLinks").doc(e.linkId).get();
  if (link.exists) return link.data()?.uid ?? null;
  if (e.replacedPurchaseToken) {
    const old = await db().collection("subscriptionLinks")
      .doc(androidLinkId(e.replacedPurchaseToken)).get();
    if (old.exists) return old.data()?.uid ?? null;
  }
  // A purchase the app has not verified yet: Google Play carries the uid.
  if (e.platform === "android" && e.ownerHint) {
    const user = await db().collection("users").doc(e.ownerHint).get();
    if (user.exists) return e.ownerHint;
  }
  return null;
}

/**
 * Re-reads a stored subscription from its store.
 * @param {object} ref What the link stored.
 * @param {Platform} platform Which store.
 * @return {Promise<Entitlement>} Its current state.
 */
function refetch(
  ref: Entitlement["storeRef"],
  platform: Platform,
): Promise<Entitlement> {
  if (platform === "android" && ref.purchaseToken) {
    return fetchPlaySubscription(ref.purchaseToken);
  }
  if (platform === "ios" && ref.transactionId) {
    return fetchAppleSubscription(ref.transactionId);
  }
  throw new functions.https.HttpsError(
    "not-found", "No subscription on file.");
}

// ------------------------------------------------------------------ Functions

const appleSecrets = {secrets: ["APPLE_IAP_PRIVATE_KEY"]};

/**
 * Callable and webhook functions must be reachable without Cloud IAM: the
 * app calls them with a Firebase ID token (checked in code, not by IAM), and
 * Apple's servers have no Google identity at all. Firebase grants this only
 * when a function is first created, so it is declared to hold on every
 * deploy.
 */
const publicAccess = {invoker: "public" as const};

/**
 * Callable. The app sends the store's proof right after a purchase or
 * restore; the plan is written to the profile only once the store confirms.
 */
export const verifySubscription = functions
  .runWith({
    ...appleSecrets,
    ...publicAccess,
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated", "Sign in required.");
    }
    const uid = context.auth.uid;
    const platform = data?.platform;

    let entitlement: Entitlement;
    if (platform === "android") {
      const token = data?.purchaseToken;
      if (typeof token !== "string" || !token || token.length > 4096) {
        throw new functions.https.HttpsError(
          "invalid-argument", "Missing purchase token.");
      }
      entitlement = await fetchPlaySubscription(token);
    } else if (platform === "ios") {
      const id = data?.transactionId;
      if (typeof id !== "string" || !/^\d{1,40}$/.test(id)) {
        throw new functions.https.HttpsError(
          "invalid-argument", "Missing transaction id.");
      }
      entitlement = await fetchAppleSubscription(id);
    } else {
      throw new functions.https.HttpsError(
        "invalid-argument", "Unknown platform.");
    }

    await linkAndApply(uid, entitlement);
    return {
      plan: entitlement.plan,
      state: entitlement.state,
      expiresAt: entitlement.expiresAt?.toISOString() ?? null,
    };
  });

/**
 * Callable. Re-checks the subscription already on the caller's profile, for
 * when the paid period ended and a renewal notification may have been lost.
 */
export const refreshSubscription = functions
  .runWith({
    ...appleSecrets,
    ...publicAccess,
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onCall(async (_data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated", "Sign in required.");
    }
    const uid = context.auth.uid;
    const user = await db().collection("users").doc(uid).get();
    const linkId = user.data()?.subscriptionLinkId as string | undefined;
    if (!linkId) {
      throw new functions.https.HttpsError(
        "not-found", "No subscription on file.");
    }
    const link = await db().collection("subscriptionLinks").doc(linkId).get();
    const stored = link.data();
    if (!stored || stored.uid !== uid) {
      throw new functions.https.HttpsError(
        "not-found", "No subscription on file.");
    }
    const entitlement = await refetch(stored.storeRef ?? {}, stored.platform);
    await linkAndApply(uid, entitlement);
    return {plan: entitlement.plan, state: entitlement.state};
  });

/**
 * Google Play real-time developer notifications (Pub/Sub). Every
 * subscription event — renewed, cancelled, on hold, expired, revoked —
 * triggers a fresh read of that purchase.
 */
export const playBillingNotifications = functions.pubsub
  .topic(PLAY_NOTIFICATIONS_TOPIC)
  .onPublish(async (message) => {
    const payload = message.json ?? {};
    const token = payload.subscriptionNotification?.purchaseToken;
    if (payload.packageName && payload.packageName !== playPackage()) return;
    if (typeof token !== "string") return; // test or one-time notifications

    let entitlement: Entitlement;
    try {
      entitlement = await fetchPlaySubscription(token);
    } catch (err) {
      if (err instanceof functions.https.HttpsError &&
          err.code === "unavailable") {
        throw err; // Let Pub/Sub retry.
      }
      console.warn("Ignoring Play notification", err);
      return;
    }
    const uid = await ownerOf(entitlement);
    if (!uid) {
      console.warn("Play notification for an unlinked purchase",
        entitlement.linkId);
      return;
    }
    await linkAndApply(uid, entitlement);
  });

/**
 * App Store Server Notifications V2 (HTTPS). The payload only says which
 * subscription changed; its state is then read from Apple's API.
 */
export const appStoreNotifications = functions
  .runWith({
    ...appleSecrets,
    ...publicAccess,
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    try {
      const notification = jwsPayload(req.body?.signedPayload);
      const data = (notification.data ?? {}) as Record<string, string>;
      const tx = jwsPayload(data.signedTransactionInfo);
      const original = tx.originalTransactionId;
      if (typeof original !== "string") {
        res.status(200).send("ignored");
        return;
      }
      const entitlement = await fetchAppleSubscription(original);
      const uid = await ownerOf(entitlement);
      if (uid) await linkAndApply(uid, entitlement);
      res.status(200).send("ok");
    } catch (err) {
      console.error("App Store notification failed", err);
      // A 5xx makes Apple retry later.
      res.status(500).send("error");
    }
  });
