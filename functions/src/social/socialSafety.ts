import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { optionalText } from "./socialHelpers";

interface TargetRequest { targetUid: string; }
interface ReportRequest extends TargetRequest {
  reason?: string;
  note?: string;
  postId?: string;
  commentId?: string;
}

/** Blocks are private to the reporter and immediately dissolve direct personal follows. */
export const blockSocialProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { targetUid } = (request.data ?? {}) as Partial<TargetRequest>;
  const uid = request.auth.uid;
  validateTarget(targetUid, uid);
  await db.runTransaction(async (tx) => {
    const outgoingFollowRef = db.collection("personFollows").doc(`${uid}_${targetUid}`);
    const incomingFollowRef = db.collection("personFollows").doc(`${targetUid}_${uid}`);
    const [target, outgoingFollow, incomingFollow] = await Promise.all([
      tx.get(db.collection("personProfiles").doc(targetUid!)), tx.get(outgoingFollowRef), tx.get(incomingFollowRef),
    ]);
    if (!target.exists) throw new HttpsError("not-found", "Dieses Profil existiert nicht.");
    tx.set(db.collection("socialBlocks").doc(`${uid}_${targetUid}`), { blockerUid: uid, targetUid, createdAt: Timestamp.now() });
    if (outgoingFollow.exists) {
      tx.delete(outgoingFollowRef);
      tx.set(db.collection("personProfiles").doc(uid), { followingCount: FieldValue.increment(-1) }, { merge: true });
      tx.set(db.collection("personProfiles").doc(targetUid), { followerCount: FieldValue.increment(-1) }, { merge: true });
    }
    if (incomingFollow.exists) {
      tx.delete(incomingFollowRef);
      tx.set(db.collection("personProfiles").doc(targetUid), { followingCount: FieldValue.increment(-1) }, { merge: true });
      tx.set(db.collection("personProfiles").doc(uid), { followerCount: FieldValue.increment(-1) }, { merge: true });
    }
  });
  return { isBlocked: true };
});

export const unblockSocialProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { targetUid } = (request.data ?? {}) as Partial<TargetRequest>;
  validateTarget(targetUid, request.auth.uid);
  await db.collection("socialBlocks").doc(`${request.auth.uid}_${targetUid}`).delete();
  return { isBlocked: false };
});

/** Reports are retained server-side and intentionally cannot be browsed by a client. */
export const reportSocialProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { targetUid, reason, note, postId, commentId } = (request.data ?? {}) as Partial<ReportRequest>;
  validateTarget(targetUid, request.auth.uid);
  const safeReason = typeof reason === "string" && ["profile", "harassment", "impersonation", "other"].includes(reason) ? reason : "profile";
  let contentContext: Record<string, unknown> = {};
  if (postId !== undefined || commentId !== undefined) {
    if (!postId || typeof postId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Beitragsverweis.");
    const post = await db.collection("posts").doc(postId).get();
    if (!post.exists || post.data()?.status !== "published") {
      throw new HttpsError("not-found", "Dieser Beitrag ist nicht mehr verfügbar.");
    }
    if (commentId !== undefined) {
      if (!commentId || typeof commentId !== "string") throw new HttpsError("invalid-argument", "Ungültiger Kommentarverweis.");
      const comment = await post.ref.collection("comments").doc(commentId).get();
      if (!comment.exists || comment.data()?.authorUid !== targetUid) {
        throw new HttpsError("not-found", "Dieser Kommentar ist nicht mehr verfügbar.");
      }
      contentContext = {
        contentType: "postComment",
        postId,
        commentId,
        reportedBody: typeof comment.data()?.body === "string" ? comment.data()?.body : "",
      };
    } else {
      const postAuthorUid = post.data()?.ownerUid ?? post.data()?.creator?.uid;
      if (postAuthorUid !== targetUid) throw new HttpsError("invalid-argument", "Dieses Profil gehört nicht zum Beitrag.");
      contentContext = {
        contentType: "post",
        postId,
        reportedBody: typeof post.data()?.caption === "string" ? post.data()?.caption : "",
      };
    }
  }
  await db.collection("socialReports").add({
    reporterUid: request.auth.uid,
    targetUid,
    reason: safeReason,
    note: optionalText(note, "Hinweis", 500),
    ...contentContext,
    createdAt: Timestamp.now(),
  });
  return { reported: true };
});

function validateTarget(targetUid: unknown, uid: string): asserts targetUid is string {
  if (!targetUid || typeof targetUid !== "string" || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Ungültiges Profil.");
  }
}
