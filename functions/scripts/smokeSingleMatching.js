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

async function prepareSingle(authUser, email, displayName) {
  await db.collection("users").doc(authUser.localId).set({
    displayName,
    email,
    authProvider: "password",
    accountMode: "single",
    datingEnabled: true,
    dietaryDefault: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await callable("updateSingleProfile", authUser.idToken, {
    displayName,
    city: "Marburg",
    bio: "Lokaler Matching-Test",
    age: 27,
    preferredAgeMinimum: 24,
    preferredAgeMaximum: 32,
    interests: ["Kaffee", "Spaziergänge"],
    budgetPreference: "mittel",
    moods: ["entspannt", "kulinarisch"],
    isMatchingActive: true,
    avatarPath: null,
  });
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const password = `Single-${marker}!`;
  const firstEmail = `single-a-${marker}@example.test`;
  const secondEmail = `single-b-${marker}@example.test`;
  const first = await signUp(firstEmail, password);
  const second = await signUp(secondEmail, password);
  let matchId;

  try {
    await Promise.all([
      prepareSingle(first, firstEmail, "Mite Single A"),
      prepareSingle(second, secondEmail, "Mite Single B"),
    ]);

    assert.equal((await callable("expressSingleInterest", first.idToken, { targetUid: second.localId })).status, "sent");
    const matched = await callable("expressSingleInterest", second.idToken, { targetUid: first.localId });
    assert.equal(matched.status, "matched");
    matchId = matched.matchId;

    await callable("sendSingleMessage", first.idToken, { matchId, body: "Lust auf einen Kaffee am Samstag?" });
    const recipientMatches = await callable("getSingleMatches", second.idToken);
    const recipientMatch = recipientMatches.matches.find((item) => item.matchId === matchId);
    assert.equal(recipientMatch?.hasUnreadMessage, true);

    const senderMatches = await callable("getSingleMatches", first.idToken);
    assert.equal(senderMatches.matches.find((item) => item.matchId === matchId)?.hasUnreadMessage, false);

    await callable("markSingleMatchRead", second.idToken, { matchId });
    const readMatches = await callable("getSingleMatches", second.idToken);
    assert.equal(readMatches.matches.find((item) => item.matchId === matchId)?.hasUnreadMessage, false);

    await callable("deleteOwnAccount", first.idToken);
    await callable("deleteOwnAccount", second.idToken);
    matchId = undefined;
    console.log("Single matching and unread-message smoke test passed.");
  } catch (error) {
    if (matchId) await db.recursiveDelete(db.collection("singleMatches").doc(matchId)).catch(() => {});
    await Promise.all([first.localId, second.localId].map(async (uid) => {
      await db.recursiveDelete(db.collection("users").doc(uid)).catch(() => {});
      await db.recursiveDelete(db.collection("singleProfiles").doc(uid)).catch(() => {});
      await adminAuth.deleteUser(uid).catch(() => {});
    }));
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
