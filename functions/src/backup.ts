/**
 * Backups: one file with a user's transactions, categories, credit cards and
 * budgets, which can be imported into the same account or another one.
 *
 * Files are built and signed here, never by the app. Importing writes past
 * the daily entry limit (those entries were counted when they were first
 * made), so only a file this server signed, unchanged, may be imported;
 * otherwise anyone could hand-write a "backup" to get round the limit.
 *
 * Secret: BACKUP_SIGNING_KEY (any long random string). Changing it makes
 * older backup files unimportable.
 */
import * as functions from "firebase-functions/v1";
import {
  getFirestore,
  Firestore,
  Timestamp,
  FieldValue,
} from "firebase-admin/firestore";
import {createHmac, timingSafeEqual} from "crypto";
import {runAs} from "./runtime";

export const BACKUP_FORMAT = "accounts-note-backup";
export const BACKUP_VERSION = 1;

const COLLECTIONS = [
  "categories",
  "creditCards",
  "accounts",
  "budgets",
  "transactions",
  "transfers",
] as const;
type Collection = typeof COLLECTIONS[number];

/** Largest file accepted: the callable request limit is 10 MB. */
const MAX_CONTENT_BYTES = 9 * 1024 * 1024;

/** Firestore ids made by the app: auto ids, uuids, `2026-09_cat` keys. */
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

interface Doc {
  id: string;
  data: Record<string, unknown>;
}

/** What a backup holds. Signed as one JSON string. */
export interface BackupPayload {
  version: number;
  exportedAt: string;
  sourceUid: string;
  sourceEmail: string | null;
  currency: string | null;
  collections: Record<Collection, Doc[]>;
}

/** The file: the payload base64-encoded, so its bytes survive any reader. */
export interface BackupFile {
  format: string;
  version: number;
  data: string;
  signature: string;
}

export interface ImportResult {
  transactionsAdded: number;
  transactionsAlreadyThere: number;
  categoriesAdded: number;
  creditCardsAdded: number;
  budgetsImported: number;
  accountsAdded: number;
  transfersAdded: number;
}

// --------------------------------------------------------------- encoding

/**
 * Firestore values to plain JSON: timestamps become {"__ts": millis}.
 * @param {unknown} value A Firestore value.
 * @return {unknown} The JSON-safe value.
 */
export function encodeValue(value: unknown): unknown {
  if (value instanceof Timestamp) return {__ts: value.toMillis()};
  if (Array.isArray(value)) return value.map(encodeValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, encodeValue(v)]));
  }
  return value;
}

/**
 * The reverse of [encodeValue].
 * @param {unknown} value A JSON value from a backup.
 * @return {unknown} The Firestore value.
 */
export function decodeValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(decodeValue);
  if (value && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    const keys = Object.keys(obj);
    if (keys.length === 1 && keys[0] === "__ts" &&
        typeof obj.__ts === "number") {
      return Timestamp.fromMillis(obj.__ts);
    }
    return Object.fromEntries(
      Object.entries(obj).map(([k, v]) => [k, decodeValue(v)]));
  }
  return value;
}

/**
 * HMAC-SHA256 of [data] under [secret], hex.
 * @param {string} data The signed text.
 * @param {string} secret The signing key.
 * @return {string} The signature.
 */
export function sign(data: string, secret: string): string {
  return createHmac("sha256", secret).update(data).digest("hex");
}

/**
 * Builds the signed file text for [payload].
 * @param {BackupPayload} payload What to back up.
 * @param {string} secret The signing key.
 * @return {string} The file's contents.
 */
export function encodeBackup(payload: BackupPayload, secret: string): string {
  const data = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
  const file: BackupFile = {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    data,
    signature: sign(data, secret),
  };
  return JSON.stringify(file);
}

/**
 * Checks a file's format and signature and returns its payload.
 * @param {string} content The file's contents.
 * @param {string | string[]} secrets The signing key, or every key a file
 *   may have been signed with (the current one and earlier ones).
 * @return {BackupPayload} The payload.
 */
export function decodeBackup(
  content: string,
  secrets: string | string[],
): BackupPayload {
  const invalid = (why: string) =>
    new functions.https.HttpsError("invalid-argument", why);
  if (typeof content !== "string" || !content) {
    throw invalid("That is not an Accounts Note backup file.");
  }
  if (Buffer.byteLength(content, "utf8") > MAX_CONTENT_BYTES) {
    throw invalid("This backup file is too large to import.");
  }
  let file: BackupFile;
  try {
    file = JSON.parse(content);
  } catch {
    throw invalid("That is not an Accounts Note backup file.");
  }
  if (file?.format !== BACKUP_FORMAT || typeof file.data !== "string" ||
      typeof file.signature !== "string") {
    throw invalid("That is not an Accounts Note backup file.");
  }
  if (file.version > BACKUP_VERSION) {
    throw invalid("This backup was made by a newer version of the app. " +
      "Update the app, then try again.");
  }
  const given = Buffer.from(file.signature, "hex");
  const signedByUs = (Array.isArray(secrets) ? secrets : [secrets])
    .some((secret) => {
      const expected = Buffer.from(sign(file.data, secret), "hex");
      return given.length === expected.length &&
        timingSafeEqual(given, expected);
    });
  if (!signedByUs) {
    throw invalid("This backup file has been changed or damaged, so it " +
      "cannot be imported.");
  }
  return JSON.parse(Buffer.from(file.data, "base64").toString("utf8"));
}

// ----------------------------------------------------------------- export

/**
 * Reads everything a backup holds for [uid].
 * @param {Firestore} db Firestore.
 * @param {string} uid The account.
 * @param {string | null} email Shown in the import preview.
 * @param {string | null} currency The app's currency, as the app reports it.
 * @return {Promise<BackupPayload>} The payload.
 */
export async function readBackup(
  db: Firestore,
  uid: string,
  email: string | null,
  currency: string | null,
): Promise<BackupPayload> {
  const collections = {} as Record<Collection, Doc[]>;
  for (const name of COLLECTIONS) {
    const snap = await db.collection(`users/${uid}/${name}`).get();
    collections[name] = snap.docs.map((d) => ({
      id: d.id,
      data: encodeValue(d.data()) as Record<string, unknown>,
    }));
  }
  return {
    version: BACKUP_VERSION,
    exportedAt: new Date().toISOString(),
    sourceUid: uid,
    sourceEmail: email,
    currency,
    collections,
  };
}

// ----------------------------------------------------------------- import

const str = (v: unknown) => (typeof v === "string" ? v : "");

/**
 * Adds a backup's contents to [uid]'s account.
 *
 * Merges, never replaces: categories and cards that already exist (same
 * name and type, same name and last four digits) are reused, and every
 * imported entry is pointed at them. Transactions keep their ids, so
 * importing the same file twice adds nothing the second time. The daily
 * entry counters are not touched.
 * @param {Firestore} db Firestore.
 * @param {string} uid The account importing.
 * @param {BackupPayload} payload A verified backup.
 * @return {Promise<ImportResult>} What changed.
 */
export async function applyBackup(
  db: Firestore,
  uid: string,
  payload: BackupPayload,
): Promise<ImportResult> {
  const base = `users/${uid}`;
  const docsOf = (name: Collection) =>
    (payload.collections?.[name] ?? []).filter(
      (d) => d && ID_PATTERN.test(str(d.id)) &&
        d.data && typeof d.data === "object");

  const writes: Array<[string, Record<string, unknown>]> = [];
  const result: ImportResult = {
    transactionsAdded: 0,
    transactionsAlreadyThere: 0,
    categoriesAdded: 0,
    creditCardsAdded: 0,
    budgetsImported: 0,
    accountsAdded: 0,
    transfersAdded: 0,
  };

  // Categories: reuse the target's own by name and type.
  const existingCats = await db.collection(`${base}/categories`).get();
  const catByKey = new Map<string, string>();
  const catIds = new Set<string>();
  for (const d of existingCats.docs) {
    catIds.add(d.id);
    catByKey.set(`${str(d.get("type"))}|${str(d.get("name")).trim()
      .toLowerCase()}`, d.id);
  }
  const catMap = new Map<string, string>();
  for (const c of docsOf("categories")) {
    const key = `${str(c.data.type)}|${str(c.data.name).trim().toLowerCase()}`;
    const found = catByKey.get(key);
    if (found) {
      catMap.set(c.id, found);
      continue;
    }
    const id = catIds.has(c.id) ?
      db.collection(`${base}/categories`).doc().id : c.id;
    catIds.add(id);
    catByKey.set(key, id);
    catMap.set(c.id, id);
    writes.push([`${base}/categories/${id}`,
      {...(decodeValue(c.data) as Record<string, unknown>), isDefault: false}]);
    result.categoriesAdded++;
  }

  // Credit cards: reuse by name and last four.
  const existingCards = await db.collection(`${base}/creditCards`).get();
  const cardByKey = new Map<string, string>();
  const cardIds = new Set<string>();
  for (const d of existingCards.docs) {
    cardIds.add(d.id);
    cardByKey.set(`${str(d.get("name")).trim().toLowerCase()}|` +
      `${str(d.get("last4"))}`, d.id);
  }
  const cardMap = new Map<string, string>();
  for (const c of docsOf("creditCards")) {
    const key = `${str(c.data.name).trim().toLowerCase()}|${str(c.data.last4)}`;
    const found = cardByKey.get(key);
    if (found) {
      cardMap.set(c.id, found);
      continue;
    }
    const id = cardIds.has(c.id) ?
      db.collection(`${base}/creditCards`).doc().id : c.id;
    cardIds.add(id);
    cardByKey.set(key, id);
    cardMap.set(c.id, id);
    writes.push([`${base}/creditCards/${id}`,
      decodeValue(c.data) as Record<string, unknown>]);
    result.creditCardsAdded++;
  }

  // Accounts: reuse by name and kind. A backup from before accounts
  // existed has none, and nothing changes.
  const existingAccounts = await db.collection(`${base}/accounts`).get();
  const accountByKey = new Map<string, string>();
  const accountIds = new Set<string>();
  for (const d of existingAccounts.docs) {
    accountIds.add(d.id);
    accountByKey.set(`${str(d.get("name")).trim().toLowerCase()}|` +
      `${str(d.get("kind"))}`, d.id);
  }
  const accountMap = new Map<string, string>();
  for (const a of docsOf("accounts")) {
    const key = `${str(a.data.name).trim().toLowerCase()}|${str(a.data.kind)}`;
    const found = accountByKey.get(key);
    if (found) {
      accountMap.set(a.id, found);
      continue;
    }
    const id = accountIds.has(a.id) ?
      db.collection(`${base}/accounts`).doc().id : a.id;
    accountIds.add(id);
    accountByKey.set(key, id);
    accountMap.set(a.id, id);
    writes.push([`${base}/accounts/${id}`,
      decodeValue(a.data) as Record<string, unknown>]);
    result.accountsAdded++;
  }
  const mapAccount = (v: unknown) =>
    typeof v === "string" ? (accountMap.get(v) ?? v) : null;

  // Transfers: same ids, pointed at the target's accounts.
  const existingTransfers = await db.collection(`${base}/transfers`)
    .select().get();
  const transferIds = new Set(existingTransfers.docs.map((d) => d.id));
  for (const t of docsOf("transfers")) {
    const data = decodeValue(t.data) as Record<string, unknown>;
    if (typeof data.amount !== "number" || !(data.amount > 0)) continue;
    if (transferIds.has(t.id)) continue;
    writes.push([`${base}/transfers/${t.id}`, {
      ...data,
      fromAccountId: mapAccount(data.fromAccountId),
      toAccountId: mapAccount(data.toAccountId),
    }]);
    result.transfersAdded++;
  }

  // Budgets: keyed by month and category, as the app keys them.
  for (const b of docsOf("budgets")) {
    const data = decodeValue(b.data) as Record<string, unknown>;
    const period = str(data.period);
    if (!/^\d{4}-\d{2}$/.test(period)) continue;
    const oldCat = typeof data.categoryId === "string" ? data.categoryId : null;
    const catId = oldCat ? (catMap.get(oldCat) ?? oldCat) : null;
    writes.push([`${base}/budgets/${period}_${catId ?? "overall"}`,
      {...data, categoryId: catId}]);
    result.budgetsImported++;
  }

  // Transactions: same ids, pointed at the target's categories and cards.
  const existingTx = await db.collection(`${base}/transactions`)
    .select().get();
  const txIds = new Set(existingTx.docs.map((d) => d.id));
  for (const t of docsOf("transactions")) {
    const data = decodeValue(t.data) as Record<string, unknown>;
    if (data.type !== "income" && data.type !== "expense") continue;
    if (typeof data.amount !== "number" || !(data.amount > 0)) continue;
    const oldCat = str(data.categoryId);
    const oldCard = typeof data.creditCardId === "string" ?
      data.creditCardId : null;
    if (txIds.has(t.id)) {
      result.transactionsAlreadyThere++;
      continue;
    }
    writes.push([`${base}/transactions/${t.id}`, {
      ...data,
      categoryId: catMap.get(oldCat) ?? oldCat,
      creditCardId: oldCard ? (cardMap.get(oldCard) ?? oldCard) : null,
      accountId: mapAccount(data.accountId),
      importedAt: FieldValue.serverTimestamp(),
    }]);
    result.transactionsAdded++;
  }

  // Firestore batches hold up to 500 writes.
  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    for (const [path, data] of writes.slice(i, i + 400)) {
      batch.set(db.doc(path), data, {merge: true});
    }
    await batch.commit();
  }
  return result;
}

// -------------------------------------------------------------- functions

const backupOptions = {
  ...runAs,
  secrets: ["BACKUP_SIGNING_KEY"],
  invoker: "public" as const,
  timeoutSeconds: 300,
  memory: "512MB" as const,
};


/**
 * The signing key.
 * @return {string} The key.
 */
function signingKey(): string {
  const key = process.env.BACKUP_SIGNING_KEY;
  if (!key || key.length < 16) {
    throw new functions.https.HttpsError(
      "failed-precondition", "Backups are not set up on the server yet.");
  }
  return key;
}

/**
 * Every key an imported file may be signed with: the current one, then an
 * earlier one if BACKUP_SIGNING_KEY_PREVIOUS is set (it then also needs
 * adding to backupOptions.secrets). Old backups can instead be re-signed
 * with scripts/resign-backup.mjs.
 * @return {string[]} The keys.
 */
function acceptedKeys(): string[] {
  const previous = process.env.BACKUP_SIGNING_KEY_PREVIOUS;
  return [signingKey(),
    ...(previous && previous.length >= 16 ? [previous] : [])];
}

/** Callable. Returns the signed backup file for the caller's account. */
export const createBackup = functions
  .runWith(backupOptions)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated", "Sign in required.");
    }
    const uid = context.auth.uid;
    const currency = typeof data?.currency === "string" ?
      data.currency.slice(0, 8) : null;
    const payload = await readBackup(getFirestore(), uid,
      (context.auth.token.email as string | undefined) ?? null, currency);
    const content = encodeBackup(payload, signingKey());
    if (Buffer.byteLength(content, "utf8") > MAX_CONTENT_BYTES) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "This account has too much data for one backup file.");
    }
    return {
      content,
      transactions: payload.collections.transactions.length,
    };
  });

/** Callable. Adds a signed backup's contents to the caller's account. */
export const importBackup = functions
  .runWith(backupOptions)
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated", "Sign in required.");
    }
    const payload = decodeBackup(data?.content, acceptedKeys());
    return applyBackup(getFirestore(), context.auth.uid, payload);
  });
