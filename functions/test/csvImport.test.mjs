// CSV import, against the Firestore emulator.
//
// From the repo root:
//   cd functions && npm run build && cd .. && \
//   firebase emulators:exec --only firestore --project demo-accounts-note \
//     "node --test functions/test/*.test.mjs"

import {after, before, beforeEach, describe, test} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
const csv = require("../lib/csvImport.js");

let db;
const NOW = new Date("2026-11-07T10:00:00Z");

before(() => {
  if (getApps().length === 0) initializeApp({projectId: "demo-accounts-note"});
  db = getFirestore();
});

after(async () => {
  await db.terminate();
});

beforeEach(async () => {
  await db.recursiveDelete(db.doc("users/meera"));
  await db.doc("users/meera").set({email: "meera@example.com"});
  await db.doc("users/meera/categories/food").set({
    name: "Food", type: "expense", icon: "restaurant", color: 1,
    isDefault: true, isArchived: false, createdAt: Timestamp.now(),
  });
  await db.doc("users/meera/accounts/sbi").set({
    name: "SBI savings", kind: "bank", openingBalance: 0,
    createdAt: Timestamp.now(),
  });
});

const row = (over = {}) => ({
  type: "expense", amount: 250, date: Date.UTC(2026, 9, 3, 8),
  category: "food", note: "Lunch", paymentMethod: "UPI", account: null,
  ...over,
});

describe("CSV import", () => {
  test("adds rows, reusing categories and accounts by name", async () => {
    const result = await csv.importRows(db, "meera", [
      row(),
      row({type: "income", amount: 42000, category: "Salary", note: null,
        account: "sbi SAVINGS"}),
      row({amount: -5}), // not an amount
      row({type: "transfer"}), // not a type
    ], 330, NOW);
    assert.deepEqual(result, {
      added: 2, alreadyThere: 0, categoriesAdded: 1,
      remainingThisMonth: 418,
    });
    const all = await db.collection("users/meera/transactions").get();
    const lunch = all.docs.find((d) => d.get("note") === "Lunch").data();
    assert.equal(lunch.categoryId, "food", "matched Food ignoring case");
    assert.equal(lunch.categoryName, "Food");
    assert.equal(lunch.date.toMillis(), Date.UTC(2026, 9, 3, 8));
    assert.equal(lunch.createdTzOffsetMinutes, 330);
    const salary = all.docs.find((d) => d.get("type") === "income").data();
    assert.equal(salary.accountId, "sbi");
    const usage = await db.collection("users/meera/usage").get();
    assert.equal(usage.size, 0, "the daily counter is untouched");
  });

  test("the same file twice adds nothing, but repeats in it are kept",
    async () => {
      const file = [row(), row(), row({amount: 99})];
      const first = await csv.importRows(db, "meera", file, 0, NOW);
      assert.equal(first.added, 3);
      const again = await csv.importRows(db, "meera", file, 0, NOW);
      assert.equal(again.added, 0);
      assert.equal(again.alreadyThere, 3);
      assert.equal(again.remainingThisMonth, 417);
    });

  test("a free plan imports up to 420 rows a month", async () => {
    const many = (n, from) => Array.from({length: n}, (_, i) =>
      row({amount: from + i}));
    await csv.importRows(db, "meera", many(400, 1), 0, NOW);
    await assert.rejects(
      csv.importRows(db, "meera", many(30, 1000), 0, NOW),
      /30 new entries, and your plan can import 20 more this month/);
    const all = await db.collection("users/meera/transactions").get();
    assert.equal(all.size, 400, "nothing written when over the allowance");
    // Next month the allowance is back.
    const dec = new Date("2026-12-01T10:00:00Z");
    const later = await csv.importRows(db, "meera", many(30, 1000), 0, dec);
    assert.equal(later.added, 30);
  });

  test("a paid plan imports its monthly total", async () => {
    await db.doc("users/meera").set({
      subscriptionPlan: "premium", subscriptionStatus: "active",
      subscriptionExpiresAt: Timestamp.fromDate(new Date("2027-01-01")),
    }, {merge: true});
    const result = await csv.importRows(db, "meera",
      Array.from({length: 500}, (_, i) => row({amount: i + 1})), 0, NOW);
    assert.equal(result.added, 500);
    assert.equal(result.remainingThisMonth, 5500);
  });

  test("a file with nothing usable is refused", async () => {
    await assert.rejects(csv.importRows(db, "meera", [row({amount: 0})], 0,
      NOW), /no entries/);
    await assert.rejects(csv.importRows(db, "meera", "rows", 0, NOW),
      /no entries/);
  });
});
