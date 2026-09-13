/**
 * Stripe one-time contributions for Accounts Note.
 *
 * Secrets (never commit):
 *   STRIPE_SECRET_KEY
 *   STRIPE_WEBHOOK_SECRET
 *
 * Local: functions/.env and functions/.secret.local (gitignored)
 * Prod:  firebase functions:secrets:set ...
 */
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import Stripe from "stripe";

initializeApp();
const db = getFirestore();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

const MIN_USD = 5;

function stripeClient(): Stripe {
  return new Stripe(stripeSecretKey.value());
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
 * Callable: one-time Stripe Checkout for a contribution amount (USD).
 */
export const createContributionCheckout = onCall(
  {secrets: [stripeSecretKey], cors: true},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const uid = request.auth.uid;
    const email = request.auth.token.email as string | undefined;
    const amountUsd = Number(request.data?.amountUsd);
    const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;

    if (!Number.isFinite(amountUsd) || amountUsd < MIN_USD) {
      throw new HttpsError(
        "invalid-argument",
        `Minimum contribution is $${MIN_USD}.`,
      );
    }

    const unitAmount = Math.round(amountUsd * 100);
    if (unitAmount < MIN_USD * 100) {
      throw new HttpsError(
        "invalid-argument",
        `Minimum contribution is $${MIN_USD}.`,
      );
    }

    const stripe = stripeClient();
    const customerId = await getOrCreateCustomer(stripe, uid, email);

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer: customerId,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "usd",
            unit_amount: unitAmount,
            product_data: {
              name: "Accounts Note contribution",
              description:
                "Thank you for supporting open-source. " +
                "Unlocks unlimited transactions.",
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
        amountUsd: String(amountUsd),
      },
      allow_promotion_codes: true,
    });

    return {url: session.url, sessionId: session.id};
  },
);

/**
 * Stripe webhook — marks the user as a contributor after successful payment.
 */
export const stripeWebhook = onRequest(
  {secrets: [stripeSecretKey, stripeWebhookSecret]},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
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
        stripeWebhookSecret.value(),
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
        if (session.mode === "payment" && session.payment_status === "paid") {
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
  },
);
