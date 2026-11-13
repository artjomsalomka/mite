import type { Timestamp } from "firebase-admin/firestore";

export type PostVisibility = "private" | "followers" | "public";
export type PostStatus = "draft" | "published";
export type ReactionKind = "like" | "save";

export interface ProfileSnapshot {
  coupleId: string;
  displayName: string;
  handle: string;
  avatarPath: string | null;
}

export interface PersonProfileSnapshot {
  uid: string;
  displayName: string;
  handle: string;
  avatarPath: string | null;
}

export interface PostCollaborator extends PersonProfileSnapshot {
  status: "pending" | "accepted" | "declined";
}

export type PostMediaKind = "image" | "video";

/** Ordered media keeps a post carousel faithful to the order chosen in the composer. Videos
 * always have a safe still image for lightweight feed cards. */
export interface PostMediaReference {
  path: string;
  kind: PostMediaKind;
  thumbnailPath?: string | null;
}

/** A source-backed image reserved for curated/demo content. Member uploads continue to use
 * authenticated Storage paths and never need third-party attribution metadata. */
export interface LicensedImageReference {
  url: string;
  sourcePageURL: string;
  creator: string;
  license: string;
  licenseURL: string | null;
}

export interface PublishedPost {
  id: string;
  ownerCoupleId: string;
  ownerUid?: string;
  status: "published";
  visibility: PostVisibility;
  author: ProfileSnapshot;
  creator?: PersonProfileSnapshot;
  collaborators?: PostCollaborator[];
  pendingCollaboratorUids?: string[];
  acceptedCollaboratorUids?: string[];
  caption: string;
  city: string;
  cityNormalized: string;
  categories: string[];
  imagePaths: string[];
  media?: PostMediaReference[];
  licensedImages?: LicensedImageReference[];
  sourceDateId: string | null;
  sourceEventId?: string | null;
  createdAt: Timestamp;
  publishedAt: Timestamp;
  updatedAt: Timestamp;
  likesCount: number;
  savesCount: number;
  commentsCount?: number;
}

export interface FeedItem {
  postId: string;
  ownerCoupleId: string;
  visibility: PostVisibility;
  author: ProfileSnapshot;
  creator?: PersonProfileSnapshot;
  collaborators?: PostCollaborator[];
  caption: string;
  city: string;
  cityNormalized: string;
  categories: string[];
  coverImagePath: string | null;
  coverLicensedImage?: LicensedImageReference | null;
  imageCount: number;
  likesCount: number;
  savesCount: number;
  commentsCount?: number;
  publishedAt: Timestamp;
}
