/* eslint-disable no-console */
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

async function signUp(email, password) {
  const response = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  const body = await response.json();
  if (!response.ok) throw new Error(`signup: ${JSON.stringify(body)}`);
  return body;
}

async function main() {
  const marker = randomUUID().slice(0, 8);
  const email = `social-smoke-${marker}@example.test`;
  const authUser = await signUp(email, `Smoke-${marker}!`);
  const uid = authUser.localId;
  let postId;

  try {
    await db.collection("users").doc(uid).set({
      displayName: "Mite Smoke",
      email,
      authProvider: "password",
      dietaryDefault: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await callable("updatePersonProfile", authUser.idToken, {
      displayName: "Mite Smoke",
      handle: `smoke_${marker}`,
      bio: "Automatischer lokaler Test",
      city: "Marburg",
      isDiscoverable: true,
      avatarPath: null,
    });

    const draft = await callable("createPostDraft", authUser.idToken, {
      sourceDateId: null,
      sourceEventId: null,
      collaboratorUids: [],
    });
    postId = draft.postId;
    assert.ok(postId);

    await callable("publishPost", authUser.idToken, {
      postId,
      caption: "Lokaler persönlicher Social-Smoke-Test",
      visibility: "public",
      city: "Marburg",
      categories: ["Entspannt"],
      imagePaths: [],
      media: [],
    });

    assert.equal((await callable("togglePostReaction", authUser.idToken, { postId, kind: "like" })).isActive, true);
    assert.equal((await callable("togglePostReaction", authUser.idToken, { postId, kind: "save" })).isActive, true);
    const saved = await callable("getSavedPostIds", authUser.idToken);
    assert.deepEqual(saved.postIds, [postId]);

    const comment = await callable("addPostComment", authUser.idToken, { postId, body: "Funktioniert." });
    assert.ok(comment.commentId);
    await callable("deletePostComment", authUser.idToken, { postId, commentId: comment.commentId });

    await callable("deletePost", authUser.idToken, { postId });
    postId = undefined;
    await callable("deleteOwnAccount", authUser.idToken);
    console.log("Personal social smoke test passed.");
  } catch (error) {
    if (postId) await db.recursiveDelete(db.collection("posts").doc(postId)).catch(() => {});
    await db.recursiveDelete(db.collection("users").doc(uid)).catch(() => {});
    await db.collection("personProfiles").doc(uid).delete().catch(() => {});
    await adminAuth.deleteUser(uid).catch(() => {});
    throw error;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
