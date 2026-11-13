import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { db } from "../firebaseAdmin";
import { removePostFromFollowerFeeds, syncPostToFollowerFeeds } from "./feedHelpers";
import { normalizeCategories, normalizeCity, optionalActiveCouple, optionalText } from "./socialHelpers";
import { ensurePersonProfile } from "./personProfiles";
import { consumeSocialWriteQuota } from "./socialWriteRateLimit";
import type { PersonProfileSnapshot, PostCollaborator, PostMediaReference, PostStatus, PostVisibility, ProfileSnapshot, PublishedPost } from "./types";

interface CreatePostDraftRequest {
  sourceDateId?: string | null;
  sourceEventId?: string | null;
  collaboratorUids?: string[];
}

interface PublishPostRequest {
  postId: string;
  caption?: string;
  visibility: PostVisibility;
  city?: string;
  categories?: string[];
  imagePaths?: string[];
  media?: PostMediaReference[];
}

interface DeletePostRequest {
  postId: string;
}

/** Creates a private shell first, so image upload paths are scoped to a real, owned post id. */
export const createPostDraft = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const couple = await optionalActiveCouple(request.auth.uid);
  const ownerId = couple?.coupleId ?? request.auth.uid;
  const { sourceDateId, sourceEventId, collaboratorUids } = (request.data ?? {}) as CreatePostDraftRequest;
  await consumeSocialWriteQuota(
    db.collection("users").doc(request.auth.uid).collection("socialRateLimits").doc("postDrafts"),
  );

  if (sourceDateId !== undefined && sourceDateId !== null) {
    if (typeof sourceDateId !== "string" || sourceDateId.length === 0) {
      throw new HttpsError("invalid-argument", "Ungültige Date-ID.");
    }
    if (!couple) {
      throw new HttpsError("failed-precondition", "Persönliche Momente können derzeit nur mit einem Gruppenplan verknüpft werden.");
    }
    const savedDate = await db.collection("couples").doc(couple.coupleId).collection("savedDates").doc(sourceDateId).get();
    if (!savedDate.exists) {
      throw new HttpsError("not-found", "Das ausgewählte Date wurde nicht gefunden.");
    }
  }

  let eventParticipantUids: string[] | undefined;
  if (sourceEventId !== undefined && sourceEventId !== null) {
    if (typeof sourceEventId !== "string" || sourceEventId.length === 0) {
      throw new HttpsError("invalid-argument", "Ungültige Plan-ID.");
    }
    const event = await db.collection("groupEvents").doc(sourceEventId).get();
    const eventData = event.data();
    if (!event.exists || eventData?.creatorUid !== request.auth.uid || eventData.status !== "planned") {
      throw new HttpsError("permission-denied", "Dieser Gruppenplan kann nicht geteilt werden.");
    }
    const scheduledAt = eventData.scheduledAt as Timestamp | undefined;
    if (!scheduledAt || scheduledAt.toMillis() > Date.now()) {
      throw new HttpsError("failed-precondition", "Ein Moment kann erst nach dem gemeinsamen Plan geteilt werden.");
    }
    eventParticipantUids = ((eventData.participants ?? []) as Array<{ uid?: string; status?: string }>)
      .filter((person) => person.status === "going" && typeof person.uid === "string")
      .map((person) => person.uid!);
  }

  const [creator, collaborators] = await Promise.all([
    ensurePersonProfile(request.auth.uid),
    collaboratorSnapshots(collaboratorUids, request.auth.uid),
  ]);
  const profile = couple
    ? await getProfileSnapshot(couple.coupleId)
    : personalProfileSnapshot(creator);
  if (eventParticipantUids && collaborators.some((person) => !eventParticipantUids!.includes(person.uid))) {
    throw new HttpsError("invalid-argument", "Nur bestätigte Teilnehmende dieses Plans können eingeladen werden.");
  }
  const postRef = db.collection("posts").doc();
  const createdAt = Timestamp.now();
  await postRef.set({
    ownerCoupleId: ownerId,
    ownerUid: request.auth.uid,
    status: "draft" satisfies PostStatus,
    visibility: "private" satisfies PostVisibility,
    author: profile,
    creator,
    collaborators,
    pendingCollaboratorUids: collaborators.map((item) => item.uid),
    acceptedCollaboratorUids: [],
    caption: "",
    city: "",
    cityNormalized: "",
    categories: [],
    imagePaths: [],
    media: [],
    sourceDateId: sourceDateId ?? null,
    sourceEventId: sourceEventId ?? null,
    createdAt,
    publishedAt: null,
    updatedAt: createdAt,
    likesCount: 0,
    savesCount: 0,
    commentsCount: 0,
  });

  return { postId: postRef.id };
});

/** Publishes (or updates) a post only after the client has finished authenticated image uploads. */
export const publishPost = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const couple = await optionalActiveCouple(request.auth.uid);
  const body = (request.data ?? {}) as Partial<PublishPostRequest>;
  if (!body.postId || typeof body.postId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Post.");
  }
  if (!isVisibility(body.visibility)) {
    throw new HttpsError("invalid-argument", "Ungültige Sichtbarkeit.");
  }

  const postRef = db.collection("posts").doc(body.postId);
  const postSnap = await postRef.get();
  const oldData = postSnap.data();
  const ownsPersonally = oldData?.ownerUid === request.auth.uid && oldData?.ownerCoupleId === request.auth.uid;
  const ownsAsCouple = Boolean(couple && oldData?.ownerCoupleId === couple.coupleId);
  if (!postSnap.exists || (!ownsPersonally && !ownsAsCouple)) {
    throw new HttpsError("permission-denied", "Du kannst diesen Post nicht bearbeiten.");
  }

  const ownerId = oldData!.ownerCoupleId as string;

  const caption = optionalText(body.caption, "Text", 500);
  const city = normalizeCity(body.city);
  const categories = normalizeCategories(body.categories);
  const imagePaths = validateImagePaths(body.imagePaths, ownerId, body.postId);
  const media = validateMedia(body.media, imagePaths, ownerId, body.postId);
  const postData = oldData!;
  const creator = (postData.creator as PersonProfileSnapshot | undefined) ?? await ensurePersonProfile(request.auth.uid);
  const profile = ownerId === request.auth.uid
    ? personalProfileSnapshot(creator)
    : await getProfileSnapshot(ownerId);
  const publishedAt = postData.publishedAt ?? Timestamp.now();

  const post: PublishedPost = {
    id: postRef.id,
    ownerCoupleId: ownerId,
    ownerUid: typeof postData.ownerUid === "string" ? postData.ownerUid : request.auth.uid,
    status: "published",
    visibility: body.visibility,
    author: profile,
    creator: postData.creator as PersonProfileSnapshot | undefined,
    collaborators: postData.collaborators as PostCollaborator[] | undefined,
    pendingCollaboratorUids: postData.pendingCollaboratorUids as string[] | undefined,
    acceptedCollaboratorUids: postData.acceptedCollaboratorUids as string[] | undefined,
    caption,
    city,
    cityNormalized: city.toLocaleLowerCase("de-DE"),
    categories,
    imagePaths,
    media,
    sourceDateId: (postData.sourceDateId as string | null | undefined) ?? null,
    sourceEventId: (postData.sourceEventId as string | null | undefined) ?? null,
    createdAt: postData.createdAt as Timestamp,
    publishedAt,
    updatedAt: Timestamp.now(),
    likesCount: (postData.likesCount as number | undefined) ?? 0,
    savesCount: (postData.savesCount as number | undefined) ?? 0,
    commentsCount: (postData.commentsCount as number | undefined) ?? 0,
  };

  await postRef.set(post, { merge: true });
  await syncPostToFollowerFeeds(post);
  return { postId: post.id, status: post.status };
});

/** Deletes the Firestore post, fan-out entries, reactions, and authenticated Storage assets. */
export const deletePost = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const couple = await optionalActiveCouple(request.auth.uid);
  const { postId } = (request.data ?? {}) as Partial<DeletePostRequest>;
  if (!postId || typeof postId !== "string") {
    throw new HttpsError("invalid-argument", "Ungültiger Post.");
  }

  const postRef = db.collection("posts").doc(postId);
  const postSnap = await postRef.get();
  const postData = postSnap.data();
  const ownsPersonally = postData?.ownerUid === request.auth.uid && postData?.ownerCoupleId === request.auth.uid;
  const ownsAsCouple = Boolean(couple && postData?.ownerCoupleId === couple.coupleId);
  if (!postSnap.exists || (!ownsPersonally && !ownsAsCouple)) {
    throw new HttpsError("permission-denied", "Du kannst diesen Post nicht löschen.");
  }

  const ownerId = postData!.ownerCoupleId as string;

  await removePostFromFollowerFeeds(postId, ownerId);
  await db.recursiveDelete(postRef);
  // Uploads happen while a post is still a draft. Delete the complete scoped prefix rather than
  // only `imagePaths`, so a cancelled/failed publish cannot leave an unreferenced private photo.
  await Promise.all([
    getStorage().bucket().deleteFiles({ prefix: `postImages/${ownerId}/${postId}/` }),
    getStorage().bucket().deleteFiles({ prefix: `postVideos/${ownerId}/${postId}/` }),
  ]);

  return { postId };
});

async function getProfileSnapshot(coupleId: string): Promise<ProfileSnapshot> {
  const profile = await db.collection("coupleProfiles").doc(coupleId).get();
  if (!profile.exists) {
    throw new HttpsError("failed-precondition", "Bitte richtet zuerst euer Paar-Profil ein.");
  }
  const data = profile.data()!;
  return {
    coupleId,
    displayName: data.displayName as string,
    handle: data.handle as string,
    avatarPath: (data.avatarPath as string | null | undefined) ?? null,
  };
}

function personalProfileSnapshot(profile: PersonProfileSnapshot): ProfileSnapshot {
  return {
    coupleId: profile.uid,
    displayName: profile.displayName,
    handle: profile.handle,
    avatarPath: profile.avatarPath,
  };
}

async function collaboratorSnapshots(value: unknown, creatorUid: string): Promise<PostCollaborator[]> {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > 5 || !value.every((uid) => typeof uid === "string" && uid.length > 0)) {
    throw new HttpsError("invalid-argument", "Du kannst höchstens fünf Mitwirkende einladen.");
  }
  const unique = [...new Set(value as string[])].filter((uid) => uid !== creatorUid);
  const profiles = await Promise.all(unique.map((uid) => ensurePersonProfile(uid).catch(() => null)));
  if (profiles.some((profile) => profile === null)) {
    throw new HttpsError("not-found", "Mindestens ein ausgewähltes Profil existiert nicht.");
  }
  return profiles.map((profile) => ({ ...profile!, status: "pending" }));
}

function isVisibility(value: unknown): value is PostVisibility {
  return value === "private" || value === "followers" || value === "public";
}

function validateImagePaths(value: unknown, coupleId: string, postId: string): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > 8 || !value.every((path) => typeof path === "string")) {
    throw new HttpsError("invalid-argument", "Ein Post darf höchstens acht Fotos enthalten.");
  }
  const prefix = `postImages/${coupleId}/${postId}/`;
  const unique = [...new Set(value)];
  if (unique.some((path) => !path.startsWith(prefix) || !/\.jpg$/i.test(path))) {
    throw new HttpsError("invalid-argument", "Ungültiger Bildpfad.");
  }
  return unique;
}

function validateMedia(value: unknown, imagePaths: string[], coupleId: string, postId: string): PostMediaReference[] {
  // Older app versions publish only imagePaths. Turn those paths into the new media shape so
  // all readers get a predictable, ordered carousel during the transition.
  if (value === undefined || value === null) {
    return imagePaths.map((path) => ({ path, kind: "image" }));
  }
  if (!Array.isArray(value) || value.length > 8) {
    throw new HttpsError("invalid-argument", "Ein Post darf höchstens acht Medien enthalten.");
  }

  const imagePrefix = `postImages/${coupleId}/${postId}/`;
  const videoPrefix = `postVideos/${coupleId}/${postId}/`;
  const media = value.map((entry): PostMediaReference => {
    if (!entry || typeof entry !== "object") {
      throw new HttpsError("invalid-argument", "Ungültiges Medium.");
    }
    const item = entry as Record<string, unknown>;
    const path = item.path;
    const kind = item.kind;
    const thumbnailPath = item.thumbnailPath;
    if (typeof path !== "string" || (kind !== "image" && kind !== "video")) {
      throw new HttpsError("invalid-argument", "Ungültiges Medium.");
    }
    if (kind === "image") {
      if (!path.startsWith(imagePrefix) || !/\.jpg$/i.test(path) || thumbnailPath !== null && thumbnailPath !== undefined) {
        throw new HttpsError("invalid-argument", "Ungültiger Bildpfad.");
      }
      return { path, kind };
    }
    if (!path.startsWith(videoPrefix) || !/\.(mp4|mov|m4v)$/i.test(path) || typeof thumbnailPath !== "string"
      || !thumbnailPath.startsWith(imagePrefix) || !/-poster\.jpg$/i.test(thumbnailPath)) {
      throw new HttpsError("invalid-argument", "Ungültiger Videopfad.");
    }
    return { path, kind, thumbnailPath };
  });

  const uniquePaths = new Set(media.map((item) => item.path));
  if (uniquePaths.size !== media.length) {
    throw new HttpsError("invalid-argument", "Ein Medium wurde mehrfach übergeben.");
  }
  const declaredImages = media.filter((item) => item.kind === "image").map((item) => item.path);
  if (declaredImages.length !== imagePaths.length || declaredImages.some((path) => !imagePaths.includes(path))) {
    throw new HttpsError("invalid-argument", "Bild- und Medienliste passen nicht zusammen.");
  }
  return media;
}
