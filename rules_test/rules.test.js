// Firestore security rules: daily entry limits and server-owned plan fields.
//
// Run from the repo root (starts the emulator, runs, stops it):
//   firebase emulators:exec --only firestore --project demo-accounts-note \
//     "npm --prefix rules_test test"

import {readFileSync} from "node:fs";
import {after, before, beforeEach, describe, test} from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  deleteDoc,
  doc,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";

const UID = "asha";
const IST = 330; // UTC+05:30, in minutes

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-accounts-note",
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed(`users/${UID}`, {email: "asha@example.com"});
});

const db = () => env.authenticatedContext(UID).firestore();

async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

/** yyyy-MM-dd for [date] shifted by [offset] minutes, as the app computes it. */
function usageDay(date, offset) {
  const local = new Date(date.getTime() + offset * 60000);
  return local.toISOString().slice(0, 10);
}

function entry(type, {createdAt = new Date(), offset = IST} = {}) {
  return {
    type,
    amount: 120,
    categoryId: "food",
    categoryName: "Food",
    date: Timestamp.fromDate(createdAt),
    createdAt: Timestamp.fromDate(createdAt),
    updatedAt: Timestamp.fromDate(createdAt),
    createdTzOffsetMinutes: offset,
  };
}

/**
 * Uploads a new entry the way the app does: the transaction and its day's
 * counter bump in one batch.
 */
function addCounted(firestore, id, type, opts = {}) {
  const tx = {...entry(type, opts), ...(opts.override ?? {})};
  const day = opts.day ?? usageDay(tx.createdAt.toDate(), tx.createdTzOffsetMinutes);
  const batch = writeBatch(firestore);
  batch.set(doc(firestore, `users/${UID}/transactions/${id}`), tx, {merge: true});
  if (opts.bump !== false) {
    batch.set(doc(firestore, `users/${UID}/usage/${day}`), {
      [opts.bumpType ?? type]: increment(opts.by ?? 1),
      lastTxId: opts.lastTxId ?? id,
      updatedAt: serverTimestamp(),
    }, {merge: true});
  }
  return batch.commit();
}

function today(offset = IST) {
  return usageDay(new Date(), offset);
}

function plan(name, {status = "active", days = 20} = {}) {
  return {
    email: "asha@example.com",
    subscriptionPlan: name,
    subscriptionStatus: status,
    subscriptionExpiresAt: Timestamp.fromDate(new Date(Date.now() + days * 864e5)),
  };
}

describe("free plan", () => {
  test("allows 7 income entries a day and refuses the 8th", async () => {
    for (let i = 1; i <= 7; i++) {
      await assertSucceeds(addCounted(db(), `in-${i}`, "income"));
    }
    await assertFails(addCounted(db(), "in-8", "income"));
  });

  test("counts expense separately from income", async () => {
    await seed(`users/${UID}/usage/${today()}`, {income: 7, lastTxId: "x"});
    await assertFails(addCounted(db(), "in-8", "income"));
    await assertSucceeds(addCounted(db(), "ex-1", "expense"));
  });

  test("refuses the 8th expense", async () => {
    await seed(`users/${UID}/usage/${today()}`, {expense: 7, lastTxId: "x"});
    await assertFails(addCounted(db(), "ex-8", "expense"));
  });
});

describe("paid plans", () => {
  test("Basic allows 30 a day", async () => {
    await seed(`users/${UID}`, plan("basic"));
    await seed(`users/${UID}/usage/${today()}`, {income: 29, lastTxId: "x"});
    await assertSucceeds(addCounted(db(), "in-30", "income"));
    await assertFails(addCounted(db(), "in-31", "income"));
  });

  test("Standard allows 60 a day", async () => {
    await seed(`users/${UID}`, plan("standard"));
    await seed(`users/${UID}/usage/${today()}`, {expense: 59, lastTxId: "x"});
    await assertSucceeds(addCounted(db(), "ex-60", "expense"));
    await assertFails(addCounted(db(), "ex-61", "expense"));
  });

  test("Premium allows 100 a day", async () => {
    await seed(`users/${UID}`, plan("premium"));
    await seed(`users/${UID}/usage/${today()}`, {income: 99, lastTxId: "x"});
    await assertSucceeds(addCounted(db(), "in-100", "income"));
    await assertFails(addCounted(db(), "in-101", "income"));
  });

  test("a cancelled plan keeps its limit until the paid month ends", async () => {
    await seed(`users/${UID}`, plan("premium", {status: "canceled"}));
    await seed(`users/${UID}/usage/${today()}`, {income: 7, lastTxId: "x"});
    await assertSucceeds(addCounted(db(), "in-8", "income"));
  });

  test("an expired plan falls back to the free limit", async () => {
    await seed(`users/${UID}`, plan("premium", {days: -1}));
    await seed(`users/${UID}/usage/${today()}`, {income: 7, lastTxId: "x"});
    await assertFails(addCounted(db(), "in-8", "income"));
  });

  test("a plan on hold falls back to the free limit", async () => {
    await seed(`users/${UID}`, plan("premium", {status: "on_hold"}));
    await seed(`users/${UID}/usage/${today()}`, {income: 7, lastTxId: "x"});
    await assertFails(addCounted(db(), "in-8", "income"));
  });
});

describe("the counter cannot be skipped or gamed", () => {
  test("a new entry without its counter bump is refused", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {bump: false}));
  });

  test("one bump cannot cover two new entries", async () => {
    const f = db();
    const batch = writeBatch(f);
    batch.set(doc(f, `users/${UID}/transactions/a`), entry("income"));
    batch.set(doc(f, `users/${UID}/transactions/b`), entry("income"));
    batch.set(doc(f, `users/${UID}/usage/${today()}`), {
      income: increment(1), lastTxId: "a", updatedAt: serverTimestamp(),
    }, {merge: true});
    await assertFails(batch.commit());
  });

  test("bumping the other type does not count", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {bumpType: "expense"}));
  });

  test("bumping by two is refused", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {by: 2}));
  });

  test("the bump must name the entry it is for", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {lastTxId: "other"}));
  });

  test("the bump must be on the entry's own day", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {day: "2001-01-01"}));
  });

  test("counters cannot be lowered, reset or deleted", async () => {
    const path = `users/${UID}/usage/${today()}`;
    await seed(path, {income: 7, lastTxId: "x"});
    await assertFails(setDoc(doc(db(), path), {
      income: 0, lastTxId: "x", updatedAt: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(db(), path), {income: increment(-1)}));
    await assertFails(deleteDoc(doc(db(), path)));
  });

  test("entries more than 3 days old are refused", async () => {
    const old = new Date(Date.now() - 4 * 864e5);
    await assertFails(addCounted(db(), "in-1", "income", {createdAt: old}));
  });

  test("entries made 2 days ago (offline) still upload", async () => {
    const recent = new Date(Date.now() - 2 * 864e5);
    await assertSucceeds(addCounted(db(), "in-1", "income", {createdAt: recent}));
  });

  test("entries dated in the future are refused", async () => {
    const later = new Date(Date.now() + 3 * 3600e3);
    await assertFails(addCounted(db(), "in-1", "income", {createdAt: later}));
  });

  test("a new entry without its timezone offset is refused", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {
      override: {createdTzOffsetMinutes: null},
      day: today(),
    }));
  });

  test("an out-of-range timezone offset is refused", async () => {
    await assertFails(addCounted(db(), "in-1", "income", {offset: 2000}));
  });
});

describe("days are the user's local days", () => {
  test("8:30 pm UTC counts as the next day in India", async () => {
    const now = new Date();
    // The latest 20:30 UTC that is no more than a day ago.
    const t = new Date(Date.UTC(
      now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 20, 30));
    if (t > now) t.setUTCDate(t.getUTCDate() - 1);
    const nextDay = usageDay(t, IST);
    await assertSucceeds(addCounted(db(), "in-1", "income", {
      createdAt: t, day: nextDay,
    }));
    await assertFails(addCounted(db(), "in-2", "income", {
      createdAt: t, day: t.toISOString().slice(0, 10),
    }));
  });
});

describe("existing entries", () => {
  test("editing an entry needs no counter bump", async () => {
    await seed(`users/${UID}/transactions/t1`, entry("expense"));
    await assertSucceeds(setDoc(
      doc(db(), `users/${UID}/transactions/t1`),
      {...entry("expense"), amount: 999},
      {merge: true},
    ));
  });

  test("replaying an upload that already landed is accepted", async () => {
    await assertSucceeds(addCounted(db(), "in-1", "income"));
    await assertSucceeds(addCounted(db(), "in-1", "income"));
  });
});

describe("plan fields are server-owned", () => {
  test("the app cannot give itself a plan when creating the profile", async () => {
    await env.clearFirestore();
    await assertFails(setDoc(doc(db(), `users/${UID}`), plan("premium")));
    await assertSucceeds(setDoc(doc(db(), `users/${UID}`), {email: "a@b.c"}));
  });

  test("the app cannot change its plan or expiry", async () => {
    await seed(`users/${UID}`, plan("basic"));
    await assertFails(updateDoc(doc(db(), `users/${UID}`), {
      subscriptionPlan: "premium",
    }));
    await assertFails(updateDoc(doc(db(), `users/${UID}`), {
      subscriptionExpiresAt: Timestamp.fromDate(new Date(Date.now() + 1e12)),
    }));
    await assertSucceeds(updateDoc(doc(db(), `users/${UID}`), {
      displayName: "Asha",
    }));
  });

  test("other users' counters are private", async () => {
    await seed(`users/${UID}/usage/${today()}`, {income: 1, lastTxId: "x"});
    const other = env.authenticatedContext("mallory").firestore();
    await assertFails(setDoc(doc(other, `users/${UID}/usage/${today()}`), {
      income: increment(1), lastTxId: "y", updatedAt: serverTimestamp(),
    }, {merge: true}));
  });
});
