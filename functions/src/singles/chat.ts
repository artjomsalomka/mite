import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { sendGenericPush } from "../pushNotifications";
import { requiredText } from "./singleHelpers";
import { ChatRateLimitState, nextChatRateLimit } from "./chatRateLimit";

interface SendSingleMessageRequest {
  matchId: string;
  body: string;
}
interface MarkSingleMatchReadRequest { matchId: string; }

// The chat deliberately has no attachments, contact cards, links or location payloads. The
// lightweight text check is a guardrail, not an identity-verification substitute; it prevents
// common attempts to move a first conversation off-platform by default.
const contactDetailPattern = /(?:[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|(?:\+?\d[\d\s().-]{6,}\d)|https?:\/\/|www\.|\b(?:whatsapp|telegram|signal|snapchat|instagram|insta|tiktok)\b)/i;

export const sendSingleMessage = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");

  const { matchId, body } = (request.data ?? {}) as Partial<SendSingleMessageRequest>;
  if (!matchId || typeof matchId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiges Match.");
  }
  const normalizedBody = requiredText(body, "Nachricht", 800);
  if (contactDetailPattern.test(normalizedBody)) {
    throw new HttpsError(
      "failed-precondition",
      "Kontaktangaben und externe Kontaktwege bleiben vor dem ersten Treffen in der App privat."
    );
  }

  const matchRef = db.collection("singleMatches").doc(matchId);
  const messageRef = matchRef.collection("messages").doc();
  // This private, function-maintained record is not readable or writable by clients. Keeping
  // the check and message creation in one transaction prevents parallel taps from bypassing
  // the throttle or from writing after a match was removed.
  const rateLimitRef = matchRef.collection("messageRateLimits").doc(request.auth.uid);
  const memberUids = await db.runTransaction(async (transaction) => {
    const [match, rateLimitSnapshot] = await Promise.all([
      transaction.get(matchRef),
      transaction.get(rateLimitRef),
    ]);
    const members = (match.data()?.memberUids ?? []) as string[];
    if (!match.exists || match.data()?.status !== "matched" || !members.includes(request.auth!.uid)) {
      throw new HttpsError("permission-denied", "Dieses Match ist nicht verfügbar.");
    }

    const previous = rateLimitSnapshot.data();
    const state: ChatRateLimitState | undefined = previous?.windowStartedAt instanceof Timestamp
      && previous?.lastSentAt instanceof Timestamp
      && typeof previous.sentInWindow === "number"
      ? {
          windowStartedAtMilliseconds: previous.windowStartedAt.toMillis(),
          sentInWindow: previous.sentInWindow,
          lastSentAtMilliseconds: previous.lastSentAt.toMillis(),
        }
      : undefined;
    const now = Timestamp.now();
    const rateLimitDecision = nextChatRateLimit(state, now.toMillis());
    if (!rateLimitDecision.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        rateLimitDecision.reason === "too_fast"
          ? "Bitte warte kurz, bevor du die nächste Nachricht sendest."
          : "Du hast gerade viele Nachrichten gesendet. Bitte versuche es in einer Minute erneut.",
      );
    }

    transaction.set(rateLimitRef, {
      windowStartedAt: Timestamp.fromMillis(rateLimitDecision.nextState.windowStartedAtMilliseconds),
      sentInWindow: rateLimitDecision.nextState.sentInWindow,
      lastSentAt: now,
    });
    transaction.set(messageRef, {
      senderUid: request.auth!.uid,
      body: normalizedBody,
      createdAt: now,
    });
    transaction.update(matchRef, {
      lastMessageAt: now,
      lastMessageSenderUid: request.auth!.uid,
      updatedAt: now,
    });
    return members;
  });
  void sendGenericPush(
    memberUids.filter((memberUid) => memberUid !== request.auth!.uid),
    {
      title: "Neue Nachricht",
      body: "Du hast eine neue Nachricht in einem Match.",
      data: { type: "single_message", matchId },
    },
  ).catch((error) => console.warn("Push notification for chat message failed.", error));
  return { messageId: messageRef.id };
});

/** Keeps unread state private to the match document; clients may never forge the cursor. */
export const markSingleMatchRead = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { matchId } = (request.data ?? {}) as Partial<MarkSingleMatchReadRequest>;
  if (!matchId || typeof matchId !== "string") throw new HttpsError("invalid-argument", "Ungültiges Match.");
  const matchRef = db.collection("singleMatches").doc(matchId);
  await db.runTransaction(async (transaction) => {
    const match = await transaction.get(matchRef);
    const members = (match.data()?.memberUids ?? []) as string[];
    if (!match.exists || match.data()?.status !== "matched" || !members.includes(request.auth!.uid)) {
      throw new HttpsError("permission-denied", "Dieses Match ist nicht verfügbar.");
    }
    transaction.update(matchRef, { [`readAtByUid.${request.auth!.uid}`]: Timestamp.now() });
  });
  return { read: true };
});
