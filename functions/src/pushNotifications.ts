import { logger } from "firebase-functions";
import { DocumentReference } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { db } from "./firebaseAdmin";

export interface GenericPushNotification {
  title: string;
  body: string;
  data: Record<string, string>;
}

/// Sends opt-in, privacy-preserving notifications. Message text and exact locations deliberately
/// never enter a push payload because lock-screen previews are outside the app's privacy boundary.
export async function sendGenericPush(
  recipientUids: string[],
  notification: GenericPushNotification,
): Promise<void> {
  const uniqueRecipientUids = [...new Set(recipientUids)];
  const tokenSnapshots = await Promise.all(
    uniqueRecipientUids.map((uid) => db.collection("users").doc(uid).collection("deviceTokens").get()),
  );
  const tokenEntries: Array<{ reference: DocumentReference; token: string }> = [];
  for (const snapshot of tokenSnapshots) {
    for (const document of snapshot.docs) {
      const token = document.data().token;
      if (typeof token === "string") tokenEntries.push({ reference: document.ref, token });
    }
  }
  if (tokenEntries.length === 0) return;

  const response = await getMessaging().sendEachForMulticast({
    tokens: tokenEntries.map((entry) => entry.token),
    notification: {
      title: notification.title,
      body: notification.body,
    },
    data: notification.data,
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });

  const invalidTokenDeletes = response.responses.flatMap((item, index) => {
    const code = item.error?.code;
    return code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token"
      ? [tokenEntries[index].reference.delete()]
      : [];
  });
  await Promise.all(invalidTokenDeletes);

  if (response.failureCount > 0) {
    logger.warn("Some push notifications could not be delivered.", {
      failedCount: response.failureCount,
    });
  }
}
