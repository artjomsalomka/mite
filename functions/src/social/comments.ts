import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, type DocumentReference } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { ensurePersonProfile } from "./personProfiles";
import { optionalActiveCouple } from "./socialHelpers";
import { syncPostToFollowerFeeds } from "./feedHelpers";
import { consumeSocialWriteQuota } from "./socialWriteRateLimit";
import type { PublishedPost } from "./types";

interface AddCommentRequest {
  postId: string;
  body: string;
}

interface DeleteCommentRequest {
  postId: string;
  commentId: string;
}

/**
 * Comments are Function-only so every entry has a verified social identity, text limits and a
 * server timestamp. The post owner's active couple can moderate a thread; everyone else can
 * only delete their own comment.
 */
export const addPostComment = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const couple = await optionalActiveCouple(uid);
  const { postId, body } = (request.data ?? {}) as Partial<AddCommentRequest>;
  if (!postId || typeof postId !== "string" || !body || typeof body !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Kommentar.");
  }
  const normalizedBody = body.trim();
  if (!normalizedBody || normalizedBody.length > 500) {
    throw new HttpsError("invalid-argument", "Ein Kommentar muss zwischen 1 und 500 Zeichen lang sein.");
  }

  const postRef = db.collection("posts").doc(postId);
  const post = await postRef.get();
  if (!post.exists || !await canAccessPost(post.data()!, uid, couple?.coupleId)) {
    throw new HttpsError("permission-denied", "Dieser Moment ist nicht verfügbar.");
  }

  const author = await ensurePersonProfile(request.auth.uid);
  const publicProfile = await db.collection("personProfiles").doc(request.auth.uid).get();
  if (publicProfile.data()?.isDiscoverable !== true) {
    throw new HttpsError("failed-precondition", "Bitte aktiviere zuerst dein öffentliches Profil, um zu kommentieren.");
  }

  await consumeSocialWriteQuota(
    db.collection("users").doc(request.auth.uid).collection("socialRateLimits").doc("comments"),
  );

  const now = Timestamp.now();
  const commentRef = postRef.collection("comments").doc();
  await db.runTransaction(async (tx) => {
    tx.set(commentRef, {
      authorUid: request.auth!.uid,
      author,
      body: normalizedBody,
      createdAt: now,
      updatedAt: now,
    });
    tx.set(postRef, { commentsCount: FieldValue.increment(1), updatedAt: now }, { merge: true });
  });
  await refreshFollowerProjection(postRef);
  return { commentId: commentRef.id };
});

export const deletePostComment = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const couple = await optionalActiveCouple(uid);
  const { postId, commentId } = (request.data ?? {}) as Partial<DeleteCommentRequest>;
  if (!postId || typeof postId !== "string" || !commentId || typeof commentId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Kommentar.");
  }

  const postRef = db.collection("posts").doc(postId);
  const commentRef = postRef.collection("comments").doc(commentId);
  await db.runTransaction(async (tx) => {
    const [post, comment] = await Promise.all([tx.get(postRef), tx.get(commentRef)]);
    if (!post.exists || !comment.exists || !await canAccessPost(post.data()!, uid, couple?.coupleId)) {
      throw new HttpsError("not-found", "Dieser Kommentar ist nicht verfügbar.");
    }
    const isOwnComment = comment.data()?.authorUid === request.auth!.uid;
    const isPostOwner = (post.data()?.ownerUid === uid && post.data()?.ownerCoupleId === uid)
      || (couple && post.data()?.ownerCoupleId === couple.coupleId);
    if (!isOwnComment && !isPostOwner) {
      throw new HttpsError("permission-denied", "Du darfst diesen Kommentar nicht löschen.");
    }
    tx.delete(commentRef);
    tx.set(postRef, { commentsCount: FieldValue.increment(-1), updatedAt: Timestamp.now() }, { merge: true });
  });
  await refreshFollowerProjection(postRef);
  return { commentId };
});

async function canAccessPost(post: Record<string, unknown>, uid: string, coupleId?: string): Promise<boolean> {
  if (typeof post.ownerUid === "string" && post.ownerUid !== uid) {
    const [outgoing, incoming] = await Promise.all([
      db.collection("socialBlocks").doc(`${uid}_${post.ownerUid}`).get(),
      db.collection("socialBlocks").doc(`${post.ownerUid}_${uid}`).get(),
    ]);
    if (outgoing.exists || incoming.exists) return false;
  }
  if ((post.ownerUid === uid && post.ownerCoupleId === uid)
    || post.ownerCoupleId === coupleId
    || post.visibility === "public") return true;
  if (post.visibility !== "followers" || typeof post.ownerCoupleId !== "string") return false;
  if (typeof post.ownerUid === "string"
    && (await db.collection("personFollows").doc(`${uid}_${post.ownerUid}`).get()).exists) return true;
  return Boolean(coupleId
    && (await db.collection("follows").doc(`${coupleId}_${post.ownerCoupleId}`).get()).exists);
}

async function refreshFollowerProjection(postRef: DocumentReference): Promise<void> {
  const post = await postRef.get();
  if (!post.exists || post.data()?.status !== "published") return;
  await syncPostToFollowerFeeds({ id: post.id, ...post.data() } as PublishedPost);
}
