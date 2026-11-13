#!/usr/bin/env bash

# Starts the complete local backend used by the iOS Simulator.
# Test data is exported when this process is stopped cleanly (Ctrl-C), then
# re-imported on the next start. OpenAI's local key is mirrored from the
# ignored .env.local into the ignored .secret.local for defineSecret().

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
export_dir="$project_root/emulator-data"
# Must match the demo GoogleService-Info.plist used by the Debug app. `--project` affects only
# the local Emulator Suite; it does not deploy, read, or write any cloud data.
firebase_project="demo-mite-submission"

cd "$project_root"
mkdir -p "$export_dir"
node "$project_root/Scripts/sync-local-secrets.mjs"

# The Firestore emulator currently runs reliably with the installed LTS JDK 21. The globally
# selected JDK 25 lets the emulator boot, but causes iOS Firestore Watch/Write streams to fail
# internally and leaves the app offline. Keep this scoped to the local emulator process only.
if java_21_home="$(/usr/libexec/java_home -v 21 2>/dev/null)"; then
  export JAVA_HOME="$java_21_home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

npm --prefix functions run build

if [[ -f "$export_dir/firebase-export-metadata.json" ]]; then
  exec firebase emulators:start \
    --project="$firebase_project" \
    --only auth,firestore,functions,storage \
    --import="$export_dir" \
    --export-on-exit="$export_dir"
else
  exec firebase emulators:start \
    --project="$firebase_project" \
    --only auth,firestore,functions,storage \
    --export-on-exit="$export_dir"
fi
