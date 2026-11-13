import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { sendGenericPush } from "../pushNotifications";
import { normalizeCity, optionalText, requireText } from "./socialHelpers";
import { ensurePersonProfile, type PersonProfileSnapshot } from "./personProfiles";
import { consumeSocialWriteQuota } from "./socialWriteRateLimit";
import type { LicensedImageReference } from "./types";

type Attendance = "invited" | "going" | "maybe" | "declined";

interface EventParticipant extends PersonProfileSnapshot {
  status: Attendance;
}

interface CreateGroupEventRequest {
  title: string;
  city?: string;
  note?: string;
  scheduledAt: string;
  inviteeUids?: string[];
  planSteps?: string[];
  coverLicensedImage?: LicensedImageReference | null;
}

interface RespondToGroupEventRequest {
  eventId: string;
  status: Exclude<Attendance, "invited">;
}

interface CancelGroupEventRequest { eventId: string; }
interface UpdateGroupEventCoverRequest { eventId: string; coverImagePath: string | null; }
interface SendGroupEventMessageRequest { eventId: string; body: string; }
interface ProposeGroupEventTimeRequest { eventId: string; scheduledAt: string; body?: string; }
interface AcceptGroupEventTimeProposalRequest { eventId: string; messageId: string; }
interface ProposeGroupEventStepRequest { eventId: string; stepId: string; title: string; body?: string; }
interface AcceptGroupEventStepProposalRequest { eventId: string; messageId: string; }
interface MarkGroupEventReadRequest { eventId: string; }
interface InviteToGroupEventRequest { eventId: string; inviteeUids: string[]; }
interface LeaveGroupEventRequest { eventId: string; }
interface SetGroupEventAvailabilityRequest {
  eventId: string;
  slots: Array<{ startEpochSeconds: number; status: "available" | "maybe" | "unavailable" }>;
  durationMinutes: number;
  source: "calendar" | "manual";
}
interface AddGroupEventExpenseRequest {
  eventId: string;
  title: string;
  amountMinor: number;
  currency: string;
  paidByUid: string;
  participantUids: string[];
  sharesByUid: Record<string, number>;
}
interface VoidGroupEventExpenseRequest { eventId: string; expenseId: string; }
interface MarkGroupEventSettlementPaidRequest { eventId: string; toUid: string; amountMinor: number; currency: string; }
interface ConfirmGroupEventSettlementRequest { eventId: string; settlementId: string; }
interface SetGroupEventPaymentLinkRequest { url: string; }
interface GetGroupEventPaymentLinksRequest { eventId: string; }

/** A group plan is an invitation-based object, not a post. It can later become a shared moment. */
export const createGroupEvent = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const body = (request.data ?? {}) as Partial<CreateGroupEventRequest>;
  // The guided planning flow can return a fully selected route before the LLM has
  // supplied a short umbrella title. A selected first stop is a much better title
  // than rejecting an otherwise valid group plan.
  const requestedSteps = validatePlanSteps(body.planSteps);
  const title = resolveEventTitle(body.title, requestedSteps);
  const planSteps = requestedSteps.length > 0
    ? requestedSteps
    : [{ id: "step-1", title }];
  const city = normalizeCity(body.city);
  const note = optionalText(body.note, "Notiz", 500);
  const coverLicensedImage = validateLicensedImage(body.coverLicensedImage);
  const scheduledAt = parseFutureDate(body.scheduledAt);
  const inviteeUids = validateInvitees(body.inviteeUids, request.auth.uid);
  // Reject a blocked invitation before consuming the organiser's small write quota.
  // The transaction below repeats this check so a concurrent block is still safe.
  await assertNoInvitationBlocksBeforeQuota(request.auth.uid, inviteeUids);
  await consumeSocialWriteQuota(
    db.collection("users").doc(request.auth.uid).collection("socialRateLimits").doc("groupEvents"),
  );
  const [creator, ...invitees] = await Promise.all([
    ensurePersonProfile(request.auth.uid),
    ...inviteeUids.map((uid) => publicInviteeSnapshot(uid)),
  ]);
  const now = Timestamp.now();
  const participants: EventParticipant[] = [
    { ...creator, status: "going" },
    ...invitees.map((person): EventParticipant => ({ ...person, status: "invited" })),
  ];
  const eventRef = db.collection("groupEvents").doc();
  await db.runTransaction(async (tx) => {
    await assertNoInvitationBlocks(tx, request.auth!.uid, inviteeUids);
    tx.set(eventRef, {
      creatorUid: request.auth!.uid,
      creator,
      title,
      city,
      cityNormalized: city.toLocaleLowerCase("de-DE"),
      note,
      planSteps,
      coverImagePath: null,
      coverLicensedImage,
      scheduledAt,
      status: "planned",
      participants,
      participantUids: participants.map((person) => person.uid),
      readAtByUid: { [request.auth!.uid]: now },
      createdAt: now,
      updatedAt: now,
    });
  });
  return { eventId: eventRef.id };
});

export const respondToGroupEvent = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, status } = (request.data ?? {}) as Partial<RespondToGroupEventRequest>;
  if (!eventId || typeof eventId !== "string" || !["going", "maybe", "declined"].includes(status ?? "")) {
    throw new HttpsError("invalid-argument", "Ungültige Antwort.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  const creatorUid = await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    if (!event.exists || event.data()?.status !== "planned") throw new HttpsError("not-found", "Dieser Plan ist nicht verfügbar.");
    const participants = (event.data()?.participants ?? []) as EventParticipant[];
    const participantIndex = participants.findIndex((person) => person.uid === request.auth!.uid);
    if (participantIndex < 0 || participants[participantIndex].status !== "invited") {
      throw new HttpsError("failed-precondition", "Diese Einladung wurde bereits beantwortet.");
    }
    if (status === "declined") {
      // A declined invitation must immediately lose access to the private planning room. Keep no
      // stale participant snapshot that could be re-used to read chat, availability or expenses.
      const remaining = participants.filter((person) => person.uid !== request.auth!.uid);
      tx.update(eventRef, {
        participants: remaining,
        participantUids: remaining.map((person) => person.uid),
        [`readAtByUid.${request.auth!.uid}`]: FieldValue.delete(),
        updatedAt: Timestamp.now(),
      });
      tx.delete(eventRef.collection("availability").doc(request.auth!.uid));
    } else {
      participants[participantIndex] = { ...participants[participantIndex], status: status as Attendance };
      tx.update(eventRef, { participants, updatedAt: Timestamp.now() });
    }
    return event.data()?.creatorUid as string | undefined;
  });
  if (creatorUid && creatorUid !== request.auth.uid) {
    void sendGenericPush([creatorUid], {
      title: "Antwort auf eure Einladung",
      body: "Eine eingeladene Person hat auf euren gemeinsamen Plan geantwortet.",
      data: { type: "group_event", eventId },
    }).catch((error) => console.warn("Push notification for event response failed.", error));
  }
  return { status };
});

export const cancelGroupEvent = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId } = (request.data ?? {}) as Partial<CancelGroupEventRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const eventRef = db.collection("groupEvents").doc(eventId);
  const recipients = await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    if (!event.exists || event.data()?.creatorUid !== request.auth!.uid) {
      throw new HttpsError("permission-denied", "Du kannst diesen Plan nicht absagen.");
    }
    if (event.data()?.status !== "planned") throw new HttpsError("failed-precondition", "Dieser Plan ist bereits beendet.");
    tx.update(eventRef, { status: "cancelled", updatedAt: Timestamp.now() });
    return ((event.data()?.participantUids ?? []) as string[]).filter((uid) => uid !== request.auth!.uid);
  });
  void sendGenericPush(recipients, {
    title: "Plan abgesagt",
    body: "Ein gemeinsamer Plan wurde abgesagt.",
    data: { type: "group_event", eventId },
  }).catch((error) => console.warn("Push notification for cancelled event failed.", error));
  return { cancelled: true };
});

/** Stores only a per-member cursor, never message contents or presence information. */
export const markGroupEventRead = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId } = (request.data ?? {}) as Partial<MarkGroupEventReadRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const eventRef = db.collection("groupEvents").doc(eventId);
  await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    const participantUids = (event.data()?.participantUids ?? []) as string[];
    if (!event.exists || !participantUids.includes(request.auth!.uid)) {
      throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
    }
    tx.update(eventRef, { [`readAtByUid.${request.auth!.uid}`]: Timestamp.now() });
  });
  return { read: true };
});

export const inviteToGroupEvent = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, inviteeUids } = (request.data ?? {}) as Partial<InviteToGroupEventRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const requestedUIDs = validateInvitees(inviteeUids, request.auth.uid);
  if (requestedUIDs.length === 0) throw new HttpsError("invalid-argument", "Wähle mindestens eine Person aus.");
  const eventRef = db.collection("groupEvents").doc(eventId);
  const eventBefore = await eventRef.get();
  if (!eventBefore.exists || eventBefore.data()?.status !== "planned" || eventBefore.data()?.creatorUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Nur die organisierende Person kann weitere Menschen einladen.");
  }
  const existingUIDs = (eventBefore.data()?.participantUids ?? []) as string[];
  const newUIDs = requestedUIDs.filter((uid) => !existingUIDs.includes(uid));
  if (newUIDs.length === 0) throw new HttpsError("already-exists", "Diese Personen sind bereits Teil des Plans.");
  if (existingUIDs.length + newUIDs.length > 9) throw new HttpsError("invalid-argument", "Ein Plan ist auf neun Personen begrenzt.");
  // A rejected safety check must not make a legitimate following invite rate-limited.
  // Keep the transaction-time recheck further down for correctness under concurrency.
  await assertNoInvitationBlocksBeforeQuota(request.auth.uid, newUIDs);
  await consumeSocialWriteQuota(
    db.collection("users").doc(request.auth.uid).collection("socialRateLimits").doc("groupInvites"),
  );
  const snapshots = await Promise.all(newUIDs.map(publicInviteeSnapshot));
  const newParticipants = snapshots.map((person): EventParticipant => ({ ...person, status: "invited" }));
  const invitedUIDs = await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    if (!event.exists || event.data()?.status !== "planned" || event.data()?.creatorUid !== request.auth!.uid) {
      throw new HttpsError("permission-denied", "Dieser Plan kann nicht mehr bearbeitet werden.");
    }
    const currentUIDs = (event.data()?.participantUids ?? []) as string[];
    const additions = newParticipants.filter((person) => !currentUIDs.includes(person.uid));
    if (currentUIDs.length + additions.length > 9) throw new HttpsError("invalid-argument", "Ein Plan ist auf neun Personen begrenzt.");
    await assertNoInvitationBlocks(tx, request.auth!.uid, additions.map((person) => person.uid));
    if (additions.length > 0) {
      tx.update(eventRef, {
        participants: FieldValue.arrayUnion(...additions),
        participantUids: FieldValue.arrayUnion(...additions.map((person) => person.uid)),
        updatedAt: Timestamp.now(),
      });
    }
    return additions.map((person) => person.uid);
  });
  await sendGenericPush(invitedUIDs, {
    title: "Neue Einladung",
    body: "Du wurdest zu einem gemeinsamen Plan eingeladen.",
    data: { type: "group_event", eventId },
  }).catch((error) => console.warn("Push notification for invitation failed.", error));
  return { invited: invitedUIDs.length };
});

export const leaveGroupEvent = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId } = (request.data ?? {}) as Partial<LeaveGroupEventRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const eventRef = db.collection("groupEvents").doc(eventId);
  let transferredTo: string | null = null;
  await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    const data = event.data();
    if (!event.exists || data?.status !== "planned") throw new HttpsError("not-found", "Dieser Plan ist nicht verfügbar.");
    const participants = (data.participants ?? []) as EventParticipant[];
    if (!participants.some((person) => person.uid === request.auth!.uid)) {
      throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
    }
    const remaining = participants.filter((person) => person.uid !== request.auth!.uid);
    const update: Record<string, unknown> = {
      participants: remaining,
      participantUids: remaining.map((person) => person.uid),
      [`readAtByUid.${request.auth!.uid}`]: FieldValue.delete(),
      updatedAt: Timestamp.now(),
    };
    if (data.creatorUid === request.auth!.uid) {
      const successor = remaining.find((person) => person.status === "going")
        ?? remaining.find((person) => person.status === "maybe");
      // An unanswered invitation is deliberately not enough to grant organiser rights. If the
      // organiser leaves before anyone has engaged with the plan, cancel it rather than giving
      // an unconfirmed invitee control over people, chat and expenses.
      if (successor) {
        transferredTo = successor.uid;
        update.creatorUid = successor.uid;
        update.creator = {
          uid: successor.uid,
          displayName: successor.displayName,
          handle: successor.handle,
          avatarPath: successor.avatarPath ?? null,
        };
      } else {
        update.status = "cancelled";
      }
    }
    tx.update(eventRef, update);
    tx.delete(eventRef.collection("availability").doc(request.auth!.uid));
  });
  if (transferredTo) {
    void sendGenericPush([transferredTo], {
      title: "Du organisierst jetzt den Plan",
      body: "Die bisher organisierende Person hat den gemeinsamen Plan verlassen.",
      data: { type: "group_event", eventId },
    }).catch((error) => console.warn("Push notification for organiser transfer failed.", error));
  }
  return { left: true, transferredTo };
});

/** Only the organiser can replace the generated editorial cover with an own photo. */
export const updateGroupEventCover = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, coverImagePath } = (request.data ?? {}) as Partial<UpdateGroupEventCoverRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  if (coverImagePath !== null && (typeof coverImagePath !== "string" || coverImagePath !== `groupEventImages/${eventId}/cover.jpg`)) {
    throw new HttpsError("invalid-argument", "Ungültiges Titelbild.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    if (!event.exists || event.data()?.creatorUid !== request.auth!.uid) {
      throw new HttpsError("permission-denied", "Nur die organisierende Person kann das Titelbild ändern.");
    }
    if (event.data()?.status !== "planned") throw new HttpsError("failed-precondition", "Dieser Plan ist bereits beendet.");
    tx.update(eventRef, { coverImagePath, updatedAt: Timestamp.now() });
  });
  return { updated: true };
});

/** The event chat is deliberately stored beneath its plan, never as a globally searchable room. */
export const sendGroupEventMessage = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, body } = (request.data ?? {}) as Partial<SendGroupEventMessageRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const text = requireText(body, "Nachricht", 800);
  const eventRef = db.collection("groupEvents").doc(eventId);
  const sender = await ensureEventParticipant(eventRef, request.auth.uid);
  await consumeSocialWriteQuota(eventRef.collection("messageRateLimits").doc(request.auth.uid));
  await eventRef.collection("messages").add({
    senderUid: request.auth.uid,
    sender,
    kind: "text",
    body: text,
    proposedScheduledAt: null,
    proposalStatus: null,
    createdAt: Timestamp.now(),
  });
  return { sent: true };
});

/** Every attendee can propose a new time. The creator is the only person who can make it live. */
export const proposeGroupEventTime = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, scheduledAt, body } = (request.data ?? {}) as Partial<ProposeGroupEventTimeRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const date = parseFutureDate(scheduledAt);
  const eventRef = db.collection("groupEvents").doc(eventId);
  const sender = await ensureEventParticipant(eventRef, request.auth.uid);
  await consumeSocialWriteQuota(eventRef.collection("messageRateLimits").doc(request.auth.uid));
  const message = await eventRef.collection("messages").add({
    senderUid: request.auth.uid,
    sender,
    kind: "timeProposal",
    body: optionalText(body, "Notiz", 240),
    proposedScheduledAt: date,
    proposalStatus: "pending",
    createdAt: Timestamp.now(),
  });
  return { messageId: message.id };
});

export const acceptGroupEventTimeProposal = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, messageId } = (request.data ?? {}) as Partial<AcceptGroupEventTimeProposalRequest>;
  if (!eventId || typeof eventId !== "string" || !messageId || typeof messageId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Vorschlag.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  const messageRef = eventRef.collection("messages").doc(messageId);
  const recipients = await db.runTransaction(async (tx) => {
    const [event, message] = await Promise.all([tx.get(eventRef), tx.get(messageRef)]);
    if (!event.exists || event.data()?.creatorUid !== request.auth!.uid || event.data()?.status !== "planned") {
      throw new HttpsError("permission-denied", "Nur die organisierende Person kann den Ablauf ändern.");
    }
    const proposalTime = message.data()?.proposedScheduledAt;
    if (!message.exists || message.data()?.kind !== "timeProposal" || message.data()?.proposalStatus !== "pending" || !(proposalTime instanceof Timestamp)) {
      throw new HttpsError("failed-precondition", "Dieser Vorschlag ist nicht mehr verfügbar.");
    }
    if (proposalTime.toMillis() <= Date.now() + 5 * 60 * 1000) {
      throw new HttpsError("failed-precondition", "Der vorgeschlagene Zeitpunkt liegt bereits in der Vergangenheit.");
    }
    const now = Timestamp.now();
    tx.update(eventRef, { scheduledAt: proposalTime, updatedAt: now });
    tx.update(messageRef, { proposalStatus: "accepted" });
    return ((event.data()?.participantUids ?? []) as string[]).filter((uid) => uid !== request.auth!.uid);
  });
  void sendGenericPush(recipients, {
    title: "Neue Zeit bestätigt",
    body: "Die Uhrzeit eines gemeinsamen Plans wurde aktualisiert.",
    data: { type: "group_event", eventId },
  }).catch((error) => console.warn("Push notification for accepted time failed.", error));
  return { accepted: true };
});

export const proposeGroupEventStep = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, stepId, title, body } = (request.data ?? {}) as Partial<ProposeGroupEventStepRequest>;
  if (!eventId || typeof eventId !== "string" || !stepId || typeof stepId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Vorschlag.");
  }
  const proposedTitle = requireText(title, "Vorschlag", 100);
  const eventRef = db.collection("groupEvents").doc(eventId);
  const sender = await ensureEventParticipant(eventRef, request.auth.uid);
  const event = await eventRef.get();
  const steps = (event.data()?.planSteps ?? []) as Array<{ id: string; title: string }>;
  if (!steps.some((step) => step.id === stepId)) throw new HttpsError("not-found", "Dieser Planbaustein existiert nicht mehr.");
  await consumeSocialWriteQuota(eventRef.collection("messageRateLimits").doc(request.auth.uid));
  const message = await eventRef.collection("messages").add({
    senderUid: request.auth.uid,
    sender,
    kind: "stepProposal",
    body: optionalText(body, "Notiz", 240),
    proposedScheduledAt: null,
    proposedStepID: stepId,
    proposedStepTitle: proposedTitle,
    proposalStatus: "pending",
    createdAt: Timestamp.now(),
  });
  return { messageId: message.id };
});

export const acceptGroupEventStepProposal = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, messageId } = (request.data ?? {}) as Partial<AcceptGroupEventStepProposalRequest>;
  if (!eventId || typeof eventId !== "string" || !messageId || typeof messageId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Vorschlag.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  const messageRef = eventRef.collection("messages").doc(messageId);
  const recipients = await db.runTransaction(async (tx) => {
    const [event, message] = await Promise.all([tx.get(eventRef), tx.get(messageRef)]);
    if (!event.exists || event.data()?.creatorUid !== request.auth!.uid || event.data()?.status !== "planned") {
      throw new HttpsError("permission-denied", "Nur die organisierende Person kann den Ablauf ändern.");
    }
    const proposal = message.data();
    if (!message.exists || proposal?.kind !== "stepProposal" || proposal?.proposalStatus !== "pending"
      || typeof proposal.proposedStepID !== "string" || typeof proposal.proposedStepTitle !== "string") {
      throw new HttpsError("failed-precondition", "Dieser Vorschlag ist nicht mehr verfügbar.");
    }
    const steps = (event.data()?.planSteps ?? []) as Array<{ id: string; title: string }>;
    const index = steps.findIndex((step) => step.id === proposal.proposedStepID);
    if (index < 0) throw new HttpsError("not-found", "Dieser Planbaustein existiert nicht mehr.");
    steps[index] = { ...steps[index], title: proposal.proposedStepTitle };
    tx.update(eventRef, { planSteps: steps, updatedAt: Timestamp.now() });
    tx.update(messageRef, { proposalStatus: "accepted" });
    return ((event.data()?.participantUids ?? []) as string[]).filter((uid) => uid !== request.auth!.uid);
  });
  void sendGenericPush(recipients, {
    title: "Plan aktualisiert",
    body: "Ein Baustein eures gemeinsamen Plans wurde geändert.",
    data: { type: "group_event", eventId },
  }).catch((error) => console.warn("Push notification for accepted step failed.", error));
  return { accepted: true };
});

/** Stores only answers for finite candidate slots. Calendar event metadata never reaches Firebase. */
export const setGroupEventAvailability = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const body = (request.data ?? {}) as Partial<SetGroupEventAvailabilityRequest>;
  if (!body.eventId || typeof body.eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const durationMinutes = requireInteger(body.durationMinutes, "Dauer", 30, 480);
  if (body.source !== "calendar" && body.source !== "manual") throw new HttpsError("invalid-argument", "Ungültige Quelle.");
  if (!Array.isArray(body.slots) || body.slots.length < 1 || body.slots.length > 120) {
    throw new HttpsError("invalid-argument", "Bitte übermittle zwischen einem und 120 Zeitfenstern.");
  }
  const eventRef = db.collection("groupEvents").doc(body.eventId);
  await ensureEventParticipant(eventRef, request.auth.uid);
  const nowSeconds = Math.floor(Date.now() / 1_000);
  const latestSeconds = nowSeconds + 90 * 24 * 60 * 60;
  const statuses: Record<string, string> = {};
  for (const slot of body.slots) {
    const start = requireInteger(slot?.startEpochSeconds, "Zeitfenster", nowSeconds + 60, latestSeconds);
    if (!slot || !["available", "maybe", "unavailable"].includes(slot.status)) {
      throw new HttpsError("invalid-argument", "Ungültige Verfügbarkeit.");
    }
    statuses[String(start)] = slot.status;
  }
  const now = Timestamp.now();
  await eventRef.collection("availability").doc(request.auth.uid).set({
    uid: request.auth.uid,
    slotStatuses: statuses,
    durationMinutes,
    source: body.source,
    updatedAt: now,
    expiresAt: Timestamp.fromMillis(Date.now() + 120 * 24 * 60 * 60 * 1_000),
  });
  return { saved: Object.keys(statuses).length };
});

export const addGroupEventExpense = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const body = (request.data ?? {}) as Partial<AddGroupEventExpenseRequest>;
  if (!body.eventId || typeof body.eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const title = requireText(body.title, "Ausgabe", 80);
  const amountMinor = requireInteger(body.amountMinor, "Betrag", 1, 1_000_000);
  if (body.currency !== "EUR") throw new HttpsError("invalid-argument", "Aktuell wird nur Euro unterstützt.");
  const eventRef = db.collection("groupEvents").doc(body.eventId);
  await ensureEventParticipant(eventRef, request.auth.uid);
  const event = await eventRef.get();
  const eventUIDs = (event.data()?.participantUids ?? []) as string[];
  if (!body.paidByUid || !eventUIDs.includes(body.paidByUid)) throw new HttpsError("invalid-argument", "Die zahlende Person gehört nicht zum Plan.");
  const participantUids = validateExpenseParticipants(body.participantUids, eventUIDs);
  const sharesByUid = validateExpenseShares(body.sharesByUid, participantUids, amountMinor);
  await consumeSocialWriteQuota(eventRef.collection("expenseRateLimits").doc(request.auth.uid));
  const now = Timestamp.now();
  const expense = await eventRef.collection("expenses").add({
    title,
    amountMinor,
    currency: "EUR",
    paidByUid: body.paidByUid,
    participantUids,
    sharesByUid,
    createdByUid: request.auth.uid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  return { expenseId: expense.id };
});

export const voidGroupEventExpense = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, expenseId } = (request.data ?? {}) as Partial<VoidGroupEventExpenseRequest>;
  if (!eventId || typeof eventId !== "string" || !expenseId || typeof expenseId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültige Ausgabe.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  const expenseRef = eventRef.collection("expenses").doc(expenseId);
  await db.runTransaction(async (tx) => {
    const [event, expense, settlements] = await Promise.all([
      tx.get(eventRef),
      tx.get(expenseRef),
      tx.get(eventRef.collection("settlements").limit(1)),
    ]);
    const participantUids = (event.data()?.participantUids ?? []) as string[];
    if (!event.exists || !participantUids.includes(request.auth!.uid)) throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
    if (!expense.exists || expense.data()?.status !== "active") throw new HttpsError("not-found", "Diese Ausgabe ist nicht mehr verfügbar.");
    if (expense.data()?.createdByUid !== request.auth!.uid && event.data()?.creatorUid !== request.auth!.uid) {
      throw new HttpsError("permission-denied", "Du kannst diese Ausgabe nicht stornieren.");
    }
    // Once money has been marked as paid, silently removing an expense would rewrite the basis
    // of that payment and corrupt everybody's balances. Keep the ledger immutable from here on.
    if (!settlements.empty) {
      throw new HttpsError("failed-precondition", "Eine Ausgabe kann nach der ersten Zahlung nicht mehr storniert werden.");
    }
    tx.update(expenseRef, { status: "voided", updatedAt: Timestamp.now() });
  });
  return { voided: true };
});

export const markGroupEventSettlementPaid = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const body = (request.data ?? {}) as Partial<MarkGroupEventSettlementPaidRequest>;
  if (!body.eventId || typeof body.eventId !== "string" || !body.toUid || typeof body.toUid !== "string") {
    throw new HttpsError("invalid-argument", "Ungültige Zahlung.");
  }
  if (body.toUid === request.auth.uid) throw new HttpsError("invalid-argument", "Du kannst nicht an dich selbst zahlen.");
  const toUid = body.toUid;
  const amountMinor = requireInteger(body.amountMinor, "Betrag", 1, 1_000_000);
  if (body.currency !== "EUR") throw new HttpsError("invalid-argument", "Aktuell wird nur Euro unterstützt.");
  const eventRef = db.collection("groupEvents").doc(body.eventId);
  const payment = eventRef.collection("settlements").doc();
  await db.runTransaction(async (tx) => {
    const [event, expenses, settlements] = await Promise.all([
      tx.get(eventRef),
      tx.get(eventRef.collection("expenses").where("status", "==", "active")),
      tx.get(eventRef.collection("settlements")),
    ]);
    const participantUids = (event.data()?.participantUids ?? []) as string[];
    if (!event.exists || !participantUids.includes(request.auth!.uid)) {
      throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
    }
    if (!participantUids.includes(toUid)) {
      throw new HttpsError("invalid-argument", "Die empfangende Person gehört nicht zum Plan.");
    }
    const openAmount = settlementCapacityFromSnapshots(
      expenses,
      settlements,
      request.auth!.uid,
      toUid,
      participantUids,
    );
    if (openAmount < amountMinor) {
      throw new HttpsError("failed-precondition", "Der markierte Betrag ist höher als der noch offene Anteil.");
    }
    tx.create(payment, {
      fromUid: request.auth!.uid,
      toUid,
      amountMinor,
      currency: "EUR",
      status: "markedPaid",
      createdAt: Timestamp.now(),
      confirmedAt: null,
    });
    // All payment transactions also touch the parent event. This single contention point makes
    // two simultaneous "paid" taps retry against the newest settlement set instead of both
    // succeeding from the same stale balance snapshot.
    tx.update(eventRef, { ledgerUpdatedAt: Timestamp.now() });
  });
  void sendGenericPush([toUid], {
    title: "Zahlung markiert",
    body: "Eine Person hat eine gemeinsame Ausgabe als bezahlt markiert.",
    data: { type: "group_event", eventId: body.eventId },
  }).catch((error) => console.warn("Push notification for settlement failed.", error));
  return { settlementId: payment.id };
});

export const confirmGroupEventSettlement = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId, settlementId } = (request.data ?? {}) as Partial<ConfirmGroupEventSettlementRequest>;
  if (!eventId || typeof eventId !== "string" || !settlementId || typeof settlementId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültige Zahlung.");
  }
  const eventRef = db.collection("groupEvents").doc(eventId);
  const paymentRef = eventRef.collection("settlements").doc(settlementId);
  await db.runTransaction(async (tx) => {
    const [event, payment] = await Promise.all([tx.get(eventRef), tx.get(paymentRef)]);
    const participantUids = (event.data()?.participantUids ?? []) as string[];
    if (!event.exists || !participantUids.includes(request.auth!.uid)) throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
    if (!payment.exists || payment.data()?.toUid !== request.auth!.uid || payment.data()?.status !== "markedPaid") {
      throw new HttpsError("failed-precondition", "Diese Zahlung kann nicht bestätigt werden.");
    }
    tx.update(paymentRef, { status: "confirmed", confirmedAt: Timestamp.now() });
  });
  return { confirmed: true };
});

export const setGroupEventPaymentLink = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { url } = (request.data ?? {}) as Partial<SetGroupEventPaymentLinkRequest>;
  const normalizedURL = validatePayPalMeURL(url);
  await db.collection("users").doc(request.auth.uid).collection("privateSettings").doc("payment").set({
    paypalMeURL: normalizedURL,
    updatedAt: Timestamp.now(),
  }, { merge: true });
  return { saved: true };
});

export const getGroupEventPaymentLinks = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { eventId } = (request.data ?? {}) as Partial<GetGroupEventPaymentLinksRequest>;
  if (!eventId || typeof eventId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Plan.");
  const eventRef = db.collection("groupEvents").doc(eventId);
  await ensureEventParticipant(eventRef, request.auth.uid);
  const event = await eventRef.get();
  const participantUids = (event.data()?.participantUids ?? []) as string[];
  const snapshots = await Promise.all(participantUids.map((uid) =>
    db.collection("users").doc(uid).collection("privateSettings").doc("payment").get(),
  ));
  const links: Record<string, string> = {};
  snapshots.forEach((snapshot, index) => {
    const value = snapshot.data()?.paypalMeURL;
    if (typeof value === "string") links[participantUids[index]] = value;
  });
  return { links };
});

function settlementCapacityFromSnapshots(
  expenses: FirebaseFirestore.QuerySnapshot,
  settlements: FirebaseFirestore.QuerySnapshot,
  fromUid: string,
  toUid: string,
  participantUIDs: string[],
): number {
  const balances: Record<string, number> = Object.fromEntries(participantUIDs.map((uid) => [uid, 0]));
  expenses.forEach((snapshot) => {
    const expense = snapshot.data();
    const payer = expense.paidByUid;
    if (typeof payer === "string" && payer in balances && Number.isSafeInteger(expense.amountMinor)) {
      balances[payer] += expense.amountMinor;
    }
    const shares = expense.sharesByUid;
    if (shares && typeof shares === "object" && !Array.isArray(shares)) {
      for (const [uid, value] of Object.entries(shares as Record<string, unknown>)) {
        if (uid in balances && typeof value === "number" && Number.isSafeInteger(value)) balances[uid] -= value;
      }
    }
  });
  settlements.forEach((snapshot) => {
    const payment = snapshot.data();
    if (!["markedPaid", "confirmed"].includes(payment.status)) return;
    if (typeof payment.fromUid !== "string" || typeof payment.toUid !== "string" || !Number.isSafeInteger(payment.amountMinor)) return;
    if (payment.fromUid in balances) balances[payment.fromUid] += payment.amountMinor;
    if (payment.toUid in balances) balances[payment.toUid] -= payment.amountMinor;
  });
  return Math.max(0, Math.min(-(balances[fromUid] ?? 0), balances[toUid] ?? 0));
}

function validateInvitees(value: unknown, creatorUid: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > 8 || !value.every((uid) => typeof uid === "string" && uid.length > 0)) {
    throw new HttpsError("invalid-argument", "Du kannst höchstens acht Personen einladen.");
  }
  return [...new Set(value as string[])].filter((uid) => uid !== creatorUid);
}

function requireInteger(value: unknown, field: string, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new HttpsError("invalid-argument", `${field} ist ungültig.`);
  }
  return value;
}

function validateExpenseParticipants(value: unknown, eventUIDs: string[]): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 9 || !value.every((uid) => typeof uid === "string")) {
    throw new HttpsError("invalid-argument", "Wähle mindestens eine beteiligte Person aus.");
  }
  const result = [...new Set(value as string[])];
  if (result.some((uid) => !eventUIDs.includes(uid))) throw new HttpsError("invalid-argument", "Mindestens eine Person gehört nicht zum Plan.");
  return result;
}

function validateExpenseShares(value: unknown, participantUIDs: string[], amountMinor: number): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HttpsError("invalid-argument", "Ungültige Aufteilung.");
  const input = value as Record<string, unknown>;
  if (Object.keys(input).length !== participantUIDs.length || Object.keys(input).some((uid) => !participantUIDs.includes(uid))) {
    throw new HttpsError("invalid-argument", "Die Aufteilung passt nicht zu den ausgewählten Personen.");
  }
  const shares: Record<string, number> = {};
  for (const uid of participantUIDs) shares[uid] = requireInteger(input[uid], "Anteil", 0, amountMinor);
  if (Object.values(shares).reduce((sum, share) => sum + share, 0) !== amountMinor) {
    throw new HttpsError("invalid-argument", "Die Anteile müssen zusammen dem Gesamtbetrag entsprechen.");
  }
  return shares;
}

function validatePayPalMeURL(value: unknown): string {
  const raw = requireText(value, "PayPal.Me-Link", 200);
  let parsed: URL;
  try { parsed = new URL(raw); } catch { throw new HttpsError("invalid-argument", "Ungültiger PayPal.Me-Link."); }
  if (parsed.protocol !== "https:" || !["paypal.me", "www.paypal.me"].includes(parsed.hostname.toLowerCase())) {
    throw new HttpsError("invalid-argument", "Bitte verwende einen PayPal.Me-Link.");
  }
  const handle = parsed.pathname.split("/").filter(Boolean)[0];
  if (!handle || !/^[A-Za-z0-9._-]{1,40}$/.test(handle)) throw new HttpsError("invalid-argument", "Ungültiger PayPal.Me-Name.");
  return `https://paypal.me/${handle}`;
}

function validatePlanSteps(value: unknown): Array<{ id: string; title: string }> {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) {
    throw new HttpsError("invalid-argument", "Ein Plan braucht ein bis drei Bausteine.");
  }
  return value.map((entry, index) => ({ id: `step-${index + 1}`, title: requireText(entry, "Planbaustein", 100) }));
}

function validateLicensedImage(value: unknown): LicensedImageReference | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object") throw new HttpsError("invalid-argument", "Ungültiges Titelbild.");
  const image = value as Partial<LicensedImageReference>;
  const url = requireText(image.url, "Bild-URL", 2_000);
  const sourcePageURL = requireText(image.sourcePageURL, "Bildquelle", 2_000);
  // Server-generated route visuals live in our own Storage and are referenced as storage://
  // (see generateDateStationImages). Only that exact, hash-named location is accepted, so a
  // client cannot point a cover at an arbitrary Storage object.
  const isGeneratedRouteImage = /^storage:\/\/generatedDateImages\/v\d+\/[a-f0-9]{64}\.jpg$/.test(url);
  if ((!url.startsWith("https://") && !isGeneratedRouteImage) || !sourcePageURL.startsWith("https://")) {
    throw new HttpsError("invalid-argument", "Ungültige Bildquelle.");
  }
  const creator = requireText(image.creator, "Urheber:in", 160);
  const license = requireText(image.license, "Lizenz", 120);
  const licenseURL = image.licenseURL === null || image.licenseURL === undefined
    ? null
    : requireText(image.licenseURL, "Lizenz-Link", 2_000);
  return { url, sourcePageURL, creator, license, licenseURL };
}

function resolveEventTitle(value: unknown, planSteps: Array<{ id: string; title: string }>): string {
  if (typeof value === "string" && value.trim().length > 0) {
    // Generated route titles can be longer than the display limit. Shorten rather than reject:
    // a valid plan must never fail over its headline.
    return requireText(value.trim().slice(0, 70), "Titel", 70);
  }
  if (planSteps[0]?.title) {
    return requireText(planSteps[0].title.slice(0, 70), "Titel", 70);
  }
  return requireText(value, "Titel", 70);
}

async function ensureEventParticipant(eventRef: FirebaseFirestore.DocumentReference, uid: string): Promise<PersonProfileSnapshot> {
  const event = await eventRef.get();
  const participantUids = (event.data()?.participantUids ?? []) as string[];
  if (!event.exists || event.data()?.status !== "planned" || !participantUids.includes(uid)) {
    throw new HttpsError("permission-denied", "Du bist nicht Teil dieses Plans.");
  }
  const participant = (event.data()?.participants ?? []).find((person: EventParticipant) => person.uid === uid);
  if (participant) {
    return { uid: participant.uid, displayName: participant.displayName, handle: participant.handle, avatarPath: participant.avatarPath ?? null };
  }
  return ensurePersonProfile(uid);
}

async function publicInviteeSnapshot(uid: string): Promise<PersonProfileSnapshot> {
  const profile = await db.collection("personProfiles").doc(uid).get();
  if (!profile.exists || profile.data()?.isDiscoverable !== true) {
    throw new HttpsError("not-found", "Mindestens ein ausgewähltes Profil ist nicht öffentlich.");
  }
  const data = profile.data()!;
  return { uid, displayName: data.displayName as string, handle: data.handle as string, avatarPath: typeof data.avatarPath === "string" ? data.avatarPath : null };
}

/** Blocked profiles must not bypass the safety control through a group invitation. Reading
 * both directions in the same transaction as the invite also covers a concurrent block. */
async function assertNoInvitationBlocks(tx: FirebaseFirestore.Transaction, senderUid: string, invitees: string[]): Promise<void> {
  const snapshots = await Promise.all(invitees.flatMap((uid) => [
    tx.get(db.collection("socialBlocks").doc(`${senderUid}_${uid}`)),
    tx.get(db.collection("socialBlocks").doc(`${uid}_${senderUid}`)),
  ]));
  if (snapshots.some((snapshot) => snapshot.exists)) {
    throw new HttpsError("permission-denied", "Mindestens eine Person kann nicht zu diesem Plan eingeladen werden.");
  }
}

/** Fast preflight for user-facing failures. The transactional check above is authoritative. */
async function assertNoInvitationBlocksBeforeQuota(senderUid: string, invitees: string[]): Promise<void> {
  if (invitees.length === 0) return;
  const refs = invitees.flatMap((uid) => [
    db.collection("socialBlocks").doc(`${senderUid}_${uid}`),
    db.collection("socialBlocks").doc(`${uid}_${senderUid}`),
  ]);
  const snapshots = await db.getAll(...refs);
  if (snapshots.some((snapshot) => snapshot.exists)) {
    throw new HttpsError("permission-denied", "Mindestens eine Person kann nicht zu diesem Plan eingeladen werden.");
  }
}

function parseFutureDate(value: unknown): Timestamp {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", "Bitte wähle einen Zeitpunkt.");
  const date = new Date(value);
  if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now() + 5 * 60 * 1000) {
    throw new HttpsError("invalid-argument", "Der Zeitpunkt muss in der Zukunft liegen.");
  }
  if (date.getTime() > Date.now() + 366 * 24 * 60 * 60 * 1000) {
    throw new HttpsError("invalid-argument", "Bitte plane höchstens ein Jahr im Voraus.");
  }
  return Timestamp.fromDate(date);
}
