import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db } from "./firebaseAdmin";
import { sendGenericPush } from "./pushNotifications";

export const notifyCoupleDateSaved = onDocumentCreated(
  "couples/{coupleId}/savedDates/{savedDateId}",
  async (event) => {
    const savedDate = event.data?.data();
    if (!savedDate) return;
    const couple = await db.collection("couples").doc(event.params.coupleId).get();
    const memberUids = (couple.data()?.memberUids ?? []) as string[];
    const recipients = memberUids.filter((uid) => uid !== savedDate.createdByUid);
    await sendGenericPush(recipients, {
      title: "Neuer Date-Plan",
      body: "Ein gemeinsamer Date-Plan wurde gespeichert.",
      data: { type: "couple_date", coupleId: event.params.coupleId, savedDateId: event.params.savedDateId },
    }).catch((error) => logger.warn("Push notification for couple date failed.", { error }));
  },
);

export const notifyMatchDateSaved = onDocumentCreated(
  "singleMatches/{matchId}/savedDates/{savedDateId}",
  async (event) => {
    const savedDate = event.data?.data();
    if (!savedDate) return;
    const match = await db.collection("singleMatches").doc(event.params.matchId).get();
    const memberUids = (match.data()?.memberUids ?? []) as string[];
    const recipients = memberUids.filter((uid) => uid !== savedDate.createdByUid);
    await sendGenericPush(recipients, {
      title: "Neuer Date-Plan",
      body: "Ein gemeinsamer Date-Plan wurde gespeichert.",
      data: { type: "match_date", matchId: event.params.matchId, savedDateId: event.params.savedDateId },
    }).catch((error) => logger.warn("Push notification for match date failed.", { error }));
  },
);

export const notifyGroupEventCreated = onDocumentCreated(
  "groupEvents/{eventId}",
  async (event) => {
    const plan = event.data?.data();
    if (!plan) return;
    const recipients = ((plan.participantUids ?? []) as string[]).filter((uid) => uid !== plan.creatorUid);
    await sendGenericPush(recipients, {
      title: "Neue Einladung",
      body: "Du wurdest zu einem gemeinsamen Plan eingeladen.",
      data: { type: "group_event", eventId: event.params.eventId },
    }).catch((error) => logger.warn("Push notification for group event failed.", { error }));
  },
);

export const notifyGroupEventMessage = onDocumentCreated(
  "groupEvents/{eventId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const plan = await db.collection("groupEvents").doc(event.params.eventId).get();
    if (!plan.exists || plan.data()?.status !== "planned") return;
    const recipients = ((plan.data()?.participantUids ?? []) as string[]).filter((uid) => uid !== message.senderUid);
    await sendGenericPush(recipients, {
      title: "Neue Nachricht im Plan",
      body: "In einem gemeinsamen Plan gibt es eine neue Nachricht.",
      data: { type: "group_event_message", eventId: event.params.eventId },
    }).catch((error) => logger.warn("Push notification for group event message failed.", { error }));
  },
);
