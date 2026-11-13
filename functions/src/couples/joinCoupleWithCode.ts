import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";

interface JoinCoupleRequest {
  code: string;
}

export const joinCoupleWithCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const uid = request.auth.uid;

  const { code } = (request.data ?? {}) as Partial<JoinCoupleRequest>;
  if (!code || typeof code !== "string" || !/^\d{6}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Bitte einen gültigen 6-stelligen Code eingeben.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "Kein Nutzerprofil gefunden.");
  }
  if (userSnap.data()!.coupleId) {
    throw new HttpsError("already-exists", "Du bist bereits einem Paar zugeordnet.");
  }
  const displayName: string = userSnap.data()!.displayName ?? "Unbekannt";
  const avatarPath = typeof userSnap.data()!.avatarPath === "string" ? userSnap.data()!.avatarPath : null;

  const codeRef = db.collection("inviteCodes").doc(code);

  const coupleId = await db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(codeRef);
    if (!codeSnap.exists) {
      throw new HttpsError("not-found", "Dieser Code ist ungültig.");
    }
    const codeData = codeSnap.data()!;
    if (codeData.consumedAt) {
      throw new HttpsError("failed-precondition", "Dieser Code wurde bereits verwendet.");
    }

    const coupleRef = db.collection("couples").doc(codeData.coupleId as string);
    const coupleSnap = await tx.get(coupleRef);
    if (!coupleSnap.exists) {
      throw new HttpsError("not-found", "Das zugehörige Paar existiert nicht mehr.");
    }
    const coupleData = coupleSnap.data()!;
    if (coupleData.status !== "pending" || (coupleData.memberUids as string[]).length >= 2) {
      throw new HttpsError("failed-precondition", "Diesem Paar kann nicht mehr beigetreten werden.");
    }
    if ((coupleData.memberUids as string[]).includes(uid)) {
      throw new HttpsError("failed-precondition", "Du bist bereits Mitglied dieses Paares.");
    }

    const now = Timestamp.now();
    tx.update(coupleRef, {
      status: "active",
      memberUids: FieldValue.arrayUnion(uid),
      members: FieldValue.arrayUnion({ uid, displayName, avatarPath, joinedAt: now }),
    });
    tx.update(codeRef, { consumedAt: now });
    tx.update(userRef, {
      coupleId: coupleRef.id,
      accountMode: "couple",
      datingEnabled: false,
      updatedAt: now,
    });

    return coupleRef.id;
  });

  return { coupleId };
});
