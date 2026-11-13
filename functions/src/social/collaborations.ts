import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import type { PostCollaborator } from "./types";

interface RespondToCollaborationRequest {
  postId: string;
  accept: boolean;
}

/** Collaborators must actively opt in before a shared moment appears on their own profile. */
export const respondToPostCollaboration = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const { postId, accept } = (request.data ?? {}) as Partial<RespondToCollaborationRequest>;
  if (!postId || typeof postId !== "string" || typeof accept !== "boolean") {
    throw new HttpsError("invalid-argument", "Ungültige Zusammenarbeit.");
  }
  const postRef = db.collection("posts").doc(postId);
  await db.runTransaction(async (tx) => {
    const post = await tx.get(postRef);
    if (!post.exists || post.data()?.status !== "published") {
      throw new HttpsError("not-found", "Dieser Beitrag ist nicht verfügbar.");
    }
    const collaborators = (post.data()?.collaborators ?? []) as PostCollaborator[];
    const index = collaborators.findIndex((item) => item.uid === request.auth!.uid);
    if (index < 0) throw new HttpsError("permission-denied", "Du bist nicht zu diesem Beitrag eingeladen.");
    if (collaborators[index].status !== "pending") {
      throw new HttpsError("failed-precondition", "Diese Einladung wurde bereits beantwortet.");
    }
    collaborators[index] = { ...collaborators[index], status: accept ? "accepted" : "declined" };
    tx.update(postRef, {
      collaborators,
      pendingCollaboratorUids: collaborators.filter((item) => item.status === "pending").map((item) => item.uid),
      acceptedCollaboratorUids: collaborators.filter((item) => item.status === "accepted").map((item) => item.uid),
      updatedAt: Timestamp.now(),
    });
  });
  return { accepted: accept };
});
