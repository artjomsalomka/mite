/* eslint-disable no-console */
// Covers the release checklist's still-open gate: "Moment mit mehreren Bildern und Video
// veröffentlichen, kommentieren, melden und löschen." smokePersonalSocial.js already exercises a
// single-image-less post plus like/save/comment/delete-comment/delete-post for one account; this
// script is the complementary case it deliberately leaves out — a post carrying several images
// and a video (the actual `media` contract in posts.ts, not just the legacy `imagePaths` shape),
// commented on and reported by a *second* account, then deleted by its author.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");

const { functionBase } = require("./localSmokeEnvironment").configureLocalSmokeEnvironment();

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore();
const adminAuth = getAuth();

async function callable(name, token, data = {}) {
  const response = await fetch(`${functionBase}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(20_000),
  });
  const body = await response.json();
  if (!response.ok || body.error) throw new Error(`${name}: ${JSON.stringify(body.error || body)}`);
  return body.result ?? body.data;
}

async function expectCallableFailure(name, token, data, messageFragment) {
  const response = await fetch(`${functionBase}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(20_000),
  });
  const body = await response.json();
  assert.ok(body.error, `${name} was expected to fail but returned ${JSON.stringify(body)}`);
  if (messageFragment) {
    assert.ok(
      String(body.error.message ?? "").includes(messageFragment),
      `${name} error "${body.error.message}" did not mention "${messageFragment}"`,
    );
  }
}

async function signUpPerson(marker, label) {
  const email = `post-media-${marker}-${label}@example.test`;
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password: `Smoke-${marker}!`, returnSecureToken: true }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  const body = await response.json();
  if (!response.ok) throw new Error(`signup ${label}: ${JSON.stringify(body)}`);
  const uid = body.localId;
  await db.collection("users").doc(uid).set({
    displayName: `Mite Smoke ${label}`,
    email,
    authProvider: "password",
    dietaryDefault: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await callable("updatePersonProfile", body.idToken, {
    displayName: `Mite Smoke ${label}`,
    handle: `pm_${marker}_${label}`,
    bio: "Automatischer lokaler Test",
    city: "Marburg",
    isDiscoverable: true,
    avatarPath: null,
  });
  return { uid, idToken: body.idToken };
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const author = await signUpPerson(marker, "author");
  const viewer = await signUpPerson(marker, "viewer");
  let postId;

  try {
    const draft = await callable("createPostDraft", author.idToken, {
      sourceDateId: null,
      sourceEventId: null,
      collaboratorUids: [],
    });
    postId = draft.postId;
    assert.ok(postId);

    // Three images plus one video — the actual multi-media carousel shape, not the legacy
    // single-array-of-jpgs fallback. Files are never actually uploaded to Storage: publishPost
    // only validates path *shape* (owner/post-scoped prefix, extension, thumbnail pairing), so a
    // well-formed path is sufficient to exercise that contract without a real binary.
    const imagePaths = [1, 2, 3].map((n) => `postImages/${author.uid}/${postId}/photo-${n}.jpg`);
    const videoPath = `postVideos/${author.uid}/${postId}/clip.mp4`;
    const posterPath = `postImages/${author.uid}/${postId}/clip-poster.jpg`;
    const media = [
      ...imagePaths.map((path) => ({ path, kind: "image" })),
      { path: videoPath, kind: "video", thumbnailPath: posterPath },
    ];

    // A video path outside the post's own scoped prefix must be rejected before anything else —
    // this is the one guard that only a real video entry (never plain imagePaths) exercises.
    await expectCallableFailure("publishPost", author.idToken, {
      postId,
      caption: "Sollte scheitern",
      visibility: "public",
      city: "Marburg",
      categories: [],
      imagePaths,
      media: [...media.slice(0, 3), { path: `postVideos/${viewer.uid}/${postId}/clip.mp4`, kind: "video", thumbnailPath: posterPath }],
    }, "Videopfad");

    const published = await callable("publishPost", author.idToken, {
      postId,
      caption: "Mehrere Fotos und ein Video vom Wochenende",
      visibility: "public",
      city: "Marburg",
      categories: ["Aktiv"],
      imagePaths,
      media,
    });
    assert.equal(published.status, "published");

    const stored = (await db.collection("posts").doc(postId).get()).data();
    assert.equal(stored.media.length, 4, "expected 3 images + 1 video in the stored media list");
    assert.equal(stored.media.filter((item) => item.kind === "video").length, 1);
    assert.equal(stored.media.find((item) => item.kind === "video").thumbnailPath, posterPath);

    const comment = await callable("addPostComment", viewer.idToken, { postId, body: "Schöne Bilder!" });
    assert.ok(comment.commentId);

    // "melden" — a second account reports the published post itself, not just its author profile.
    await callable("reportSocialProfile", viewer.idToken, {
      targetUid: author.uid,
      reason: "other",
      note: "Automatischer lokaler Test",
      postId,
    });
    const reports = await db.collection("socialReports").where("postId", "==", postId).get();
    assert.equal(reports.size, 1);
    assert.equal(reports.docs[0].data().contentType, "post");

    // Reporting as the post's own author must not be possible (the target would equal the caller).
    await expectCallableFailure("reportSocialProfile", author.idToken, { targetUid: author.uid, postId }, "Ungültiges Profil");

    await callable("deletePostComment", author.idToken, { postId, commentId: comment.commentId });
    await callable("deletePost", author.idToken, { postId });
    const afterDelete = await db.collection("posts").doc(postId).get();
    assert.equal(afterDelete.exists, false);
    postId = undefined;

    console.log("Multi-image/video post lifecycle smoke test passed.");
  } finally {
    if (postId) await db.recursiveDelete(db.collection("posts").doc(postId)).catch(() => {});
    for (const person of [author, viewer]) {
      await db.recursiveDelete(db.collection("users").doc(person.uid)).catch(() => {});
      await db.collection("personProfiles").doc(person.uid).delete().catch(() => {});
      await adminAuth.deleteUser(person.uid).catch(() => {});
    }
    await db.collection("socialReports").where("targetUid", "==", author.uid).get()
      .then((snap) => Promise.all(snap.docs.map((doc) => doc.ref.delete())));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
