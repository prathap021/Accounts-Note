/**
 * Importing entries from a CSV file (another app's export, a bank statement,
 * or this app's own report).
 *
 * The app reads the file and shows a preview; the rows it sends here are
 * checked again and written with the admin SDK, because the security rules
 * only accept a new entry alongside its day's counter bump. So the daily
 * limit cannot be dodged with a hand-made file, imports have their own
 * allowance: the plan's monthly total, per calendar month.
 *
 * Each row gets an id made from its contents, so importing the same file
 * again adds nothing.
 */
import * as functions from "firebase-functions/v1";
import {
  getFirestore,
  Firestore,
  Timestamp,
  FieldValue,
} from "firebase-admin/firestore";
import {createHash} from "crypto";

/** Rows importable per calendar month: the plan's monthly total. */
export const MONTHLY_IMPORT_ROWS: Record<string, number> = {
  free: 420,
  basic: 1800,
  standard: 3600,
  premium: 6000,
};

/** Most rows accepted in one call. */
export const MAX_ROWS_PER_CALL = 6000;

export interface CsvRow {
  type: "income" | "expense";
  amount: number;
  /** Epoch milliseconds. */
  date: number;
  category: string;
  note: string | null;
  paymentMethod: string | null;
  account: string | null;
}

export interface CsvImportResult {
  added: number;
  alreadyThere: number;
  categoriesAdded: number;
  remainingThisMonth: number;
}

const str = (v: unknown, max: number): string | null => {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length === 0 ? null : t.slice(0, max);
};

/**
 * The rows that are well-formed; anything else is dropped.
 * @param {unknown} input What the app sent.
 * @param {Date} now The current time.
 * @return {CsvRow[]} Valid rows.
 */
export function validRows(input: unknown, now = new Date()): CsvRow[] {
  if (!Array.isArray(input)) return [];
  const earliest = Date.UTC(1990, 0, 1);
  const latest = now.getTime() + 366 * 24 * 3600 * 1000;
  const rows: CsvRow[] = [];
  for (const r of input.slice(0, MAX_ROWS_PER_CALL)) {
    if (!r || typeof r !== "object") continue;
    const o = r as Record<string, unknown>;
    if (o.type !== "income" && o.type !== "expense") continue;
    const amount = o.amount;
    if (typeof amount !== "number" || !Number.isFinite(amount) ||
      amount <= 0 || amount >= 1e12) continue;
    const date = o.date;
    if (typeof date !== "number" || !Number.isFinite(date) ||
      date < earliest || date > latest) continue;
    rows.push({
      type: o.type,
      amount: Math.round(amount * 100) / 100,
      date,
      category: str(o.category, 50) ?? "Other",
      note: str(o.note, 500),
      paymentMethod: str(o.paymentMethod, 40),
      account: str(o.account, 100),
    });
  }
  return rows;
}

/**
 * Stable id for a row: the same file imported twice maps to the same ids.
 * [occurrence] tells identical rows in one file apart.
 * @param {CsvRow} row The row.
 * @param {number} occurrence How many identical rows came before it.
 * @return {string} A Firestore doc id.
 */
export function rowId(row: CsvRow, occurrence: number): string {
  const key = [row.type, row.amount, row.date, row.category.toLowerCase(),
    row.note ?? "", occurrence].join("|");
  return "csv-" + createHash("sha256").update(key).digest("hex").slice(0, 32);
}

/**
 * The plan whose limits apply now. Mirrors dailyLimit() in firestore.rules.
 * @param {FirebaseFirestore.DocumentData | undefined} user The profile.
 * @param {Date} now The current time.
 * @return {string} free, basic, standard or premium.
 */
export function planOf(
  user: FirebaseFirestore.DocumentData | undefined,
  now = new Date(),
): string {
  const plan = user?.subscriptionPlan;
  const status = user?.subscriptionStatus;
  const expires = (user?.subscriptionExpiresAt as Timestamp | undefined)
    ?.toDate();
  const live = ["active", "grace", "canceled"].includes(status) &&
    expires !== undefined && expires > now;
  return live && typeof plan === "string" && plan in MONTHLY_IMPORT_ROWS ?
    plan : "free";
}

/**
 * Adds [input] to the user's entries.
 * @param {Firestore} db Firestore.
 * @param {string} uid The user.
 * @param {unknown} input Rows from the app.
 * @param {number} tzOffsetMinutes The phone's offset from UTC.
 * @param {Date} now The current time.
 * @return {Promise<CsvImportResult>} What changed.
 */
export async function importRows(
  db: Firestore,
  uid: string,
  input: unknown,
  tzOffsetMinutes: number,
  now = new Date(),
): Promise<CsvImportResult> {
  const base = `users/${uid}`;
  const rows = validRows(input, now);
  if (rows.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument", "The file has no entries that can be imported.");
  }

  // Ids, skipping rows already imported.
  const seen = new Map<string, number>();
  const withIds = rows.map((row) => {
    const sig = rowId(row, 0);
    const n = seen.get(sig) ?? 0;
    seen.set(sig, n + 1);
    return {row, id: rowId(row, n)};
  });
  const existing = new Set<string>();
  for (let i = 0; i < withIds.length; i += 300) {
    const refs = withIds.slice(i, i + 300)
      .map((r) => db.doc(`${base}/transactions/${r.id}`));
    for (const snap of await db.getAll(...refs)) {
      if (snap.exists) existing.add(snap.id);
    }
  }
  const fresh = withIds.filter((r) => !existing.has(r.id));

  // This month's allowance, reserved before anything is written.
  const month = now.toISOString().slice(0, 7);
  const counterRef = db.doc(`${base}/importUsage/${month}`);
  const user = (await db.doc(base).get()).data();
  const limit = MONTHLY_IMPORT_ROWS[planOf(user, now)];
  const remaining = await db.runTransaction(async (tx) => {
    const used = ((await tx.get(counterRef)).get("rows") as number) ?? 0;
    const left = limit - used;
    if (fresh.length > left) {
      throw new functions.https.HttpsError("resource-exhausted",
        `This file has ${fresh.length} new entries, and your plan can ` +
        `import ${Math.max(0, left)} more this month.`);
    }
    if (fresh.length > 0) {
      tx.set(counterRef, {rows: used + fresh.length,
        updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    return left - fresh.length;
  });

  // Categories by name and type; new names are created.
  const writes: Array<[string, Record<string, unknown>]> = [];
  const cats = await db.collection(`${base}/categories`).get();
  const catByKey = new Map<string, {id: string; name: string}>();
  for (const d of cats.docs) {
    catByKey.set(`${d.get("type")}|${String(d.get("name")).trim()
      .toLowerCase()}`, {id: d.id, name: String(d.get("name"))});
  }
  let categoriesAdded = 0;
  const categoryFor = (type: string, name: string) => {
    const key = `${type}|${name.toLowerCase()}`;
    let found = catByKey.get(key);
    if (!found) {
      const id = db.collection(`${base}/categories`).doc().id;
      found = {id, name};
      catByKey.set(key, found);
      writes.push([`${base}/categories/${id}`, {
        name, type, icon: "category", color: 0xFF64748B,
        isDefault: false, isArchived: false,
        createdAt: Timestamp.fromDate(now),
      }]);
      categoriesAdded++;
    }
    return found;
  };

  // Accounts by name; an unknown name is kept only as the payment method.
  const accounts = await db.collection(`${base}/accounts`).get();
  const accountByName = new Map<string, {id: string; name: string}>();
  for (const d of accounts.docs) {
    accountByName.set(String(d.get("name")).trim().toLowerCase(),
      {id: d.id, name: String(d.get("name"))});
  }

  const created = Timestamp.fromDate(now);
  for (const {row, id} of fresh) {
    const cat = categoryFor(row.type, row.category);
    const account = row.account ?
      accountByName.get(row.account.toLowerCase()) : undefined;
    writes.push([`${base}/transactions/${id}`, {
      type: row.type,
      amount: row.amount,
      categoryId: cat.id,
      categoryName: cat.name,
      note: row.note,
      date: Timestamp.fromMillis(row.date),
      paymentMethod: row.paymentMethod ?? "Other",
      creditCardId: null,
      creditCardName: null,
      accountId: account?.id ?? null,
      accountName: account?.name ?? null,
      isRecurring: false,
      recurringId: null,
      createdAt: created,
      updatedAt: created,
      createdTzOffsetMinutes: tzOffsetMinutes,
      importedAt: FieldValue.serverTimestamp(),
    }]);
  }

  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const [path, data] of writes.slice(i, i + 400)) {
      batch.set(db.doc(path), data, {merge: true});
    }
    await batch.commit();
  }

  return {
    added: fresh.length,
    alreadyThere: existing.size,
    categoriesAdded,
    remainingThisMonth: remaining,
  };
}

/** Callable. Imports rows the app read from a CSV file. */
export const importCsvRows = functions
  .runWith({invoker: "public", timeoutSeconds: 300, memory: "512MB"})
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated", "Sign in required.");
    }
    const offset = typeof data?.tzOffsetMinutes === "number" &&
      Math.abs(data.tzOffsetMinutes) <= 14 * 60 ?
      Math.round(data.tzOffsetMinutes) : 0;
    return importRows(getFirestore(), context.auth.uid, data?.rows, offset);
  });
