import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { ensurePersonProfile } from "./personProfiles";

interface PersonFollowRequest {
  targetUid: string;
}

/**
 * Personal follows deliberately live next to the older couple follow graph.  A connection is
 * between two people, while the linked couple remains a visible context on the profile.
 */
export const followPerson = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { targetUid } = (request.data ?? {}) as Partial<PersonFollowRequest>;
  const followerUid = request.auth.uid;
  if (!targetUid || typeof targetUid !== "string" || targetUid === followerUid) {
    throw new HttpsError("invalid-argument", "Ungültiges Profil.");
  }

  const target = await db.collection("personProfiles").doc(targetUid).get();
  if (!target.exists || target.data()?.isDiscoverable !== true) {
    throw new HttpsError("not-found", "Dieses Profil ist nicht öffentlich.");
  }
  await ensurePersonProfile(followerUid);
  const followRef = db.collection("personFollows").doc(`${followerUid}_${targetUid}`);
  await db.runTransaction(async (tx) => {
    const [existing, outgoingBlock, incomingBlock] = await Promise.all([
      tx.get(followRef),
      tx.get(db.collection("socialBlocks").doc(`${followerUid}_${targetUid}`)),
      tx.get(db.collection("socialBlocks").doc(`${targetUid}_${followerUid}`)),
    ]);
    if (outgoingBlock.exists || incomingBlock.exists) {
      throw new HttpsError("permission-denied", "Zwischen diesen Profilen besteht eine Blockierung.");
    }
    if (existing.exists) return;
    tx.set(followRef, { followerUid, targetUid, createdAt: Timestamp.now() });
    tx.set(db.collection("personProfiles").doc(followerUid), { followingCount: FieldValue.increment(1) }, { merge: true });
    tx.set(db.collection("personProfiles").doc(targetUid), { followerCount: FieldValue.increment(1) }, { merge: true });
  });
  return { isFollowing: true };
});

export const unfollowPerson = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { targetUid } = (request.data ?? {}) as Partial<PersonFollowRequest>;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiges Profil.");
  }
  const followRef = db.collection("personFollows").doc(`${request.auth.uid}_${targetUid}`);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(followRef);
    if (!existing.exists) return;
    tx.delete(followRef);
    tx.set(db.collection("personProfiles").doc(request.auth!.uid), { followingCount: FieldValue.increment(-1) }, { merge: true });
    tx.set(db.collection("personProfiles").doc(targetUid), { followerCount: FieldValue.increment(-1) }, { merge: true });
  });
  return { isFollowing: false };
});

/** The graph stays private; clients receive only their own follow targets. */
export const getViewerPersonSocialState = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const follows = await db.collection("personFollows")
    .where("followerUid", "==", request.auth.uid)
    .limit(200)
    .get();
  const [outgoingBlocks, incomingBlocks] = await Promise.all([
    db.collection("socialBlocks").where("blockerUid", "==", request.auth.uid).limit(200).get(),
    db.collection("socialBlocks").where("targetUid", "==", request.auth.uid).limit(200).get(),
  ]);
  const followingUids = follows.docs.map((item) => item.data().targetUid as string);
  const profiles = await Promise.all(followingUids.map((uid) => db.collection("personProfiles").doc(uid).get()));
  // A profile that opts out immediately disappears from this list, even though the private
  // follow edge remains harmless until the viewer explicitly unfollows it.
  const followingPeople = profiles.flatMap((profile) => {
    const data = profile.data();
    if (!profile.exists || data?.isDiscoverable !== true) return [];
    return [{
      uid: profile.id,
      displayName: data.displayName as string,
      handle: data.handle as string,
      city: typeof data.city === "string" ? data.city : "",
      avatarPath: typeof data.avatarPath === "string" ? data.avatarPath : null,
      linkedCoupleId: typeof data.linkedCoupleId === "string" ? data.linkedCoupleId : null,
    }];
  });
  return {
    followingUids,
    followingPeople,
    blockedByMeUids: outgoingBlocks.docs.map((block) => block.data().targetUid as string),
    blockedMeUids: incomingBlocks.docs.map((block) => block.data().blockerUid as string),
  };
});
