import { HttpsError } from "firebase-functions/v2/https";
import { Timestamp, type DocumentReference } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { nextChatRateLimit, type ChatRateLimitState } from "../singles/chatRateLimit";

/**
 * Serializes high-frequency social writes behind a private Firestore cursor. The same modest
 * policy used by first-contact chat is suitable for comments and plan rooms: it blocks floods
 * and accidental repeated taps without interfering with a normal conversation.
 */
export async function consumeSocialWriteQuota(rateLimitRef: DocumentReference): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateLimitRef);
    const data = snapshot.data();
    const state: ChatRateLimitState | undefined = data?.windowStartedAt instanceof Timestamp
      && data?.lastSentAt instanceof Timestamp
      && typeof data.sentInWindow === "number"
      ? {
          windowStartedAtMilliseconds: data.windowStartedAt.toMillis(),
          sentInWindow: data.sentInWindow,
          lastSentAtMilliseconds: data.lastSentAt.toMillis(),
        }
      : undefined;
    const now = Timestamp.now();
    const decision = nextChatRateLimit(state, now.toMillis());
    if (!decision.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        decision.reason === "too_fast"
          ? "Bitte warte kurz, bevor du erneut sendest."
          : "Du hast gerade viel gesendet. Bitte versuche es in einer Minute erneut.",
      );
    }
    transaction.set(rateLimitRef, {
      windowStartedAt: Timestamp.fromMillis(decision.nextState.windowStartedAtMilliseconds),
      sentInWindow: decision.nextState.sentInWindow,
      lastSentAt: now,
    });
  });
}
