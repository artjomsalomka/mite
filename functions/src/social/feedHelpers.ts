import { Timestamp, WriteBatch } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import type { FeedItem, PublishedPost } from "./types";

function feedItem(post: PublishedPost): FeedItem {
  return {
    postId: post.id,
    ownerCoupleId: post.ownerCoupleId,
    visibility: post.visibility,
    author: post.author,
    creator: post.creator,
    collaborators: post.collaborators,
    caption: post.caption,
    city: post.city,
    cityNormalized: post.cityNormalized,
    categories: post.categories,
    coverImagePath: post.media?.[0]?.thumbnailPath ?? post.media?.[0]?.path ?? post.imagePaths[0] ?? null,
    coverLicensedImage: post.licensedImages?.[0] ?? null,
    imageCount: post.media?.length ?? post.imagePaths.length,
    likesCount: post.likesCount,
    savesCount: post.savesCount,
    commentsCount: post.commentsCount ?? 0,
    publishedAt: post.publishedAt,
  };
}

/** Materializes the caller-safe following feed. Private posts are never copied. */
export async function syncPostToFollowerFeeds(post: PublishedPost): Promise<void> {
  const followers = await db.collection("follows")
    .where("targetCoupleId", "==", post.ownerCoupleId)
    .get();

  await commitInBatches(followers.docs, (batch, follower) => {
    const followerCoupleId = follower.data().followerCoupleId as string;
    const itemRef = db.collection("couples").doc(followerCoupleId).collection("feedItems").doc(post.id);
    if (post.visibility === "private") {
      batch.delete(itemRef);
    } else {
      batch.set(itemRef, feedItem(post));
    }
  });
}

export async function removePostFromFollowerFeeds(postId: string, ownerCoupleId: string): Promise<void> {
  const followers = await db.collection("follows")
    .where("targetCoupleId", "==", ownerCoupleId)
    .get();

  await commitInBatches(followers.docs, (batch, follower) => {
    const followerCoupleId = follower.data().followerCoupleId as string;
    batch.delete(db.collection("couples").doc(followerCoupleId).collection("feedItems").doc(postId));
  });
}

export async function backfillFollowingFeed(followerCoupleId: string, targetCoupleId: string): Promise<void> {
  const recentPosts = await db.collection("posts")
    .where("ownerCoupleId", "==", targetCoupleId)
    .where("status", "==", "published")
    .orderBy("publishedAt", "desc")
    .limit(20)
    .get();

  const postDocs = recentPosts.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }) as PublishedPost)
    .filter((post) => post.visibility !== "private");

  await commitInBatches(postDocs, (batch, post) => {
    batch.set(
      db.collection("couples").doc(followerCoupleId).collection("feedItems").doc(post.id),
      feedItem(post)
    );
  });
}

export async function removeFollowingFeedItems(followerCoupleId: string, targetCoupleId: string): Promise<void> {
  const items = await db.collection("couples").doc(followerCoupleId).collection("feedItems")
    .where("ownerCoupleId", "==", targetCoupleId)
    .get();
  await commitInBatches(items.docs, (batch, item) => batch.delete(item.ref));
}

/** Firestore commits accept max. 500 writes; this also keeps profile growth safe after MVP. */
async function commitInBatches<T>(items: T[], write: (batch: WriteBatch, item: T) => void): Promise<void> {
  for (let index = 0; index < items.length; index += 450) {
    const batch = db.batch();
    items.slice(index, index + 450).forEach((item) => write(batch, item));
    if (index < items.length) {
      await batch.commit();
    }
  }
}

/** A shared timestamp helper avoids synthetic Date values in Firestore-facing structures. */
export function now(): Timestamp {
  return Timestamp.now();
}
