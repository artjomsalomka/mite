import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { HttpsError } from "firebase-functions/v2/https";

// Generated visuals are paid calls. A user may compare a few routes, but cannot turn
// repeatedly opening suggestion details into an unbounded image-generation workload.
const windowMilliseconds = 10 * 60_000;
const maximumNewImagesPerWindow = 12;
const minimumIntervalMilliseconds = 2_000;

interface StoredImageRateLimit {
  windowStartedAt: Timestamp;
  lastRequestedAt: Timestamp;
  generatedImagesInWindow: number;
}

export async function reserveImageGenerationSlots(uid: string, requestedImages: number): Promise<void> {
  if (requestedImages === 0) return;
  const reference = db.collection("users").doc(uid).collection("dateImageGenerationRateLimits").doc("current");
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const stored = snapshot.data() as Partial<StoredImageRateLimit> | undefined;
    const now = Timestamp.now();
    const valid = stored?.windowStartedAt instanceof Timestamp
      && stored?.lastRequestedAt instanceof Timestamp
      && typeof stored.generatedImagesInWindow === "number";
    const withinWindow = valid && now.toMillis() - stored!.windowStartedAt!.toMillis() < windowMilliseconds;
    const existingCount = withinWindow ? stored!.generatedImagesInWindow! : 0;

    if (withinWindow && now.toMillis() - stored!.lastRequestedAt!.toMillis() < minimumIntervalMilliseconds) {
      throw new HttpsError("resource-exhausted", "Bitte warte kurz, bevor weitere Bilder erstellt werden.");
    }
    if (existingCount + requestedImages > maximumNewImagesPerWindow) {
      throw new HttpsError("resource-exhausted", "Für diese kurze Zeit wurden bereits viele KI-Bilder erstellt. Bitte versuche es später erneut.");
    }
    transaction.set(reference, {
      windowStartedAt: withinWindow ? stored!.windowStartedAt : now,
      lastRequestedAt: now,
      generatedImagesInWindow: existingCount + requestedImages,
    });
  });
}
