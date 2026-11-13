import { chmodSync, existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Firebase's defineSecret() emulator override lives in .secret.local, not
// .env.local. Keep one user-edited OpenAI key and mirror it without logging it.
const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const functionsRoot = join(projectRoot, "functions");
const envPath = join(functionsRoot, ".env.local");
const secretPath = join(functionsRoot, ".secret.local");

if (!existsSync(envPath)) {
  throw new Error("functions/.env.local fehlt; lokaler OPENAI_API_KEY nicht konfiguriert.");
}

const keyLines = readFileSync(envPath, "utf8")
  .split(/\r?\n/)
  .filter((line) => line.startsWith("OPENAI_API_KEY="));
if (keyLines.length !== 1) {
  throw new Error("OPENAI_API_KEY muss genau einmal in functions/.env.local stehen.");
}

const key = keyLines[0].slice("OPENAI_API_KEY=".length).trim();
if (!key.startsWith("sk-") || /[\r\n\s]/.test(key)) {
  throw new Error("OPENAI_API_KEY in functions/.env.local hat kein gültiges Format.");
}

const existing = existsSync(secretPath) ? readFileSync(secretPath, "utf8") : "";
const otherLines = existing
  .split(/\r?\n/)
  .filter((line) => line.length > 0 && !line.startsWith("OPENAI_API_KEY="));
const next = [...otherLines, `OPENAI_API_KEY=${key}`].join("\n") + "\n";

if (existing !== next) {
  const temporaryPath = `${secretPath}.${process.pid}.tmp`;
  writeFileSync(temporaryPath, next, { mode: 0o600, flag: "wx" });
  renameSync(temporaryPath, secretPath);
}
chmodSync(secretPath, 0o600);
console.log("Lokale Firebase-Secrets sind bereit.");
