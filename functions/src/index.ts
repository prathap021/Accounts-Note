/**
 * Stripe financial contributions for Accounts Note.
 *
 * Uses 1st-gen HTTPS functions so mobile/Stripe clients can invoke without
 * Cloud Run IAM (Gen2 allUsers invoker is blocked on this project).
 *
 * Secrets (never commit):
 *   STRIPE_SECRET_KEY
 *   STRIPE_WEBHOOK_SECRET
 *
 * Local: functions/.env and functions/.secret.local (gitignored)
 * Prod:  firebase functions:secrets:set ...
 */
import * as functions from "firebase-functions/v1";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import Stripe from "stripe";

initializeApp();
const db = getFirestore();

const MIN_USD = 1;

function stripeClient(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) {
    throw new Error("STRIPE_SECRET_KEY is not configured.");
  }
  return new Stripe(key);
}

async function getOrCreateCustomer(
  stripe: Stripe,
  uid: string,
  email?: string,
): Promise<string> {
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  const data = snap.data() || {};
  if (data.stripeCustomerId) {
    return data.stripeCustomerId as string;
  }

  const customer = await stripe.customers.create({
    email: email || undefined,
    metadata: {firebaseUid: uid},
  });

  await userRef.set({stripeCustomerId: customer.id}, {merge: true});
  return customer.id;
}

async function findUidByCustomer(
  customerId: string,
): Promise<string | null> {
  const q = await db
    .collection("users")
    .where("stripeCustomerId", "==", customerId)
    .limit(1)
    .get();
  if (q.empty) return null;
  return q.docs[0].id;
}

async function markContributor(uid: string, amountUsd: number): Promise<void> {
  await db.collection("users").doc(uid).set(
    {
      hasContributed: true,
      totalContributedUsd: FieldValue.increment(amountUsd),
      lastContributionAt: FieldValue.serverTimestamp(),
      lastContributionAmountUsd: amountUsd,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

/**
 * Callable: Stripe Checkout for financial support (one-time, recurring, or sponsor).
 */
export const createContributionCheckout = functions
  .runWith({
    secrets: ["STRIPE_SECRET_KEY"],
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in required.",
      );
    }

    const uid = context.auth.uid;
    const email = context.auth.token.email as string | undefined;
    const amountUsd = Number(data?.amountUsd);
    const supportTypeRaw = String(data?.supportType || "one_time");
    const supportType = ["one_time", "recurring", "sponsor"].includes(
      supportTypeRaw,
    ) ?
      supportTypeRaw :
      "one_time";
    const featureNote = String(data?.featureNote || "").trim().slice(0, 200);
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;

    if (!Number.isFinite(amountUsd) || amountUsd < MIN_USD) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `Minimum contribution is $${MIN_USD}.`,
      );
    }

    const unitAmount = Math.round(amountUsd * 100);
    if (unitAmount < MIN_USD * 100) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `Minimum contribution is $${MIN_USD}.`,
      );
    }

    if (supportType === "sponsor" && !featureNote) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Describe the feature you'd like to sponsor.",
      );
    }

    const stripe = stripeClient();
    const customerId = await getOrCreateCustomer(stripe, uid, email);

    const productName = supportType === "sponsor" ?
      "Accounts Note feature sponsorship" :
      supportType === "recurring" ?
        "Accounts Note monthly support" :
        "Accounts Note one-time donation";

    const productDescription = supportType === "sponsor" ?
      `Sponsor: ${featureNote}` :
      supportType === "recurring" ?
        "Monthly support for ongoing development of Accounts Note." :
        "One-time donation helping cover hosting, domains, and development time.";

    const isRecurring = supportType === "recurring";

    const session = await stripe.checkout.sessions.create({
      mode: isRecurring ? "subscription" : "payment",
      customer: customerId,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "usd",
            unit_amount: unitAmount,
            ...(isRecurring ? {recurring: {interval: "month" as const}} : {}),
            product_data: {
              name: productName,
              description: productDescription,
            },
          },
        },
      ],
      success_url: `https://${projectId}.web.app/stripe-success.html`,
      cancel_url: `https://${projectId}.web.app/stripe-cancel.html`,
      client_reference_id: uid,
      metadata: {
        firebaseUid: uid,
        type: "contribution",
        supportType,
        amountUsd: String(amountUsd),
        ...(featureNote ? {featureNote} : {}),
      },
      allow_promotion_codes: true,
    });

    return {url: session.url, sessionId: session.id};
  });

/**
 * Stripe webhook — marks the user as a contributor after successful payment.
 */
export const stripeWebhook = functions
  .runWith({
    secrets: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"],
    timeoutSeconds: 60,
    memory: "256MB",
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
    if (!webhookSecret) {
      res.status(500).send("Webhook secret not configured");
      return;
    }

    const stripe = stripeClient();
    const sig = req.headers["stripe-signature"];
    if (!sig || Array.isArray(sig)) {
      res.status(400).send("Missing stripe-signature");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        webhookSecret,
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("Webhook signature verification failed.", message);
      res.status(400).send(`Webhook Error: ${message}`);
      return;
    }

    try {
      if (event.type === "checkout.session.completed") {
        const session = event.data.object as Stripe.Checkout.Session;
        const paid =
          session.payment_status === "paid" ||
          session.mode === "subscription";
        if (
          paid &&
          (session.mode === "payment" || session.mode === "subscription")
        ) {
          let uid =
            session.client_reference_id ||
            session.metadata?.firebaseUid ||
            null;
          if (!uid && typeof session.customer === "string") {
            uid = await findUidByCustomer(session.customer);
          }

          const amountUsd =
            Number(session.metadata?.amountUsd) ||
            (session.amount_total != null ?
              session.amount_total / 100 :
              MIN_USD);

          if (uid) {
            await markContributor(uid, amountUsd);
          } else {
            console.warn("Contribution paid but no firebaseUid", session.id);
          }
        }
      }
      res.json({received: true});
    } catch (err) {
      console.error("Webhook handler error", err);
      res.status(500).send("Webhook handler failed");
    }
  });
