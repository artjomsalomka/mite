import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { auth, db } from "../firebaseAdmin";
import { removePostFromFollowerFeeds } from "../social/feedHelpers";

/**
 * Deletes the caller's product account and every user-owned record that is safe to remove.
 * Reports already made by or about a person are deliberately retained as minimal safety records;
 * their retention belongs to the published privacy policy, not to a hidden client-side delete.
 */
export const deleteOwnAccount = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Bitte melde dich erneut an.");
  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const user = await userRef.get();
  const coupleId = user.data()?.coupleId;

  if (typeof coupleId === "string" && coupleId.length > 0) {
    await deleteSharedCouple(coupleId, uid);
  }

  await deleteSinglePresence(uid);
  await deleteSocialPresence(uid);
  await getStorage().bucket().deleteFiles({ prefix: `userImages/${uid}/` });
  await getStorage().bucket().deleteFiles({ prefix: `socialProfileImages/${uid}/` });
  await getStorage().bucket().deleteFiles({ prefix: `singleProfileImages/${uid}/` });
  await db.recursiveDelete(userRef);
  await auth.deleteUser(uid);
  return { deleted: true };
});

/**
 * Dissolves only the optional pair connection. Both personal accounts, public person profiles,
 * friendships and group plans remain intact; genuinely shared pair dates/posts are removed after
 * an explicit destructive confirmation in the app.
 */
export const disconnectCouple = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Bitte melde dich erneut an.");
  const uid = request.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const user = await userRef.get();
  const coupleId = user.data()?.coupleId;
  if (typeof coupleId !== "string" || coupleId.length === 0) {
    throw new HttpsError("failed-precondition", "Du bist aktuell mit keinem Paarprofil verbunden.");
  }
  await deleteSharedCouple(coupleId, uid);
  await userRef.set({
    coupleId: FieldValue.delete(),
    accountMode: null,
    datingEnabled: false,
    updatedAt: Timestamp.now(),
  }, { merge: true });
  const personalProfileRef = db.collection("personProfiles").doc(uid);
  if ((await personalProfileRef.get()).exists) {
    await personalProfileRef.update({ linkedCoupleId: null, updatedAt: Timestamp.now() });
  }
  return { disconnected: true };
});

async function deleteSharedCouple(coupleId: string, deletingUid: string) {
  const coupleRef = db.collection("couples").doc(coupleId);
  const [couple, profile, posts, inviteCodes, outgoingFollows, incomingFollows] = await Promise.all([
    coupleRef.get(),
    db.collection("coupleProfiles").doc(coupleId).get(),
    db.collection("posts").where("ownerCoupleId", "==", coupleId).get(),
    db.collection("inviteCodes").where("coupleId", "==", coupleId).get(),
    db.collection("follows").where("followerCoupleId", "==", coupleId).get(),
    db.collection("follows").where("targetCoupleId", "==", coupleId).get(),
  ]);

  await deleteSocialReactions("coupleId", coupleId);

  for (const post of posts.docs) {
    await removePostFromFollowerFeeds(post.id, coupleId);
    await db.recursiveDelete(post.ref);
    await Promise.all([
      getStorage().bucket().deleteFiles({ prefix: `postImages/${coupleId}/${post.id}/` }),
      getStorage().bucket().deleteFiles({ prefix: `postVideos/${coupleId}/${post.id}/` }),
    ]);
  }

  const memberUids = (couple.data()?.memberUids ?? []) as string[];
  const remainingProfileSnapshots = await Promise.all(
    memberUids.filter((member) => member !== deletingUid)
      .map((memberUid) => db.collection("personProfiles").doc(memberUid).get()),
  );
  const remainingProfiles = new Map(remainingProfileSnapshots.map((snapshot) => [snapshot.id, snapshot.exists]));
  const batch = db.batch();
  for (const memberUid of memberUids.filter((member) => member !== deletingUid)) {
    batch.set(db.collection("users").doc(memberUid), {
      coupleId: FieldValue.delete(),
      accountMode: null,
      datingEnabled: false,
      updatedAt: Timestamp.now(),
    }, { merge: true });
    if (remainingProfiles.get(memberUid)) {
      batch.update(db.collection("personProfiles").doc(memberUid), {
        linkedCoupleId: null,
        updatedAt: Timestamp.now(),
      });
    }
  }
  for (const inviteCode of inviteCodes.docs) batch.delete(inviteCode.ref);
  for (const follow of [...outgoingFollows.docs, ...incomingFollows.docs]) batch.delete(follow.ref);
  if (profile.exists) {
    const handle = profile.data()?.handle;
    if (typeof handle === "string" && handle.length > 0) batch.delete(db.collection("profileHandles").doc(handle));
    batch.delete(profile.ref);
  }
  await batch.commit();
  await getStorage().bucket().deleteFiles({ prefix: `profileImages/${coupleId}/` });
  if (couple.exists) await db.recursiveDelete(coupleRef);
}

/** Remove the opt-in public identity and detach it from every private social relationship. */
async function deleteSocialPresence(uid: string) {
  const [profile, outgoing, incoming, events, blocksFrom, blocksTo, pendingPosts, acceptedPosts, ownedPersonalPosts, authoredComments] = await Promise.all([
    db.collection("personProfiles").doc(uid).get(),
    db.collection("personFollows").where("followerUid", "==", uid).get(),
    db.collection("personFollows").where("targetUid", "==", uid).get(),
    db.collection("groupEvents").where("participantUids", "array-contains", uid).get(),
    db.collection("socialBlocks").where("blockerUid", "==", uid).get(),
    db.collection("socialBlocks").where("targetUid", "==", uid).get(),
    db.collection("posts").where("pendingCollaboratorUids", "array-contains", uid).get(),
    db.collection("posts").where("acceptedCollaboratorUids", "array-contains", uid).get(),
    db.collection("posts").where("ownerCoupleId", "==", uid).get(),
    db.collectionGroup("comments").where("authorUid", "==", uid).get(),
  ]);

  await deleteSocialReactions("uid", uid);

  const ownedPersonalPostIDs = new Set(ownedPersonalPosts.docs.map((post) => post.id));
  for (const post of ownedPersonalPosts.docs) {
    await removePostFromFollowerFeeds(post.id, uid);
    await db.recursiveDelete(post.ref);
    await Promise.all([
      getStorage().bucket().deleteFiles({ prefix: `postImages/${uid}/${post.id}/` }),
      getStorage().bucket().deleteFiles({ prefix: `postVideos/${uid}/${post.id}/` }),
    ]);
  }

  // Counter projections are only presentation data, but keeping them correct prevents a deleted
  // profile from leaving misleading social proof on another public profile.
  for (const follow of outgoing.docs) {
    const targetUid = follow.data().targetUid as string | undefined;
    const batch = db.batch();
    batch.delete(follow.ref);
    if (targetUid) batch.set(db.collection("personProfiles").doc(targetUid), { followerCount: FieldValue.increment(-1) }, { merge: true });
    await batch.commit();
  }
  for (const follow of incoming.docs) {
    const followerUid = follow.data().followerUid as string | undefined;
    const batch = db.batch();
    batch.delete(follow.ref);
    if (followerUid) batch.set(db.collection("personProfiles").doc(followerUid), { followingCount: FieldValue.increment(-1) }, { merge: true });
    await batch.commit();
  }

  for (const event of events.docs) {
    const data = event.data();
    if (data.creatorUid === uid) {
      await db.recursiveDelete(event.ref);
      await getStorage().bucket().deleteFiles({ prefix: `groupEventImages/${event.id}/` });
      continue;
    }
    const participants = ((data.participants ?? []) as Array<{ uid?: string }>).filter((person) => person.uid !== uid);
    const participantUids = ((data.participantUids ?? []) as string[]).filter((participantUid) => participantUid !== uid);
    const batch = db.batch();
    batch.update(event.ref, { participants, participantUids, [`readAtByUid.${uid}`]: FieldValue.delete(), updatedAt: Timestamp.now() });
    batch.delete(event.ref.collection("availability").doc(uid));
    await batch.commit();
  }

  // Posts shared by another account remain part of that group's history, but a deleted person's
  // public snapshot must not survive inside their collaborator list or invitation projections.
  const collaborativePosts = new Map(
    [...pendingPosts.docs, ...acceptedPosts.docs].map((post) => [post.id, post]),
  );
  for (const post of collaborativePosts.values()) {
    const data = post.data();
    const collaborators = ((data.collaborators ?? []) as Array<{ uid?: string }>).filter((person) => person.uid !== uid);
    const pendingCollaboratorUids = ((data.pendingCollaboratorUids ?? []) as string[]).filter((personUid) => personUid !== uid);
    const acceptedCollaboratorUids = ((data.acceptedCollaboratorUids ?? []) as string[]).filter((personUid) => personUid !== uid);
    await post.ref.update({ collaborators, pendingCollaboratorUids, acceptedCollaboratorUids, updatedAt: Timestamp.now() });
  }

  for (const comment of authoredComments.docs) {
    const postRef = comment.ref.parent.parent;
    if (postRef && ownedPersonalPostIDs.has(postRef.id)) continue;
    const batch = db.batch();
    batch.delete(comment.ref);
    if (postRef && (await postRef.get()).exists) {
      batch.set(postRef, { commentsCount: FieldValue.increment(-1), updatedAt: Timestamp.now() }, { merge: true });
    }
    await batch.commit();
  }

  if (!blocksFrom.empty || !blocksTo.empty) {
    const batch = db.batch();
    for (const block of [...blocksFrom.docs, ...blocksTo.docs]) batch.delete(block.ref);
    await batch.commit();
  }

  if (profile.exists) {
    const handle = profile.data()?.handle;
    const batch = db.batch();
    batch.delete(profile.ref);
    if (typeof handle === "string" && handle.length > 0) batch.delete(db.collection("personProfileHandles").doc(handle));
    await batch.commit();
  }
}

async function deleteSocialReactions(field: "uid" | "coupleId", value: string): Promise<void> {
  for (const collectionName of ["likes", "saves"] as const) {
    const reactions = await db.collectionGroup(collectionName).where(field, "==", value).get();
    const countField = collectionName === "likes" ? "likesCount" : "savesCount";
    for (const reaction of reactions.docs) {
      const postRef = reaction.ref.parent.parent;
      if (!postRef) continue;
      await db.runTransaction(async (tx) => {
        const [freshReaction, post] = await Promise.all([tx.get(reaction.ref), tx.get(postRef)]);
        if (!freshReaction.exists) return;
        tx.delete(reaction.ref);
        if (post.exists) {
          tx.set(postRef, { [countField]: FieldValue.increment(-1), updatedAt: Timestamp.now() }, { merge: true });
        }
      });
    }
  }
}

async function deleteSinglePresence(uid: string) {
  const [matches, interestsFrom, interestsTo, blocksFrom, blocksTo] = await Promise.all([
    db.collection("singleMatches").where("memberUids", "array-contains", uid).get(),
    db.collection("singleInterests").where("fromUid", "==", uid).get(),
    db.collection("singleInterests").where("toUid", "==", uid).get(),
    db.collection("singleBlocks").where("blockerUid", "==", uid).get(),
    db.collection("singleBlocks").where("targetUid", "==", uid).get(),
  ]);
  await Promise.all(matches.docs.map((match) => db.recursiveDelete(match.ref)));
  const batch = db.batch();
  batch.delete(db.collection("singleProfiles").doc(uid));
  for (const document of [...interestsFrom.docs, ...interestsTo.docs, ...blocksFrom.docs, ...blocksTo.docs]) {
    batch.delete(document.ref);
  }
  await batch.commit();
}
