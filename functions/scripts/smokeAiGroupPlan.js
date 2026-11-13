/* eslint-disable no-console */
// Covers the release checklist's still-open gate: "Smoke-Test: KI-Gruppenplan erstellen, Orte
// bestätigen, Bilder generieren, Einladung annehmen und im Chat schreiben." smoke:group already
// exercises invitation/acceptance/chat/time- and step-proposals end to end, but always against a
// hand-built plan — it never calls the AI itself. This script is the complementary case: it
// walks the actual guided-planning path (generateDateSuggestions -> composeDateSuggestion ->
// generateDateStationImages -> createGroupEvent), then reuses the already-covered invite/accept/
// chat flow just enough to confirm the AI-composed plan is a normal, usable group event.
//
// UNLIKE every other smoke:* script, this one makes real, billed OpenAI calls (one text
// generation, up to three image generations) through the local Functions emulator, which reads
// the real key from functions/.env.local. It is deliberately NOT part of `npm run quality:local`
// so that command stays free and fast; run it on its own with `npm run smoke:ai-group-plan` when
// you specifically want to re-validate this path.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

const { functionBase } = require("./localSmokeEnvironment").configureLocalSmokeEnvironment();

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();
const adminAuth = getAuth();

async function callable(name, token, data = {}, timeoutMs = 20_000) {
  const response = await fetch(`${functionBase}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const body = await response.json();
  if (!response.ok || body.error) throw new Error(`${name}: ${JSON.stringify(body.error || body)}`);
  return body.result ?? body.data;
}

async function signUpPerson(marker, label) {
  const email = `ai-group-${marker}-${label}@example.test`;
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password: `Smoke-${marker}!`, returnSecureToken: true }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  const body = await response.json();
  if (!response.ok) throw new Error(`signup ${label}: ${JSON.stringify(body)}`);
  const uid = body.localId;
  await db.collection("users").doc(uid).set({
    displayName: `Mite Smoke ${label}`,
    email,
    authProvider: "password",
    dietaryDefault: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await callable("updatePersonProfile", body.idToken, {
    displayName: `Mite Smoke ${label}`,
    handle: `aigrp_${marker}_${label}`,
    bio: "Automatischer lokaler Test",
    city: "Marburg",
    isDiscoverable: true,
    avatarPath: null,
  });
  return { uid, idToken: body.idToken };
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const organizer = await signUpPerson(marker, "organizer");
  const invitee = await signUpPerson(marker, "invitee");
  let eventId;

  try {
    // 1) "KI-Gruppenplan erstellen" — the same personal-scope request the app sends from
    // PlanningStartView's group mode (ownerUid, planningMode "group", no occasion).
    const criteria = {
      city: "Marburg",
      budget: "mittel",
      moods: ["entspannt", "kulinarisch"],
      indoorOutdoor: "egal",
      date: new Date(Date.now() + 3 * 86_400_000).toISOString(),
      time: "18:30",
      durationMinutes: 180,
      occasion: "spontanes Date",
      dietaryPreferences: [],
      mobility: "zufuss",
      radiusKm: 5,
      planningMode: "group",
      participantCount: 2,
    };
    const generated = await callable(
      "generateDateSuggestions",
      organizer.idToken,
      { ownerUid: organizer.uid, criteria },
      60_000,
    );
    assert.equal(generated.suggestions.length, 5, "expected exactly five route candidates");
    const stationCount = generated.suggestions[0].stations.length;
    assert.ok(stationCount === 2 || stationCount === 3, "each route must have two or three stations");
    assert.ok(generated.suggestions.every((item) => item.stations.length === stationCount));

    // 2) "Orte bestätigen" — in the app, MapKit resolves each station's searchQueryHint to a
    // real place on-device before this point; composeDateSuggestion is the server-side gate that
    // turns that confirmed, one-per-slot selection into the single route that may receive paid
    // visuals. Picking the first candidate in every slot mirrors "accept the suggested places".
    const candidateIds = generated.suggestions.map((item) => item.id).slice(0, 1);
    const composed = await callable("composeDateSuggestion", organizer.idToken, {
      ownerUid: organizer.uid,
      requestId: generated.requestId,
      candidateIds: Array(stationCount).fill(candidateIds[0]),
    });
    assert.equal(composed.suggestion.stations.length, stationCount);

    // 3) "Bilder generieren" — real OpenAI image calls, one per station.
    const imaged = await callable("generateDateStationImages", organizer.idToken, {
      ownerUid: organizer.uid,
      requestId: generated.requestId,
      suggestionId: composed.suggestion.id,
    }, 60_000);
    assert.ok(imaged.stationImages.length > 0, "expected at least one generated station image");
    const cover = imaged.stationImages[0].licensedImage;
    assert.match(cover.url, /^storage:\/\/generatedDateImages\/v\d+\/[a-f0-9]{64}\.jpg$/);

    // Turn the composed, imaged route into the actual shared group plan.
    const created = await callable("createGroupEvent", organizer.idToken, {
      title: composed.suggestion.title,
      city: criteria.city,
      note: composed.suggestion.summary,
      coverLicensedImage: cover,
      scheduledAt: criteria.date,
      planSteps: composed.suggestion.stations.map((station) => station.title),
      inviteeUids: [invitee.uid],
    });
    eventId = created.eventId;
    assert.ok(eventId);
    const stored = (await db.collection("groupEvents").doc(eventId).get()).data();
    assert.equal(stored.coverLicensedImage.url, cover.url);
    assert.equal(stored.planSteps.length, stationCount);

    // 4) "Einladung annehmen und im Chat schreiben" — the already-hardened path, exercised just
    // once here to confirm an AI-composed plan behaves like any other group event.
    await callable("respondToGroupEvent", invitee.idToken, { eventId, status: "going" });
    const afterAccept = (await db.collection("groupEvents").doc(eventId).get()).data();
    assert.equal(afterAccept.participants.find((person) => person.uid === invitee.uid).status, "going");

    await callable("sendGroupEventMessage", invitee.idToken, { eventId, body: "Bin dabei, klingt super!" });
    const messages = await db.collection("groupEvents").doc(eventId).collection("messages").get();
    assert.equal(messages.size, 1);

    console.log("AI group-plan lifecycle smoke test passed.");
  } finally {
    if (eventId) await db.recursiveDelete(db.collection("groupEvents").doc(eventId)).catch(() => {});
    for (const person of [organizer, invitee]) {
      await db.recursiveDelete(db.collection("users").doc(person.uid)).catch(() => {});
      await db.collection("personProfiles").doc(person.uid).delete().catch(() => {});
      await adminAuth.deleteUser(person.uid).catch(() => {});
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
