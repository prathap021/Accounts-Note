// Backup export and import, against the Firestore emulator.
//
// From the repo root:
//   cd functions && npm run build && cd .. && \
//   firebase emulators:exec --only firestore --project demo-accounts-note \
//     "node --test functions/test"

import {after, before, beforeEach, describe, test} from "node:test";
import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

const require = createRequire(import.meta.url);
const backup = require("../lib/backup.js");

const SECRET = "test-signing-key-0123456789";
let db;

before(() => {
  initializeApp({projectId: "demo-accounts-note"});
  db = getFirestore();
});

after(async () => {
  await db.terminate();
});

async function clear() {
  for (const uid of ["asha", "ravi"]) {
    await db.recursiveDelete(db.doc(`users/${uid}`));
  }
}

beforeEach(clear);

const ts = (iso) => Timestamp.fromDate(new Date(iso));

/** Asha's account: two categories, a card, a budget and three entries. */
async function seedAsha() {
  const u = "users/asha";
  await db.doc(u).set({email: "asha@example.com"});
  await db.doc(`${u}/categories/food-a`).set({
    name: "Food", type: "expense", icon: "restaurant", color: 1,
    isDefault: true, isArchived: false, createdAt: ts("2025-01-01"),
  });
  await db.doc(`${u}/categories/pets-a`).set({
    name: "Pets", type: "expense", icon: "pets", color: 2,
    isDefault: false, isArchived: false, createdAt: ts("2025-02-01"),
  });
  await db.doc(`${u}/categories/salary-a`).set({
    name: "Salary", type: "income", icon: "work", color: 3,
    isDefault: true, isArchived: false, createdAt: ts("2025-01-01"),
  });
  await db.doc(`${u}/creditCards/card-a`).set({
    name: "HDFC Millennia", last4: "4321", color: 4, createdAt: ts("2025-03-01"),
  });
  await db.doc(`${u}/accounts/sbi-a`).set({
    name: "SBI savings", kind: "bank", openingBalance: 10000,
    createdAt: ts("2025-03-01"),
  });
  await db.doc(`${u}/accounts/cash-a`).set({
    name: "Cash in hand", kind: "cash", openingBalance: 0,
    createdAt: ts("2025-03-01"),
  });
  await db.doc(`${u}/transfers/x1`).set({
    fromAccountId: "sbi-a", toAccountId: "cash-a",
    fromAccountName: "SBI savings", toAccountName: "Cash in hand",
    amount: 2000, date: ts("2026-10-04"), note: "ATM",
    createdAt: ts("2026-10-04"),
  });
  await db.doc(`${u}/budgets/2026-10_food-a`).set({
    period: "2026-10", categoryId: "food-a", limit: 5000,
  });
  const tx = (id, data) => db.doc(`${u}/transactions/${id}`).set({
    amount: 100, note: null, paymentMethod: "Cash", isRecurring: false,
    createdAt: ts("2026-10-05"), updatedAt: ts("2026-10-05"),
    createdTzOffsetMinutes: 330, ...data,
  });
  await tx("t1", {type: "income", amount: 50000, categoryId: "salary-a",
    categoryName: "Salary", date: ts("2026-10-01")});
  await tx("t2", {type: "expense", amount: 450, categoryId: "food-a",
    categoryName: "Food", date: ts("2026-10-02"), accountId: "cash-a",
    accountName: "Cash in hand"});
  await tx("t3", {type: "expense", amount: 1200, categoryId: "pets-a",
    categoryName: "Pets", date: ts("2026-10-03"), paymentMethod: "Credit Card",
    creditCardId: "card-a", creditCardName: "HDFC Millennia ••4321"});
}

/** Ravi already has his own Food category, under another id. */
async function seedRavi() {
  await db.doc("users/ravi").set({email: "ravi@example.com"});
  await db.doc("users/ravi/categories/food-r").set({
    name: "Food", type: "expense", icon: "restaurant", color: 9,
    isDefault: true, isArchived: false, createdAt: ts("2026-01-01"),
  });
  await db.doc("users/ravi/accounts/cash-r").set({
    name: "Cash in hand", kind: "cash", openingBalance: 500,
    createdAt: ts("2026-01-01"),
  });
}

async function exportAsha() {
  const payload = await backup.readBackup(db, "asha", "asha@example.com", "INR");
  return backup.encodeBackup(payload, SECRET);
}

describe("backup files", () => {
  test("timestamps survive the trip through JSON", () => {
    const t = ts("2026-10-05T10:30:00Z");
    const back = backup.decodeValue(
      JSON.parse(JSON.stringify(backup.encodeValue({at: t, n: [t]}))));
    assert.equal(back.at.toMillis(), t.toMillis());
    assert.equal(back.n[0].toMillis(), t.toMillis());
  });

  test("a backup holds every collection, signed", async () => {
    await seedAsha();
    const file = JSON.parse(await exportAsha());
    assert.equal(file.format, "accounts-note-backup");
    const payload = backup.decodeBackup(JSON.stringify(file), SECRET);
    assert.equal(payload.sourceEmail, "asha@example.com");
    assert.equal(payload.currency, "INR");
    assert.equal(payload.collections.transactions.length, 3);
    assert.equal(payload.collections.categories.length, 3);
    assert.equal(payload.collections.creditCards.length, 1);
    assert.equal(payload.collections.budgets.length, 1);
    assert.equal(payload.collections.accounts.length, 2);
    assert.equal(payload.collections.transfers.length, 1);
  });

  test("an edited file is refused", async () => {
    await seedAsha();
    const file = JSON.parse(await exportAsha());
    const payload = JSON.parse(Buffer.from(file.data, "base64").toString());
    payload.collections.transactions.push({id: "fake", data: {
      type: "expense", amount: 1, categoryId: "food-a", date: {__ts: 0}}});
    file.data = Buffer.from(JSON.stringify(payload)).toString("base64");
    assert.throws(() => backup.decodeBackup(JSON.stringify(file), SECRET),
      /changed or damaged/);
  });

  test("a file signed with another key is refused", async () => {
    await seedAsha();
    const content = await exportAsha();
    assert.throws(() => backup.decodeBackup(content, "another-key-0123456789"),
      /changed or damaged/);
  });

  test("anything else is not a backup", () => {
    assert.throws(() => backup.decodeBackup("hello", SECRET), /not an/);
    assert.throws(() => backup.decodeBackup("{}", SECRET), /not an/);
    assert.throws(() => backup.decodeBackup(JSON.stringify({
      format: "accounts-note-backup", version: 99, data: "", signature: "",
    }), SECRET), /newer version/);
  });
});

describe("importing into another account", () => {
  test("adds everything, reusing the target's matching categories", async () => {
    await seedAsha();
    await seedRavi();
    const payload = backup.decodeBackup(await exportAsha(), SECRET);
    const result = await backup.applyBackup(db, "ravi", payload);

    assert.deepEqual(result, {
      transactionsAdded: 3,
      transactionsAlreadyThere: 0,
      categoriesAdded: 2, // Pets and Salary; Food was already there
      creditCardsAdded: 1,
      budgetsImported: 1,
      accountsAdded: 1, // SBI; Ravi already keeps Cash in hand
      transfersAdded: 1,
    });

    const t2 = (await db.doc("users/ravi/transactions/t2").get()).data();
    assert.equal(t2.categoryId, "food-r", "points at Ravi's own Food");
    assert.equal(t2.amount, 450);
    assert.equal(t2.accountId, "cash-r", "points at Ravi's own cash");
    const x1 = (await db.doc("users/ravi/transfers/x1").get()).data();
    assert.equal(x1.fromAccountId, "sbi-a");
    assert.equal(x1.toAccountId, "cash-r");
    assert.equal(x1.amount, 2000);
    assert.ok(t2.date instanceof Timestamp);
    assert.equal(t2.date.toDate().toISOString(), "2026-10-02T00:00:00.000Z");

    const t3 = (await db.doc("users/ravi/transactions/t3").get()).data();
    assert.equal(t3.categoryId, "pets-a");
    assert.equal(t3.creditCardId, "card-a");
    assert.ok((await db.doc("users/ravi/categories/pets-a").get()).exists);
    assert.ok((await db.doc("users/ravi/creditCards/card-a").get()).exists);

    const budget = await db.doc("users/ravi/budgets/2026-10_food-r").get();
    assert.equal(budget.get("categoryId"), "food-r", "rekeyed to Ravi's Food");

    const usage = await db.collection("users/ravi/usage").get();
    assert.equal(usage.size, 0, "imported entries do not use today's allowance");
  });

  test("importing the same file twice adds nothing the second time",
    async () => {
      await seedAsha();
      await seedRavi();
      const payload = backup.decodeBackup(await exportAsha(), SECRET);
      await backup.applyBackup(db, "ravi", payload);
      const again = await backup.applyBackup(db, "ravi", payload);

      assert.equal(again.transactionsAdded, 0);
      assert.equal(again.transactionsAlreadyThere, 3);
      assert.equal(again.categoriesAdded, 0);
      assert.equal(again.creditCardsAdded, 0);
      assert.equal(again.accountsAdded, 0);
      assert.equal(again.transfersAdded, 0);
      const all = await db.collection("users/ravi/transactions").get();
      assert.equal(all.size, 3);
    });

  test("restoring into the same account changes nothing", async () => {
    await seedAsha();
    const payload = backup.decodeBackup(await exportAsha(), SECRET);
    const result = await backup.applyBackup(db, "asha", payload);
    assert.equal(result.transactionsAdded, 0);
    assert.equal(result.categoriesAdded, 0);
    assert.equal(result.transactionsAlreadyThere, 3);
  });
});
