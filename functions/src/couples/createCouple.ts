import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { generateInviteCode } from "./inviteCode";
import { resumableInviteCode } from "./pendingCoupleRecovery";

const MAX_CODE_ATTEMPTS = 10;

/**
 * Creates a new pending couple for the caller and reserves a unique 6-digit invite code.
 * Both the couple doc and the invite-code reservation are written here (Admin SDK) rather than
 * by the client directly, so the "exactly one pending->active transition, no double-join, no
 * colliding code" invariants live in one place instead of being re-derived in security-rules
 * language.
 */
export const createCouple = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const uid = request.auth.uid;

  const userRef = db.collection("users").doc(uid);
  const coupleRef = db.collection("couples").doc();

  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
    const code = generateInviteCode();
    const codeRef = db.collection("inviteCodes").doc(code);

    try {
      const result = await db.runTransaction(async (tx) => {
        // Reading the user inside the transaction is essential: two taps (or a retry after a
        // timeout) must not create two pending couples before either client observes the write.
        const [userSnap, codeSnap] = await Promise.all([tx.get(userRef), tx.get(codeRef)]);
        if (!userSnap.exists) {
          throw new HttpsError("failed-precondition", "Kein Nutzerprofil gefunden.");
        }

        const userData = userSnap.data()!;
        const existingCoupleId = userData.coupleId;
        if (typeof existingCoupleId === "string" && existingCoupleId.length > 0) {
          const existingCouple = await tx.get(db.collection("couples").doc(existingCoupleId));
          const existingInviteCode = resumableInviteCode(existingCouple.data(), uid);
          if (existingInviteCode) {
            return { coupleId: existingCoupleId, inviteCode: existingInviteCode };
          }
          throw new HttpsError("already-exists", "Du bist bereits einem Paar zugeordnet.");
        }

        if (codeSnap.exists) {
          throw new Error("CODE_TAKEN");
        }

        const displayName: string = typeof userData.displayName === "string" ? userData.displayName : "Unbekannt";
        const avatarPath = typeof userData.avatarPath === "string" ? userData.avatarPath : null;
        const now = Timestamp.now();
        tx.set(codeRef, { coupleId: coupleRef.id, createdAt: now, consumedAt: null });
        tx.set(coupleRef, {
          status: "pending",
          inviteCode: code,
          createdByUid: uid,
          createdAt: now,
          memberUids: [uid],
          members: [{ uid, displayName, avatarPath, joinedAt: now }],
        });
        tx.update(userRef, {
          coupleId: coupleRef.id,
          accountMode: "couple",
          datingEnabled: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { coupleId: coupleRef.id, inviteCode: code };
      });
      return result;
    } catch (error) {
      if (error instanceof Error && error.message === "CODE_TAKEN") {
        continue; // extremely rare collision on a 6-digit space — just retry with a new code
      }
      throw error;
    }
  }

  throw new HttpsError("resource-exhausted", "Konnte keinen freien Einladungscode reservieren, bitte erneut versuchen.");
});
