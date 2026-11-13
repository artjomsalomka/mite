/* eslint-disable no-console */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { functionBase } = require("./localSmokeEnvironment").configureLocalSmokeEnvironment();
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();
const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;

function value(input) {
  if (input === null) return { nullValue: null };
  if (input instanceof Date) return { timestampValue: input.toISOString() };
  if (typeof input === "string") return { stringValue: input };
  if (typeof input === "number") return { integerValue: String(input) };
  if (typeof input === "boolean") return { booleanValue: input };
  if (Array.isArray(input)) return { arrayValue: { values: input.map(value) } };
  return { mapValue: { fields: fields(input) } };
}
const fields = (object) => Object.fromEntries(Object.entries(object).map(([key, entry]) => [key, value(entry)]));

async function request(path, user, method = "GET", data, expected = 200) {
  const response = await fetch(`${base}/${path}`, {
    method, headers: { "content-type": "application/json", ...(user ? { authorization: `Bearer ${user.idToken}` } : {}) },
    body: data ? JSON.stringify({ fields: fields(data) }) : undefined,
    signal: AbortSignal.timeout(15_000),
  });
  assert.equal(response.status, expected, `${method} ${path}: expected ${expected}, received ${response.status}`);
}

async function main() {
  const marker = randomUUID();
  const users = [];
  const roots = [];
  try {
    for (let i = 0; i < 3; i++) {
      const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: `rules-${marker}-${i}@example.test`, password: `Rules-${marker}!`, returnSecureToken: true }),
        signal: AbortSignal.timeout(15_000),
      });
      assert.equal(response.status, 200);
      const user = await response.json();
      users.push(user);
      const root = db.collection("users").doc(user.localId);
      roots.push(root);
      await root.set({ displayName: "Rules test" });
    }
    const [owner, guest, outsider] = users;
    const event = db.collection("groupEvents").doc(`rules-${marker}`);
    const couple = db.collection("couples").doc(`rules-${marker}`);
    const match = db.collection("singleMatches").doc(`rules-${marker}`);
    roots.push(event, couple, match);
    await event.set({ creatorUid: owner.localId, participantUids: [owner.localId, guest.localId] });
    await couple.set({ status: "active", memberUids: [owner.localId, guest.localId] });
    await match.set({ status: "matched", memberUids: [owner.localId, guest.localId] });

    for (const collection of ["messages", "availability", "expenses", "settlements"]) {
      await event.collection(collection).doc("sample").set({ body: "Private group content" });
      const path = `${event.path}/${collection}/sample`;
      await request(path, guest);
      await request(path, outsider, "GET", undefined, 403);
      await request(path, null, "GET", undefined, 403);
      await request(path, owner, "PATCH", { forged: true }, 403);
    }
    await request(event.path, owner, "PATCH", { participantUids: [outsider.localId] }, 403);
    await request(`users/${owner.localId}`, outsider, "GET", undefined, 403);

    const future = new Date(Date.now() + 86_400_000);
    const past = new Date(Date.now() - 86_400_000);
    const plan = { sourceRequestId: "request", sourceSuggestionId: "idea", title: "Ufercafé",
      scheduledAt: future, createdByUid: owner.localId, createdAt: new Date(), status: "upcoming", rating: null,
      stations: [{ order: 1, title: "Kaffee", durationMinutes: 60 }] };
    const rating = { stars: 5, comment: null, tags: [], ratedByUid: owner.localId, ratedAt: new Date() };
    for (const scope of [`users/${owner.localId}`, couple.path, match.path]) {
      await db.doc(`${scope}/dateRequests/request`).set({ status: "completed" });
      await request(`${scope}/dateRequests/request`, owner);
      await request(`${scope}/dateRequests/request`, outsider, "GET", undefined, 403);
      const path = `${scope}/savedDates/plan`;
      await request(path, owner, "PATCH", plan);
      await request(path, outsider, "GET", undefined, 403);
      await request(path, owner, "PATCH", { ...plan, scheduledAt: past }, 403);
      await request(path, owner, "PATCH", { ...plan, status: "completed", rating }, 403);
      await request(path, owner, "PATCH", { ...plan, completedStationOrders: [1] }, 403);
      const moved = { ...plan, scheduledAt: new Date(future.getTime() + 3_600_000) };
      await request(path, owner, "PATCH", moved);
      await request(path, owner, "PATCH", { ...moved, status: "cancelled", scheduledAt: past }, 403);
      await request(path, owner, "PATCH", { ...moved, status: "cancelled" });
      await request(path, owner, "PATCH", moved, 403);
      await request(path, owner, "DELETE", undefined, 403);

      const pastPath = `${scope}/savedDates/past`;
      await db.doc(pastPath).set({ ...plan, scheduledAt: past });
      await request(pastPath, owner, "PATCH", { ...plan, scheduledAt: past, status: "completed", rating });
      await request(pastPath, owner, "PATCH", { ...plan, scheduledAt: past, status: "completed", rating: { ...rating, stars: 4 } }, 403);

      // The callable must support exactly the same personal/couple/match ownership scopes.
      const journeyPath = `${scope}/savedDates/journey`;
      await db.doc(journeyPath).set({ ...plan, scheduledAt: past });
      const scopeType = scope.startsWith("users/") ? "personal" : scope.startsWith("couples/") ? "couple" : "match";
      for (const [user, expected] of [[owner, 200], [outsider, 403]]) {
        const response = await fetch(`${functionBase}/setDateStationCompleted`, {
          method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${user.idToken}` },
          body: JSON.stringify({ data: { scopeType, scopeId: scope.split("/")[1], dateId: "journey", stationOrder: 1, completed: true } }),
          signal: AbortSignal.timeout(15_000),
        });
        assert.equal(response.status, expected, `journey ${scopeType} authorization`);
      }
    }
    console.log("Firestore authorization and saved-date lifecycle smoke test passed.");
  } finally {
    for (const root of roots) await db.recursiveDelete(root);
    for (const user of users) await getAuth().deleteUser(user.localId);
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
