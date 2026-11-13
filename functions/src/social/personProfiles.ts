import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { db } from "../firebaseAdmin";
import { syncPostToFollowerFeeds } from "./feedHelpers";
import { normalizeCity, normalizeHandle, optionalText, requireText } from "./socialHelpers";
import type { PublishedPost } from "./types";

interface UpdatePersonProfileRequest {
  displayName: string;
  handle: string;
  bio?: string;
  city?: string;
  isDiscoverable?: boolean;
  avatarPath?: string | null;
}

/** The public social identity is deliberately separate from the private `users/{uid}` account. */
export interface PersonProfileSnapshot {
  uid: string;
  displayName: string;
  handle: string;
  avatarPath: string | null;
}

export async function ensurePersonProfile(uid: string): Promise<PersonProfileSnapshot> {
  const [userSnap, profileSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("personProfiles").doc(uid).get(),
  ]);
  if (!userSnap.exists) throw new HttpsError("failed-precondition", "Kein Nutzerprofil gefunden.");
  const user = userSnap.data()!;
  const displayName = typeof user.displayName === "string" && user.displayName.trim() ? user.displayName.trim() : "Mitglied";
  const existing = profileSnap.data();
  const handle = typeof existing?.handle === "string" ? existing.handle : generatedHandle(displayName, uid);
  const now = Timestamp.now();
  const profile = {
    uid,
    displayName,
    displayNameNormalized: displayName.toLocaleLowerCase("de-DE"),
    handle,
    handleNormalized: handle,
    bio: typeof existing?.bio === "string" ? existing.bio : "",
    city: typeof existing?.city === "string" ? existing.city : "",
    cityNormalized: typeof existing?.cityNormalized === "string" ? existing.cityNormalized : "",
    // The user's private avatar never becomes public merely because a social profile exists.
    avatarPath: typeof existing?.avatarPath === "string" ? existing.avatarPath : null,
    isDiscoverable: existing?.isDiscoverable === true,
    followerCount: typeof existing?.followerCount === "number" ? existing.followerCount : 0,
    followingCount: typeof existing?.followingCount === "number" ? existing.followingCount : 0,
    linkedCoupleId: typeof user.coupleId === "string" ? user.coupleId : null,
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  };
  await db.collection("personProfiles").doc(uid).set(profile, { merge: true });
  return { uid, displayName, handle, avatarPath: typeof existing?.avatarPath === "string" ? existing.avatarPath : null };
}

/** A public person must explicitly decide to appear in search; no signup silently publishes them. */
export const updatePersonProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const body = (request.data ?? {}) as Partial<UpdatePersonProfileRequest>;
  const displayName = requireText(body.displayName, "Profilname", 40);
  const handle = normalizeHandle(body.handle);
  const bio = optionalText(body.bio, "Bio", 160);
  const city = normalizeCity(body.city);
  const requestedAvatarPath = validatePublicAvatarPath(body.avatarPath, uid);
  if (typeof body.isDiscoverable !== "boolean") {
    throw new HttpsError("invalid-argument", "Bitte wähle die Sichtbarkeit deines Profils.");
  }

  const profileRef = db.collection("personProfiles").doc(uid);
  const newHandleRef = db.collection("personProfileHandles").doc(handle);
  await db.runTransaction(async (tx) => {
    const [existing, user, reservation] = await Promise.all([
      tx.get(profileRef), tx.get(db.collection("users").doc(uid)), tx.get(newHandleRef),
    ]);
    if (!user.exists) throw new HttpsError("failed-precondition", "Kein Nutzerprofil gefunden.");
    const oldHandle = existing.data()?.handle as string | undefined;
    if (oldHandle !== handle) {
      if (reservation.exists && reservation.data()?.uid !== uid) {
        throw new HttpsError("already-exists", "Dieser Handle ist bereits vergeben.");
      }
      tx.set(newHandleRef, { uid, createdAt: Timestamp.now() });
      if (oldHandle) tx.delete(db.collection("personProfileHandles").doc(oldHandle));
    }
    const now = Timestamp.now();
    tx.set(profileRef, {
      uid,
      displayName,
      displayNameNormalized: displayName.toLocaleLowerCase("de-DE"),
      handle,
      handleNormalized: handle,
      bio,
      city,
      cityNormalized: city.toLocaleLowerCase("de-DE"),
      avatarPath: requestedAvatarPath === undefined ? existing.data()?.avatarPath ?? null : requestedAvatarPath,
      isDiscoverable: body.isDiscoverable,
      followerCount: typeof existing.data()?.followerCount === "number" ? existing.data()?.followerCount : 0,
      followingCount: typeof existing.data()?.followingCount === "number" ? existing.data()?.followingCount : 0,
      linkedCoupleId: typeof user.data()?.coupleId === "string" ? user.data()?.coupleId : null,
      createdAt: existing.data()?.createdAt ?? now,
      updatedAt: now,
    }, { merge: true });
  });

  // A post stores a small public identity snapshot so feeds can render without reading every
  // profile. Refresh that snapshot across history when somebody changes their public profile;
  // otherwise older Moments would keep showing a stale name or avatar indefinitely.
  const updatedProfile = (await profileRef.get()).data();
  if (updatedProfile) {
    await propagatePublicIdentity(uid, {
      uid,
      displayName: updatedProfile.displayName as string,
      handle: updatedProfile.handle as string,
      avatarPath: typeof updatedProfile.avatarPath === "string" ? updatedProfile.avatarPath : null,
    });
  }
  if (requestedAvatarPath === null) {
    await getStorage().bucket().file(`socialProfileImages/${uid}/avatar.jpg`).delete({ ignoreNotFound: true });
  }
  return { uid, handle, isDiscoverable: body.isDiscoverable };
});

/** Keeps denormalized social snapshots current without exposing private user records. */
async function propagatePublicIdentity(uid: string, identity: PersonProfileSnapshot): Promise<void> {
  const [createdPosts, acceptedPosts, pendingPosts, events, comments] = await Promise.all([
    db.collection("posts").where("creator.uid", "==", uid).get(),
    db.collection("posts").where("acceptedCollaboratorUids", "array-contains", uid).get(),
    db.collection("posts").where("pendingCollaboratorUids", "array-contains", uid).get(),
    db.collection("groupEvents").where("participantUids", "array-contains", uid).get(),
    db.collectionGroup("comments").where("authorUid", "==", uid).get(),
  ]);

  const postDocs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
  [...createdPosts.docs, ...acceptedPosts.docs, ...pendingPosts.docs].forEach((post) => postDocs.set(post.ref.path, post));
  const operations: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];

  postDocs.forEach((post) => {
    const data = post.data();
    const creator = data.creator?.uid === uid ? identity : data.creator;
    const collaborators = Array.isArray(data.collaborators)
      ? data.collaborators.map((person: Record<string, unknown>) => person.uid === uid ? { ...person, ...identity } : person)
      : data.collaborators;
    operations.push((batch) => batch.set(post.ref, { creator, collaborators, updatedAt: Timestamp.now() }, { merge: true }));
  });

  events.docs.forEach((event) => {
    const data = event.data();
    const creator = data.creator?.uid === uid ? identity : data.creator;
    const participants = Array.isArray(data.participants)
      ? data.participants.map((person: Record<string, unknown>) => person.uid === uid ? { ...person, ...identity } : person)
      : data.participants;
    operations.push((batch) => batch.set(event.ref, { creator, participants, updatedAt: Timestamp.now() }, { merge: true }));
  });

  comments.docs.forEach((comment) => {
    operations.push((batch) => batch.set(comment.ref, { author: identity }, { merge: true }));
  });

  for (let index = 0; index < operations.length; index += 450) {
    const batch = db.batch();
    operations.slice(index, index + 450).forEach((write) => write(batch));
    await batch.commit();
  }

  // Followers read materialized feed cards. Refresh those cards too, after the source post
  // snapshots have been committed, so avatar updates feel immediate in every surface.
  for (const post of postDocs.values()) {
    const refreshed = await post.ref.get();
    const data = refreshed.data();
    if (data?.status === "published") {
      await syncPostToFollowerFeeds({ id: post.id, ...data } as PublishedPost);
    }
  }
}

function generatedHandle(displayName: string, uid: string): string {
  const stem = displayName.toLocaleLowerCase("de-DE")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "").slice(0, 15) || "mitglied";
  return `${stem}_${uid.slice(0, 6).toLowerCase()}`;
}

/** Public images have a dedicated path; private personal avatars can never be promoted by text. */
function validatePublicAvatarPath(value: unknown, uid: string): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const expected = `socialProfileImages/${uid}/avatar.jpg`;
  if (value !== expected) throw new HttpsError("invalid-argument", "Ungültiges Community-Profilbild.");
  return value;
}
