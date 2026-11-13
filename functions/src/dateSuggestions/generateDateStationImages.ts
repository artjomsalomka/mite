import { createHash } from "node:crypto";
import OpenAI from "openai";
import { getStorage } from "firebase-admin/storage";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { db } from "../firebaseAdmin";
import { reserveImageGenerationSlots } from "./dateImageGenerationRateLimit";
import type { DateStation, DateSuggestion, GeneratedDateImage } from "./types";

const openaiApiKey = defineSecret("OPENAI_API_KEY");
const imageModel = defineString("OPENAI_IMAGE_MODEL", { default: "gpt-image-1-mini" });
const maximumStationsPerRoute = 4;
const imageVersion = "v1";

type Scope = { coupleId?: string; matchId?: string; ownerUid?: string };
interface RequestData extends Scope { requestId?: string; suggestionId?: string; }

interface StationImageResult { order: number; licensedImage: GeneratedDateImage; }

export const generateDateStationImages = onCall(
  { secrets: [openaiApiKey], timeoutSeconds: 60, memory: "1GiB" },
  async (request): Promise<{ stationImages: StationImageResult[] }> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as RequestData;
    const scopeCount = [data.coupleId, data.matchId, data.ownerUid].filter((value) => typeof value === "string" && value.length > 0).length;
    if (!data.requestId || !data.suggestionId || scopeCount !== 1) {
      throw new HttpsError("invalid-argument", "Date-Kontext, Anfrage und Vorschlag sind erforderlich.");
    }

    const scopeRef = data.coupleId
      ? db.collection("couples").doc(data.coupleId)
      : data.matchId
        ? db.collection("singleMatches").doc(data.matchId)
        : db.collection("users").doc(data.ownerUid!);
    const scope = await scopeRef.get();
    const hasAccess = data.ownerUid
      ? data.ownerUid === uid
      : ((scope.data()?.memberUids ?? []) as string[]).includes(uid);
    if (!scope.exists || !hasAccess) {
      throw new HttpsError("permission-denied", "Dieser Date-Vorschlag ist nicht verfügbar.");
    }

    const requestRef = scopeRef.collection("dateRequests").doc(data.requestId);
    const savedRequest = await requestRef.get();
    if (!savedRequest.exists || savedRequest.data()?.status !== "completed") {
      throw new HttpsError("not-found", "Der Date-Vorschlag wurde nicht gefunden.");
    }
    const criteria = savedRequest.data()?.criteria as { city?: unknown } | undefined;
    const city = typeof criteria?.city === "string" ? criteria.city.trim() : "";
    const suggestions = (savedRequest.data()?.suggestions ?? []) as DateSuggestion[];
    const suggestion = suggestions.find((item) => item.id === data.suggestionId);
    if (!suggestion || !city) throw new HttpsError("not-found", "Der Date-Vorschlag ist unvollständig.");

    const stations = suggestion.stations.slice(0, maximumStationsPerRoute);
    const cached = await Promise.all(stations.map((station) => readCachedImage(station, city)));
    const missing = stations.filter((_, index) => cached[index] == null);
    await reserveImageGenerationSlots(uid, missing.length);

    const client = new OpenAI({ apiKey: openaiApiKey.value(), maxRetries: 0, timeout: 55_000 });
    const generated = await Promise.all(stations.map(async (station, index) => {
      const existing = cached[index];
      if (existing) return { order: station.order, licensedImage: existing };
      try {
        return { order: station.order, licensedImage: await createAndStoreImage(client, station, city, uid) };
      } catch (error) {
        // A missing visual never invalidates an otherwise usable, place-verified date route.
        logger.warn("Date station image generation failed.", {
          failureType: error instanceof Error ? error.name : "UnknownError",
          providerStatus: typeof (error as { status?: unknown })?.status === "number"
            ? (error as { status: number }).status : undefined,
        });
        return null;
      }
    }));

    const stationImages = generated.filter((item): item is StationImageResult => item != null);
    if (stationImages.length > 0) {
      const updated = suggestions.map((candidate) => candidate.id !== suggestion.id ? candidate : {
        ...candidate,
        stations: candidate.stations.map((station) => {
          const image = stationImages.find((result) => result.order === station.order)?.licensedImage;
          return image ? { ...station, licensedImage: image } : station;
        }),
      });
      await requestRef.update({ suggestions: updated });
    }
    return { stationImages };
  },
);

async function readCachedImage(station: DateStation, city: string): Promise<GeneratedDateImage | null> {
  const path = objectPath(station, city);
  const [exists] = await getStorage().bucket().file(path).exists();
  return exists ? generatedImage(path) : null;
}

async function createAndStoreImage(client: OpenAI, station: DateStation, city: string, uid: string): Promise<GeneratedDateImage> {
  const path = objectPath(station, city);
  const file = getStorage().bucket().file(path);
  const response = await client.images.generate({
    model: imageModel.value(),
    prompt: buildImagePrompt(station, city),
    size: "1024x1024",
    quality: "medium",
    n: 1,
    output_format: "jpeg",
    output_compression: 78,
    background: "opaque",
    moderation: "auto",
    user: "pb-" + createHash("sha256").update(uid).digest("hex").slice(0, 24),
  });
  const image = response.data?.[0]?.b64_json;
  if (!image) throw new Error("OpenAI returned no image data.");
  const data = Buffer.from(image, "base64");
  if (data.length < 1_000 || data.length > 8 * 1024 * 1024) throw new Error("Generated image size was invalid.");

  // A second concurrent request may have filled the same cache key while OpenAI was rendering.
  const [exists] = await file.exists();
  if (!exists) {
    await file.save(data, {
      resumable: false,
      validation: "md5",
      metadata: {
        contentType: "image/jpeg",
        cacheControl: "public,max-age=31536000,immutable",
        metadata: {
          kind: "ai-date-mood-image",
          model: imageModel.value(),
          imageVersion,
        },
      },
    });
  }
  return generatedImage(path);
}

function objectPath(station: DateStation, city: string): string {
  const promptKey = JSON.stringify({
    version: imageVersion, city: city.toLocaleLowerCase("de-DE"), title: station.title,
    category: station.category, hint: station.searchQueryHint, description: station.description,
  });
  const hash = createHash("sha256").update(promptKey).digest("hex");
  return "generatedDateImages/" + imageVersion + "/" + hash + ".jpg";
}

function generatedImage(path: string): GeneratedDateImage {
  return {
    url: "storage://" + path,
    sourcePageURL: "https://openai.com/policies/usage-policies/",
    creator: "OpenAI GPT Image 1 Mini",
    license: "KI-Stimmungsbild",
    licenseURL: null,
    contextLabel: "KI-Stimmungsbild · nicht das konkrete Geschäft oder der konkrete Ort",
  };
}

function buildImagePrompt(station: DateStation, city: string): string {
  return [
    "Create one square, premium editorial mood image for a mobile date-planning app.",
    "The date activity is: " + station.title + ".",
    "Activity description: " + station.description + ".",
    "It takes place in or near " + city + ".",
    "Depict a warm, inviting, plausible atmosphere for this activity, with elegant natural lighting and cinematic but believable composition.",
    "Do not reproduce or claim to show a specific real venue, landmark, business, or street.",
    "Do not include readable text, logos, map imagery, branding, watermarks, UI, or identifiable people.",
    "The output must be a polished standalone photograph-style image, with no border or collage.",
  ].join("\\n");
}
