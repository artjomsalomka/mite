import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { sendGenericPush } from "../pushNotifications";
import { matchId, optionalText, relationshipId, requireSingleProfile, SingleProfileData, suggestion } from "./singleHelpers";
import { isMutuallyCompatible } from "./matchingCompatibility";

interface InterestRequest { targetUid: string; }
interface BlockRequest { targetUid: string; }
interface ReportRequest { targetUid: string; reason: "spam" | "inappropriate" | "safety" | "other"; details?: string; }

export const getSingleSuggestions = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const ownProfile = await requireSingleProfile(uid);
  if (!ownProfile.isMatchingActive) return { suggestions: [] };

  // This small-MVP scan keeps the first release index-free. At scale this becomes a city and
  // preference-indexed candidate service; the block/interest checks remain server-side either way.
  const candidates = await db.collection("singleProfiles").where("isMatchingActive", "==", true).limit(50).get();
  const visible = await Promise.all(candidates.docs.map(async (candidateDoc) => {
    if (candidateDoc.id === uid) return null;
    const candidate = candidateDoc.data() as SingleProfileData;
    if (!isMutuallyCompatible(ownProfile, candidate)) return null;

    const [outgoing, incoming, blockedBySelf, blockedByCandidate] = await Promise.all([
      db.collection("singleInterests").doc(relationshipId(uid, candidate.uid)).get(),
      db.collection("singleInterests").doc(relationshipId(candidate.uid, uid)).get(),
      db.collection("singleBlocks").doc(relationshipId(uid, candidate.uid)).get(),
      db.collection("singleBlocks").doc(relationshipId(candidate.uid, uid)).get(),
    ]);
    if (outgoing.exists || incoming.exists || blockedBySelf.exists || blockedByCandidate.exists) return null;

    const commonInterestCount = candidate.interests.filter((interest) => ownProfile.interests.includes(interest)).length;
    return suggestion(candidate, commonInterestCount);
  }));

  return {
    suggestions: visible
      .filter((item): item is NonNullable<typeof item> => item !== null)
      .sort((left, right) => right.commonInterestCount - left.commonInterestCount || left.displayName.localeCompare(right.displayName, "de"))
      .slice(0, 20),
  };
});

export const expressSingleInterest = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  await requireSingleProfile(uid);
  const { targetUid } = (request.data ?? {}) as Partial<InterestRequest>;
  if (!targetUid || typeof targetUid !== "string" || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Ungültiges Profil.");
  }

  const ownProfileRef = db.collection("singleProfiles").doc(uid);
  const targetProfileRef = db.collection("singleProfiles").doc(targetUid);
  const outgoingRef = db.collection("singleInterests").doc(relationshipId(uid, targetUid));
  const incomingRef = db.collection("singleInterests").doc(relationshipId(targetUid, uid));
  const blockedBySelfRef = db.collection("singleBlocks").doc(relationshipId(uid, targetUid));
  const blockedByTargetRef = db.collection("singleBlocks").doc(relationshipId(targetUid, uid));
  const singleMatchId = matchId(uid, targetUid);
  const matchRef = db.collection("singleMatches").doc(singleMatchId);
  const result = await db.runTransaction(async (transaction) => {
    const [ownProfile, targetProfile, outgoing, incoming, blockedBySelf, blockedByTarget, existingMatch] = await Promise.all([
      transaction.get(ownProfileRef),
      transaction.get(targetProfileRef),
      transaction.get(outgoingRef),
      transaction.get(incomingRef),
      transaction.get(blockedBySelfRef),
      transaction.get(blockedByTargetRef),
      transaction.get(matchRef),
    ]);
    const own = ownProfile.data() as SingleProfileData | undefined;
    const target = targetProfile.data() as SingleProfileData | undefined;
    if (!ownProfile.exists || !targetProfile.exists || !own?.isMatchingActive || !target?.isMatchingActive || !isMutuallyCompatible(own, target)) {
      throw new HttpsError("not-found", "Dieses Profil ist nicht verfügbar.");
    }
    if (blockedBySelf.exists || blockedByTarget.exists) {
      throw new HttpsError("permission-denied", "Dieses Profil ist nicht verfügbar.");
    }
    if (existingMatch.exists || outgoing.data()?.status === "matched") {
      return { status: "matched", matchId: singleMatchId, createdNewMatch: false };
    }
    if (outgoing.exists) {
      return { status: "sent", matchId: null, createdNewMatch: false };
    }

    const now = Timestamp.now();
    if (incoming.exists) {
      transaction.set(outgoingRef, { fromUid: uid, toUid: targetUid, status: "matched", createdAt: now, updatedAt: now });
      transaction.update(incomingRef, { status: "matched", updatedAt: now });
      transaction.set(matchRef, {
        memberUids: [uid, targetUid].sort(),
        status: "matched",
        readAtByUid: { [uid]: now, [targetUid]: now },
        createdAt: now,
        updatedAt: now,
      });
      return { status: "matched", matchId: singleMatchId, createdNewMatch: true };
    }

    transaction.set(outgoingRef, { fromUid: uid, toUid: targetUid, status: "sent", createdAt: now, updatedAt: now });
    return { status: "sent", matchId: null, createdNewMatch: false };
  });
  if (result.createdNewMatch) {
    void sendGenericPush([targetUid], {
      title: "Neues Match",
      body: "Jemand möchte mit dir ein Date planen.",
      data: { type: "single_match", matchId: singleMatchId },
    }).catch((error) => console.warn("Push notification for new match failed.", error));
  }
  return { status: result.status, matchId: result.matchId };
});

export const getSingleMatches = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  await requireSingleProfile(uid);
  const matches = await db.collection("singleMatches").where("memberUids", "array-contains", uid).get();
  const previews = await Promise.all(matches.docs.map(async (match) => {
    const memberUids = (match.data().memberUids ?? []) as string[];
    const otherUid = memberUids.find((memberUid) => memberUid !== uid);
    if (!otherUid) return null;
    const [profile, blockedBySelf, blockedByOther] = await Promise.all([
      db.collection("singleProfiles").doc(otherUid).get(),
      db.collection("singleBlocks").doc(relationshipId(uid, otherUid)).get(),
      db.collection("singleBlocks").doc(relationshipId(otherUid, uid)).get(),
    ]);
    if (!profile.exists || blockedBySelf.exists || blockedByOther.exists) return null;
    const profileData = profile.data() as SingleProfileData;
    const createdAt = match.data().createdAt as Timestamp | undefined;
    const lastMessageAt = match.data().lastMessageAt as Timestamp | undefined;
    const readAt = match.data().readAtByUid?.[uid] as Timestamp | undefined;
    const lastMessageSenderUid = match.data().lastMessageSenderUid as string | undefined;
    return {
      matchId: match.id,
      profile: suggestion(profileData, 0),
      matchedAtMilliseconds: createdAt?.toMillis() ?? 0,
      lastActivityAtMilliseconds: lastMessageAt?.toMillis() ?? createdAt?.toMillis() ?? 0,
      hasUnreadMessage: Boolean(
        lastMessageAt
        && lastMessageSenderUid !== uid
        && lastMessageAt.toMillis() > (readAt?.toMillis() ?? 0),
      ),
    };
  }));
  return {
    matches: previews
      .filter((item): item is NonNullable<typeof item> => item !== null)
      .sort((left, right) => right.lastActivityAtMilliseconds - left.lastActivityAtMilliseconds),
  };
});

export const blockSingle = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  await requireSingleProfile(uid);
  const { targetUid } = (request.data ?? {}) as Partial<BlockRequest>;
  if (!targetUid || typeof targetUid !== "string" || targetUid === uid) {
    throw new HttpsError("invalid-argument", "Ungültiges Profil.");
  }
  const now = Timestamp.now();
  const batch = db.batch();
  batch.set(db.collection("singleBlocks").doc(relationshipId(uid, targetUid)), { blockerUid: uid, targetUid, createdAt: now });
  batch.delete(db.collection("singleInterests").doc(relationshipId(uid, targetUid)));
  batch.delete(db.collection("singleInterests").doc(relationshipId(targetUid, uid)));
  batch.delete(db.collection("singleMatches").doc(matchId(uid, targetUid)));
  await batch.commit();
  return { isBlocked: true };
});

export const reportSingle = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  await requireSingleProfile(uid);
  const { targetUid, reason, details } = (request.data ?? {}) as Partial<ReportRequest>;
  if (!targetUid || typeof targetUid !== "string" || targetUid === uid || !["spam", "inappropriate", "safety", "other"].includes(reason ?? "")) {
    throw new HttpsError("invalid-argument", "Ungültige Meldung.");
  }
  await db.collection("singleReports").add({
    reporterUid: uid,
    targetUid,
    reason,
    details: optionalText(details, "Details", 500),
    createdAt: Timestamp.now(),
  });
  return { reported: true };
});
