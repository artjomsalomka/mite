/* eslint-disable no-console */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

const { functionBase } = require("./localSmokeEnvironment").configureLocalSmokeEnvironment();

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();
const adminAuth = getAuth();

async function callable(name, token, data = {}) {
  const response = await fetch(`${functionBase}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(20_000),
  });
  const body = await response.json();
  if (!response.ok || body.error) throw new Error(`${name}: ${JSON.stringify(body.error || body)}`);
  return body.result ?? body.data;
}

async function signUp(email, password) {
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  const body = await response.json();
  if (!response.ok) throw new Error(`signup: ${JSON.stringify(body)}`);
  return body;
}

async function createUserProfile(uid, email, displayName) {
  await db.collection("users").doc(uid).set({
    displayName,
    email,
    authProvider: "password",
    dietaryDefault: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const password = `Smoke-${marker}!`;
  const firstEmail = `couple-a-${marker}@example.test`;
  const secondEmail = `couple-b-${marker}@example.test`;
  const first = await signUp(firstEmail, password);
  const second = await signUp(secondEmail, password);
  let coupleId;

  try {
    await Promise.all([
      createUserProfile(first.localId, firstEmail, "Mite A"),
      createUserProfile(second.localId, secondEmail, "Mite B"),
    ]);

    const created = await callable("createCouple", first.idToken);
    coupleId = created.coupleId;
    assert.match(created.inviteCode, /^\d{6}$/);

    // A retry must resume the same pending pair instead of creating a second one.
    const resumed = await callable("createCouple", first.idToken);
    assert.equal(resumed.coupleId, coupleId);
    assert.equal(resumed.inviteCode, created.inviteCode);

    const joined = await callable("joinCoupleWithCode", second.idToken, { code: created.inviteCode });
    assert.equal(joined.coupleId, coupleId);

    const [couple, firstUser, secondUser] = await Promise.all([
      db.collection("couples").doc(coupleId).get(),
      db.collection("users").doc(first.localId).get(),
      db.collection("users").doc(second.localId).get(),
    ]);
    assert.equal(couple.data()?.status, "active");
    assert.deepEqual(new Set(couple.data()?.memberUids), new Set([first.localId, second.localId]));
    assert.equal(firstUser.data()?.coupleId, coupleId);
    assert.equal(secondUser.data()?.coupleId, coupleId);

    await callable("disconnectCouple", first.idToken);
    const [removedCouple, disconnectedFirst, disconnectedSecond] = await Promise.all([
      db.collection("couples").doc(coupleId).get(),
      db.collection("users").doc(first.localId).get(),
      db.collection("users").doc(second.localId).get(),
    ]);
    assert.equal(removedCouple.exists, false);
    assert.equal(disconnectedFirst.data()?.coupleId, undefined);
    assert.equal(disconnectedSecond.data()?.coupleId, undefined);

    await callable("deleteOwnAccount", first.idToken);
    await callable("deleteOwnAccount", second.idToken);
    console.log("Couple lifecycle smoke test passed.");
  } catch (error) {
    if (coupleId) await db.recursiveDelete(db.collection("couples").doc(coupleId)).catch(() => {});
    await Promise.all([first.localId, second.localId].map(async (uid) => {
      await db.recursiveDelete(db.collection("users").doc(uid)).catch(() => {});
      await adminAuth.deleteUser(uid).catch(() => {});
    }));
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
