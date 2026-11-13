# Mite

A native iOS prototype for planning outings with friends. Choose a city, budget and mood, combine activity suggestions, and organise the resulting plan together.

## What the demo shows

Preferences → five alternatives for each activity slot → choose a combination → an itinerary with real-place lookup. OpenAI generates structured suggestions; Apple MapKit searches for the suggested venues. Generated images illustrate the mood and are not photographs of those venues.

The broader prototype includes group chat, availability coordination, shared expenses and social features. The hackathon demonstration focuses on planning.

## Architecture

Swift/SwiftUI (iOS 17+) → Firebase Authentication + callable TypeScript Functions → OpenAI Responses API → validated structured suggestions → MapKit lookup in the app. Firestore and Storage have per-user/member access rules. Provider secrets belong only in the backend.

## Review without an API key

No author-owned API key, live backend, shared account or hosted AI access is supplied. Inspect the source and the accompanying real Simulator demo without running a provider request. To reproduce live AI generation, use your own OpenAI account and credentials; any resulting provider charges belong to that account. Without a valid provider key the live AI planning feature is unavailable. No backend is deployed by cloning this repository or running the documented local setup.

## Run locally

Prerequisites: macOS, Xcode with an iOS Simulator, XcodeGen, Node.js 22 LTS, Firebase CLI and Java 21 for the emulators.

```sh
npm --prefix functions ci
cp Configuration/GoogleService-Info.example.plist PerfectBoyfriend/GoogleService-Info.plist
cp functions/.env.example functions/.env.local
# Edit the ignored .env.local: enter your own OpenAI key and available model IDs.
# The planning demo does not require Stripe keys; remove those optional placeholder lines.
xcodegen generate
./Scripts/start-local.sh
```

In a second terminal, open `PerfectBoyfriend.xcodeproj`, select the PerfectBoyfriend scheme, Debug and an iPhone Simulator, then run. Register a local account and choose group planning. Use synthetic names and an example.test email for local tests.

The example plist deliberately contains dummy values and the `demo-mite-submission` project ID. It works only with the local emulators. `start-local.sh` uses that same demo project, imports only your own local test data if present, and never deploys. Emulator ports bind to localhost by default. Do not replace this configuration with the author's Firebase resources. A physical device needs deliberate local-network configuration; the documented default is the Simulator.

AI generation uses your own API account and can cost money: one text generation plus two or three images after selecting a route. The text output is capped at 8,000 tokens; retries are disabled for that provider call. Provider usage counts are logged without prompts or keys. Model access and pricing depend on your account. No shared provider key, demo password, private account export or user data is included.

## Verified snapshot

The privacy-cleaned export was revalidated on 13 November: all 21 backend unit tests (Node.js 22) and all 19 iOS unit tests passed. Optional dependency funding/contact metadata was removed; dependency versions and integrity hashes are unchanged.

On 12–13 November 2026, the backend TypeScript build and all 21 unit tests passed. Seven isolated Firebase smoke-test suites passed (auth, couple lifecycle, personal social, post media, groups, matching and Firestore rules). The iOS Simulator build and 19 iOS unit tests passed with Xcode 26.6 / iOS 26.5. Unit tests ran on Node.js 26; the recorded live planning demo ran with Node.js 22.23.5 and Java 21, matching the configured Node.js 22 deployment runtime.

A dependency update removed the critical, high and low findings reported by npm audit. The final npm audit still reports six moderate findings in indirect dependencies. This is not a certification that the prototype is safe to operate publicly. The source contains known prototype limitations described below.

The fresh Simulator walkthrough on 13 November successfully generated five choices per slot, resolved two Marburg venues, generated two mood images, and saved the selected route as a group event with two synthetic local participants. Waiting periods and an emulator reconnection are cut from the edited recording; it is not an uninterrupted one-take demo. No real user accounts or location permissions are required for that demonstration.

## Tests

```sh
npm --prefix functions test
bash Scripts/audit-local.sh
```

The audit script uses isolated localhost ports and the `demo-mite-audit` project. It runs backend unit tests and local auth, relationship, social, group, matching and access-rule smoke tests without paid AI generation. With no local secret configuration, the emulator may ask for dummy values for the declared provider secrets; use throwaway strings for this free audit. The separately named `smoke:ai-group-plan` script makes real billed calls and is intentionally excluded from the free audit.

## Development history and contribution

Development began in August 2026, before the hackathon started on October 27. This is an existing personal project, not an application built entirely during the hackathon. Product requirements, design direction, decisions and iterative review were provided by the project author. Claude and OpenAI Codex were used extensively for implementation and debugging. The AI inside the app is distinct from those coding assistants.

## Limitations and safety

This is a development prototype, not a hosted public service or an App Store release. App Check is configured on the client but is not enforced by the callable backend in this snapshot. Authentication and per-user rate limits are present; public deployment requires additional abuse protection, budget controls and operational review.

Place lookup does not verify opening hours, reservations, availability or prices. The visual itinerary is not guaranteed navigation. The optional identity verification and push-notification integrations require separate setup and are outside the planning walkthrough.

The public source excludes personal avatars, seeded account data, private configuration, build products and diagnostic logs. Generic fallback photographs are omitted pending a complete attribution review; those locations may show an empty photo placeholder until a generated/real image is available. Code paths and attribution metadata are retained. The two bundled assembly illustrations and app icon are project artwork; no rights to unrelated demo photos or soundtrack are claimed.

## Licensing and dependencies

No blanket open-source licence has been selected for the author's code or artwork. Public availability for review does not grant a new licence to third-party assets. Apple frameworks, Firebase, Stripe and OpenAI SDKs retain their respective licences; their source is resolved through package managers rather than bundled here. See `NOTICE.md`.
