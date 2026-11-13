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

async function expectCallableFailure(name, token, data, expectedCode) {
  await assert.rejects(
    () => callable(name, token, data),
    (error) => String(error.message).toLowerCase().replaceAll("_", "-").includes(expectedCode.toLowerCase()),
    `${name} should fail with ${expectedCode}`,
  );
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

async function preparePerson(authUser, email, name, handle) {
  await db.collection("users").doc(authUser.localId).set({
    displayName: name,
    email,
    authProvider: "password",
    dietaryDefault: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await callable("updatePersonProfile", authUser.idToken, {
    displayName: name,
    handle,
    bio: "Lokaler Gruppenplan-Test",
    city: "Marburg",
    isDiscoverable: true,
    avatarPath: null,
  });
}

// Backend minimum is 1,200 ms; 1,100 relied on request overhead and made fast runs flaky.
const pauseForRateLimit = () => new Promise((resolve) => setTimeout(resolve, 1_500));

async function main() {
  const marker = randomUUID().slice(0, 8);
  const password = `Group-${marker}!`;
    const ownerEmail = `group-owner-${marker}@example.test`;
    const guestEmail = `group-guest-${marker}@example.test`;
    const outsiderEmail = `group-outsider-${marker}@example.test`;
    const declinedEmail = `group-declined-${marker}@example.test`;
  const owner = await signUp(ownerEmail, password);
  const guest = await signUp(guestEmail, password);
    const outsider = await signUp(outsiderEmail, password);
    const declined = await signUp(declinedEmail, password);
  let eventId;

  try {
    await Promise.all([
      preparePerson(owner, ownerEmail, "Mite Owner", `owner_${marker}`),
      preparePerson(guest, guestEmail, "Mite Guest", `guest_${marker}`),
      preparePerson(outsider, outsiderEmail, "Mite Outsider", `outsider_${marker}`),
      preparePerson(declined, declinedEmail, "Mite Declined", `declined_${marker}`),
    ]);

    const originalTime = new Date(Date.now() + 48 * 60 * 60 * 1_000);
    const blockRef = db.collection("socialBlocks").doc(`${guest.localId}_${owner.localId}`);
    await blockRef.set({ blockerUid: guest.localId, targetUid: owner.localId });
    await expectCallableFailure("createGroupEvent", owner.idToken, {
      title: "Blocked invitation", city: "Marburg", scheduledAt: originalTime.toISOString(),
      inviteeUids: [guest.localId], planSteps: ["Kaffee"],
    }, "permission-denied");
    await blockRef.delete();
    await pauseForRateLimit();
    const created = await callable("createGroupEvent", owner.idToken, {
      title: "Kaffee an der Lahn",
      city: "Marburg",
      note: "Automatischer Kollaborationstest",
      scheduledAt: originalTime.toISOString(),
      inviteeUids: [guest.localId, declined.localId],
      planSteps: ["Kaffee im Ufercafé", "Spaziergang an der Lahn"],
      coverLicensedImage: null,
    });
    eventId = created.eventId;
    assert.ok(eventId);

    await callable("respondToGroupEvent", declined.idToken, { eventId, status: "declined" });
    await expectCallableFailure("sendGroupEventMessage", declined.idToken,
      { eventId, body: "Das dürfte nicht gesendet werden." }, "permission-denied");
    const afterDecline = (await db.collection("groupEvents").doc(eventId).get()).data();
    assert.equal(afterDecline.participantUids.includes(declined.localId), false);

    await callable("respondToGroupEvent", guest.idToken, { eventId, status: "going" });
    await callable("sendGroupEventMessage", guest.idToken, { eventId, body: "Ich bin dabei." });
    await pauseForRateLimit();

    const proposedTime = new Date(Date.now() + 72 * 60 * 60 * 1_000);
    const timeProposal = await callable("proposeGroupEventTime", guest.idToken, {
      eventId,
      scheduledAt: proposedTime.toISOString(),
      body: "Eine Stunde später wäre besser.",
    });
    await callable("acceptGroupEventTimeProposal", owner.idToken, { eventId, messageId: timeProposal.messageId });
    await pauseForRateLimit();

    const stepProposal = await callable("proposeGroupEventStep", guest.idToken, {
      eventId,
      stepId: "step-2",
      title: "Abendrunde am Schloss",
      body: "Das passt besser zum Sonnenuntergang.",
    });
    await callable("acceptGroupEventStepProposal", owner.idToken, { eventId, messageId: stepProposal.messageId });
    await callable("markGroupEventRead", guest.idToken, { eventId });

    const slotStart = Math.floor((Date.now() + 4 * 24 * 60 * 60 * 1_000) / 1_000);
    await callable("setGroupEventAvailability", owner.idToken, {
      eventId,
      slots: [{ startEpochSeconds: slotStart, status: "available" }],
      durationMinutes: 120,
      source: "manual",
    });
    await callable("setGroupEventAvailability", guest.idToken, {
      eventId,
      slots: [{ startEpochSeconds: slotStart, status: "maybe" }],
      durationMinutes: 120,
      source: "calendar",
    });
    await expectCallableFailure(
      "setGroupEventAvailability",
      outsider.idToken,
      { eventId, slots: [{ startEpochSeconds: slotStart, status: "available" }], durationMinutes: 120, source: "manual" },
      "permission-denied",
    );

    const expense = await callable("addGroupEventExpense", owner.idToken, {
      eventId,
      title: "Kaffee und Kuchen",
      amountMinor: 1_000,
      currency: "EUR",
      paidByUid: owner.localId,
      participantUids: [owner.localId, guest.localId],
      sharesByUid: { [owner.localId]: 500, [guest.localId]: 500 },
    });
    assert.ok(expense.expenseId);
    const concurrentPayments = await Promise.allSettled([1, 2].map(() =>
      callable("markGroupEventSettlementPaid", guest.idToken, {
        eventId,
        toUid: owner.localId,
        amountMinor: 500,
        currency: "EUR",
      }),
    ));
    assert.equal(concurrentPayments.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(concurrentPayments.filter((result) => result.status === "rejected").length, 1);
    const settlement = concurrentPayments.find((result) => result.status === "fulfilled").value;
    assert.ok(settlement.settlementId);
    await callable("confirmGroupEventSettlement", owner.idToken, { eventId, settlementId: settlement.settlementId });
    await expectCallableFailure(
      "voidGroupEventExpense",
      owner.idToken,
      { eventId, expenseId: expense.expenseId },
      "failed-precondition",
    );
    await callable("setGroupEventPaymentLink", guest.idToken, { url: "https://paypal.me/miteguest" });
    const paymentLinks = await callable("getGroupEventPaymentLinks", owner.idToken, { eventId });
    assert.equal(paymentLinks.links[guest.localId], "https://paypal.me/miteguest");

    const event = (await db.collection("groupEvents").doc(eventId).get()).data();
    assert.equal(event.participants.find((person) => person.uid === guest.localId)?.status, "going");
    assert.equal(event.planSteps[1].title, "Abendrunde am Schloss");
    assert.ok(Math.abs(event.scheduledAt.toMillis() - proposedTime.getTime()) < 1_000);
    assert.ok(event.readAtByUid[guest.localId]);
    assert.equal((await db.collection("groupEvents").doc(eventId).collection("availability").get()).size, 2);
    assert.equal((await db.collection("groupEvents").doc(eventId).collection("expenses").get()).size, 1);
    assert.equal((await db.collection("groupEvents").doc(eventId).collection("settlements").get()).size, 1);

    const outsiderBlock = db.collection("socialBlocks").doc(`${outsider.localId}_${owner.localId}`);
    await outsiderBlock.set({ blockerUid: outsider.localId, targetUid: owner.localId });
    await expectCallableFailure("inviteToGroupEvent", owner.idToken,
      { eventId, inviteeUids: [outsider.localId] }, "permission-denied");
    await outsiderBlock.delete();
    await pauseForRateLimit();
    await callable("inviteToGroupEvent", owner.idToken, { eventId, inviteeUids: [outsider.localId] });
    await callable("setGroupEventAvailability", outsider.idToken, {
      eventId, slots: [{ startEpochSeconds: slotStart, status: "available" }], durationMinutes: 120, source: "manual",
    });
    await callable("leaveGroupEvent", outsider.idToken, { eventId });
    assert.equal((await db.collection("groupEvents").doc(eventId).collection("availability").doc(outsider.localId).get()).exists, false);
    await expectCallableFailure("setGroupEventAvailability", outsider.idToken,
      { eventId, slots: [{ startEpochSeconds: slotStart, status: "available" }], durationMinutes: 120, source: "manual" }, "permission-denied");

    await callable("leaveGroupEvent", owner.idToken, { eventId });
    const afterCreatorLeave = (await db.collection("groupEvents").doc(eventId).get()).data();
    assert.equal(afterCreatorLeave.creatorUid, guest.localId, "only an engaged participant may become organiser");

    await callable("deleteOwnAccount", owner.idToken);
    await callable("deleteOwnAccount", guest.idToken);
    await callable("deleteOwnAccount", outsider.idToken);
    await callable("deleteOwnAccount", declined.idToken);
    eventId = undefined;
    console.log("Group collaboration smoke test passed.");
  } catch (error) {
    if (eventId) await db.recursiveDelete(db.collection("groupEvents").doc(eventId)).catch(() => {});
    await Promise.all([owner.localId, guest.localId, outsider.localId, declined.localId].map(async (uid) => {
      await db.recursiveDelete(db.collection("users").doc(uid)).catch(() => {});
      await db.recursiveDelete(db.collection("personProfiles").doc(uid)).catch(() => {});
      await adminAuth.deleteUser(uid).catch(() => {});
    }));
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
