import { logger } from "firebase-functions";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { Timestamp } from "firebase-admin/firestore";
import Stripe from "stripe";
import { db } from "../firebaseAdmin";
import { requireSingleProfile } from "./singleHelpers";

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

type VerificationStatus = "unverified" | "pending" | "verified" | "requires_input";

function stripeClient(): Stripe {
  return new Stripe(stripeSecretKey.value(), { apiVersion: "2026-08-26.dahlia" });
}

function appStatus(session: Stripe.Identity.VerificationSession): VerificationStatus {
  switch (session.status) {
  case "verified": return "verified";
  case "requires_input": return "requires_input";
  case "processing": return "pending";
  default: return "unverified";
  }
}

/// Persists only the provider, opaque session id and outcome. ID images, names, document data
/// and Stripe's client secret never reach Firestore.
async function persistStatus(uid: string, session: Stripe.Identity.VerificationSession): Promise<VerificationStatus> {
  const status = appStatus(session);
  const now = Timestamp.now();
  const batch = db.batch();
  batch.set(db.collection("users").doc(uid), {
    verificationStatus: status,
    verificationUpdatedAt: now,
  }, { merge: true });
  batch.set(db.collection("singleProfiles").doc(uid), {
    isVerified: status === "verified",
    updatedAt: now,
  }, { merge: true });
  batch.set(db.collection("singleVerifications").doc(uid), {
    provider: "stripe",
    sessionId: session.id,
    status,
    updatedAt: now,
  }, { merge: true });
  await batch.commit();
  return status;
}

function clientSecretOrThrow(session: Stripe.Identity.VerificationSession): string {
  if (!session.client_secret) {
    throw new HttpsError("failed-precondition", "Die Verifizierungs-Sitzung ist abgelaufen. Bitte erneut starten.");
  }
  return session.client_secret;
}

async function nextVerificationAttempt(uid: string): Promise<number> {
  const reference = db.collection("singleVerifications").doc(uid);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.data()?.attempt;
    const attempt = typeof current === "number" ? current + 1 : 1;

    transaction.set(reference, {
      attempt,
      updatedAt: Timestamp.now(),
    }, { merge: true });

    return attempt;
  });
}

async function createSession(uid: string): Promise<Stripe.Identity.VerificationSession> {
  const attempt = await nextVerificationAttempt(uid);

  return stripeClient().identity.verificationSessions.create({
    type: "document",
    client_reference_id: uid,
    options: {
      document: {
        require_live_capture: true,
        require_matching_selfie: true,
      },
    },
  }, {
    idempotencyKey: `single-verification-${uid}-${attempt}`,
  });
}

/// Returns a one-time secret only to the authenticated user who owns the session. A completed
/// upload does not grant a verified badge—the status is re-read from Stripe server-side.
export const startSingleVerification = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    const uid = request.auth.uid;
    await requireSingleProfile(uid);

    const stored = await db.collection("singleVerifications").doc(uid).get();
    let session: Stripe.Identity.VerificationSession | null = null;
    const storedSessionId = stored.data()?.sessionId;
    if (typeof storedSessionId === "string") {
      try {
        session = await stripeClient().identity.verificationSessions.retrieve(storedSessionId);
      } catch {
        // A redacted or unavailable session is safely replaced below.
        session = null;
      }
    }

    if (!session || session.status === "canceled") {
      session = await createSession(uid);
    }

    const status = await persistStatus(uid, session);
    if (status === "verified") {
      return { status, verificationSessionClientSecret: null };
    }
    if (status === "pending") {
      return { status, verificationSessionClientSecret: null };
    }
    return {
      status,
      verificationSessionClientSecret: clientSecretOrThrow(session),
    };
  }
);

/// Lets the client refresh after Stripe's sheet closes. In production this is complemented by a
/// signed Stripe webhook, but this server-side retrieval remains the authority for the badge.
export const refreshSingleVerificationStatus = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    const uid = request.auth.uid;
    await requireSingleProfile(uid);

    const stored = await db.collection("singleVerifications").doc(uid).get();
    const sessionId = stored.data()?.sessionId;
    if (typeof sessionId !== "string") return { status: "unverified" satisfies VerificationStatus };

    const session = await stripeClient().identity.verificationSessions.retrieve(sessionId);
    return { status: await persistStatus(uid, session) };
  }
);

/// Stripe calls this endpoint after a verification result changes. The signature is validated
/// before any Firestore write, so clients can never grant themselves a verified badge. The local
/// signing secret is supplied by the emulator through functions/.secret.local.
export const stripeIdentityWebhook = onRequest(
  { secrets: [stripeSecretKey, stripeWebhookSecret] },
  async (request, response) => {
    const signature = request.header("stripe-signature");
    if (!signature) {
      response.status(400).send("Missing Stripe signature.");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripeClient().webhooks.constructEvent(
        request.rawBody,
        signature,
        stripeWebhookSecret.value(),
      );
    } catch (error) {
      logger.warn("Rejected Stripe webhook with an invalid signature.", { error });
      response.status(400).send("Invalid Stripe signature.");
      return;
    }

    if (!event.type.startsWith("identity.verification_session.")) {
      response.status(200).json({ received: true });
      return;
    }

    const notifiedSession = event.data.object as Stripe.Identity.VerificationSession;
    const uid = notifiedSession.client_reference_id;
    if (typeof uid !== "string" || uid.trim().length === 0) {
      logger.warn("Ignored Stripe Identity event without a user reference.", { eventType: event.type });
      response.status(200).json({ received: true });
      return;
    }

    try {
      const session = await stripeClient().identity.verificationSessions.retrieve(notifiedSession.id);
      const status = await persistStatus(uid, session);
      logger.info("Updated single verification from Stripe webhook.", {
        eventType: event.type,
        status,
      });
      response.status(200).json({ received: true });
    } catch (error) {
      logger.error("Could not persist a verified Stripe Identity event.", { error, eventType: event.type });
      response.status(500).send("Webhook processing failed.");
    }
  },
);
