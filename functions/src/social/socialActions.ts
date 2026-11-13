import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { backfillFollowingFeed, removeFollowingFeedItems } from "./feedHelpers";
import { optionalActiveCouple, requireActiveCouple } from "./socialHelpers";
import type { PostVisibility, ReactionKind } from "./types";

interface FollowRequest {
  targetCoupleId: string;
}

interface ReactionRequest {
  postId: string;
  kind: ReactionKind;
}

interface ViewerSocialStateRequest {
  postIds?: string[];
}

const savedPostIndex = (uid: string, postId: string) =>
  db.collection("users").doc(uid).collection("savedPosts").doc(postId);

/** Follow is immediate in Phase 2; private posts are still never copied into the follower feed. */
export const followCouple = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { coupleId } = await requireActiveCouple(request.auth.uid);
  const { targetCoupleId } = (request.data ?? {}) as Partial<FollowRequest>;
  if (!targetCoupleId || typeof targetCoupleId !== "string" || targetCoupleId === coupleId) {
    throw new HttpsError("invalid-argument", "Ungültiges Paar.");
  }
  if (!(await db.collection("coupleProfiles").doc(targetCoupleId).get()).exists) {
    throw new HttpsError("not-found", "Dieses Paar-Profil existiert nicht.");
  }

  const followRef = db.collection("follows").doc(`${coupleId}_${targetCoupleId}`);
  await followRef.set({ followerCoupleId: coupleId, targetCoupleId, createdAt: Timestamp.now() }, { merge: true });
  await backfillFollowingFeed(coupleId, targetCoupleId);
  return { isFollowing: true };
});

export const unfollowCouple = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { coupleId } = await requireActiveCouple(request.auth.uid);
  const { targetCoupleId } = (request.data ?? {}) as Partial<FollowRequest>;
  if (!targetCoupleId || typeof targetCoupleId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiges Paar.");
  }

  await db.collection("follows").doc(`${coupleId}_${targetCoupleId}`).delete();
  await removeFollowingFeedItems(coupleId, targetCoupleId);
  return { isFollowing: false };
});

/** Reactions belong to a person. Legacy couple reactions remain readable and are migrated on tap. */
export const togglePostReaction = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const couple = await optionalActiveCouple(uid);
  const { postId, kind } = (request.data ?? {}) as Partial<ReactionRequest>;
  if (!postId || typeof postId !== "string" || (kind !== "like" && kind !== "save")) {
    throw new HttpsError("invalid-argument", "Ungültige Reaktion.");
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnap = await postRef.get();
  if (!postSnap.exists || !(await canAccessPost(postSnap.data()!, uid, couple?.coupleId))) {
    throw new HttpsError("permission-denied", "Dieser Post ist nicht verfügbar.");
  }

  const collection = kind === "like" ? "likes" : "saves";
  const countField = kind === "like" ? "likesCount" : "savesCount";
  const reactionRef = postRef.collection(collection).doc(uid);
  const legacyReactionRef = couple && couple.coupleId !== uid
    ? postRef.collection(collection).doc(couple.coupleId)
    : null;
  const isActive = await db.runTransaction(async (tx) => {
    const [existing, legacyExisting] = await Promise.all([
      tx.get(reactionRef),
      legacyReactionRef ? tx.get(legacyReactionRef) : Promise.resolve(null),
    ]);
    if (existing.exists) {
      tx.delete(reactionRef);
      if (kind === "save") tx.delete(savedPostIndex(uid, postId));
      tx.update(postRef, { [countField]: FieldValue.increment(-1), updatedAt: Timestamp.now() });
      return false;
    }
    if (legacyReactionRef && legacyExisting?.exists) {
      tx.delete(legacyReactionRef);
      if (kind === "save") tx.delete(savedPostIndex(uid, postId));
      tx.update(postRef, { [countField]: FieldValue.increment(-1), updatedAt: Timestamp.now() });
      return false;
    }
    const now = Timestamp.now();
    tx.set(reactionRef, { uid, createdAt: now });
    if (kind === "save") tx.set(savedPostIndex(uid, postId), { postId, createdAt: now });
    tx.update(postRef, { [countField]: FieldValue.increment(1), updatedAt: Timestamp.now() });
    return true;
  });

  return { isActive };
});

/**
 * `follows` is intentionally not readable from the client. This callable returns only the
 * caller's own relationship/reaction state for currently accessible feed posts, so the UI can
 * render reliable follow/like/save states without opening a relationship-discovery endpoint.
 */
export const getViewerSocialState = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const couple = await optionalActiveCouple(uid);
  const rawPostIds = (request.data ?? {}) as ViewerSocialStateRequest;
  const postIds = rawPostIds.postIds ?? [];
  if (!Array.isArray(postIds) || postIds.length > 50 || !postIds.every((id) => typeof id === "string" && id.length > 0)) {
    throw new HttpsError("invalid-argument", "Ungültige Beitragsliste.");
  }

  const followingSnap = couple
    ? await db.collection("follows").where("followerCoupleId", "==", couple.coupleId).get()
    : null;
  const followingCoupleIds = followingSnap?.docs.map((doc) => doc.data().targetCoupleId as string) ?? [];
  const followingSet = new Set(followingCoupleIds);
  const blockedUIDs = await blockedUIDsFor(uid);
  const uniquePostIds = [...new Set(postIds)];
  const posts = await Promise.all(uniquePostIds.map((postId) => db.collection("posts").doc(postId).get()));

  const accessible = await Promise.all(posts.map(async (post) => {
    if (!post.exists) return null;
    const data = post.data()!;
    const canAccess = data.status === "published"
      && await canAccessPost(data, uid, couple?.coupleId, followingSet, blockedUIDs);
    return canAccess ? post.id : null;
  }));
  const accessiblePostIds = accessible.filter((postId): postId is string => postId !== null);

  const reactions = await Promise.all(accessiblePostIds.flatMap((postId) => {
    const postRef = db.collection("posts").doc(postId);
    return [
      postRef.collection("likes").doc(uid).get(),
      postRef.collection("saves").doc(uid).get(),
      couple ? postRef.collection("likes").doc(couple.coupleId).get() : Promise.resolve(null),
      couple ? postRef.collection("saves").doc(couple.coupleId).get() : Promise.resolve(null),
    ];
  }));

  const likedPostIds: string[] = [];
  const savedPostIds: string[] = [];
  const savedAtByPost = new Map<string, Timestamp>();
  reactions.forEach((reaction, index) => {
    if (!reaction?.exists) return;
    const postId = accessiblePostIds[Math.floor(index / 4)];
    if (index % 4 === 0 || index % 4 === 2) likedPostIds.push(postId);
    else {
      savedPostIds.push(postId);
      const createdAt = reaction.data()?.createdAt;
      if (createdAt instanceof Timestamp && !savedAtByPost.has(postId)) savedAtByPost.set(postId, createdAt);
    }
  });

  if (savedAtByPost.size > 0) {
    const batch = db.batch();
    savedAtByPost.forEach((createdAt, postId) => {
      batch.set(savedPostIndex(uid, postId), { postId, createdAt }, { merge: true });
    });
    await batch.commit();
  }

  return { followingCoupleIds, likedPostIds, savedPostIds };
});

/** Returns only the caller's saved, still-accessible Moments in newest-save-first order. */
export const getSavedPostIds = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const couple = await optionalActiveCouple(uid);
  const blockedUIDs = await blockedUIDsFor(uid);
  const saved = await db.collection("users").doc(uid).collection("savedPosts")
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  const posts = await Promise.all(saved.docs.map(async (entry) => {
    const postId = entry.data().postId as string | undefined;
    if (!postId) return null;
    const post = await db.collection("posts").doc(postId).get();
    if (!post.exists || post.data()?.status !== "published") return null;
    return await canAccessPost(post.data()!, uid, couple?.coupleId, undefined, blockedUIDs) ? post.id : null;
  }));
  return { postIds: posts.filter((postId): postId is string => postId !== null) };
});

async function canAccessPost(
  post: Record<string, unknown>,
  viewerUid: string,
  viewerCoupleId?: string,
  knownFollowingCouples?: Set<string>,
  knownBlockedUIDs?: Set<string>,
): Promise<boolean> {
  const ownerCoupleId = post.ownerCoupleId as string;
  const ownerUid = post.ownerUid as string | undefined;
  if (ownerUid && ownerUid !== viewerUid) {
    if (knownBlockedUIDs?.has(ownerUid)) return false;
    if (!knownBlockedUIDs && await hasBlockBetween(viewerUid, ownerUid)) return false;
  }
  if ((ownerUid === viewerUid && ownerCoupleId === viewerUid)
    || ownerCoupleId === viewerCoupleId
    || post.visibility === "public") return true;
  if (post.visibility !== ("followers" satisfies PostVisibility)) return false;
  if (ownerUid && (await db.collection("personFollows").doc(`${viewerUid}_${ownerUid}`).get()).exists) return true;
  if (!viewerCoupleId) return false;
  if (knownFollowingCouples?.has(ownerCoupleId)) return true;
  return (await db.collection("follows").doc(`${viewerCoupleId}_${ownerCoupleId}`).get()).exists;
}

async function blockedUIDsFor(uid: string): Promise<Set<string>> {
  const [outgoing, incoming] = await Promise.all([
    db.collection("socialBlocks").where("blockerUid", "==", uid).limit(200).get(),
    db.collection("socialBlocks").where("targetUid", "==", uid).limit(200).get(),
  ]);
  return new Set([
    ...outgoing.docs.map((block) => block.data().targetUid as string),
    ...incoming.docs.map((block) => block.data().blockerUid as string),
  ]);
}

async function hasBlockBetween(firstUid: string, secondUid: string): Promise<boolean> {
  const [outgoing, incoming] = await Promise.all([
    db.collection("socialBlocks").doc(`${firstUid}_${secondUid}`).get(),
    db.collection("socialBlocks").doc(`${secondUid}_${firstUid}`).get(),
  ]);
  return outgoing.exists || incoming.exists;
}
