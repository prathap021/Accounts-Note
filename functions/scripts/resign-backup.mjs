// Re-signs an Accounts Note backup file with this project's current key, so
// a backup made on another Firebase project (or before a key change) can be
// imported. The key is read from standard input and never printed:
//
//   firebase functions:secrets:access BACKUP_SIGNING_KEY --project <id> \
//     | node functions/scripts/resign-backup.mjs <backup.json> <output.json>
//
// The file's contents are not changed, only its signature.
import {createHmac} from "node:crypto";
import {readFileSync, writeFileSync} from "node:fs";

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error("Usage: ... | node resign-backup.mjs <backup.json> <output.json>");
  process.exit(2);
}

let key = readFileSync(0, "utf8");
if (key.endsWith("\n")) key = key.slice(0, -1);
if (key.length < 16) {
  console.error("No signing key on standard input.");
  process.exit(1);
}

const file = JSON.parse(readFileSync(input, "utf8"));
if (file.format !== "accounts-note-backup" || typeof file.data !== "string") {
  console.error("That is not an Accounts Note backup file.");
  process.exit(1);
}
const payload = JSON.parse(Buffer.from(file.data, "base64").toString("utf8"));
const counts = Object.fromEntries(
  Object.entries(payload.collections ?? {}).map(([k, v]) => [k, v.length]));

file.signature = createHmac("sha256", key).update(file.data).digest("hex");
writeFileSync(output, JSON.stringify(file));
console.log("Re-signed backup written to", output);
console.log("Exported", payload.exportedAt, "with", counts);
