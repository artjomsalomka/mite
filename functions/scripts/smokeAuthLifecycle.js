/* eslint-disable no-console */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

require("./localSmokeEnvironment").configureLocalSmokeEnvironment();

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const adminAuth = getAuth();
const authBase = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const identityBase = `${authBase}/identitytoolkit.googleapis.com/v1/accounts`;

async function post(path, body) {
  const response = await fetch(`${identityBase}:${path}?key=local`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20_000),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`${path}: ${JSON.stringify(data)}`);
  return data;
}

async function oobCode(requestType, email) {
  const response = await fetch(`${authBase}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/oobCodes`, {
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) throw new Error(`oobCodes: HTTP ${response.status}`);
  const data = await response.json();
  const entry = [...(data.oobCodes ?? [])].reverse().find(
    (code) => code.requestType === requestType && code.email === email,
  );
  assert.ok(entry?.oobCode, `Missing ${requestType} out-of-band code for ${email}`);
  return entry.oobCode;
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const email = `auth-smoke-${marker}@example.test`;
  const firstPassword = `Start-${marker}!`;
  const nextPassword = `Reset-${marker}!`;
  let uid;

  try {
    const registered = await post("signUp", { email, password: firstPassword, returnSecureToken: true });
    uid = registered.localId;
    assert.ok(registered.idToken);
    assert.equal(registered.email, email);

    const signedIn = await post("signInWithPassword", { email, password: firstPassword, returnSecureToken: true });
    assert.equal(signedIn.localId, uid);

    await post("sendOobCode", { requestType: "VERIFY_EMAIL", idToken: registered.idToken });
    await post("update", { oobCode: await oobCode("VERIFY_EMAIL", email) });
    assert.equal((await adminAuth.getUser(uid)).emailVerified, true);

    await post("sendOobCode", { requestType: "PASSWORD_RESET", email });
    await post("resetPassword", {
      oobCode: await oobCode("PASSWORD_RESET", email),
      newPassword: nextPassword,
    });
    const resetSignIn = await post("signInWithPassword", { email, password: nextPassword, returnSecureToken: true });
    assert.equal(resetSignIn.localId, uid);

    await adminAuth.deleteUser(uid);
    uid = undefined;
    console.log("Authentication lifecycle smoke test passed.");
  } catch (error) {
    if (uid) await adminAuth.deleteUser(uid).catch(() => {});
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
