#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if java_21_home="$(/usr/libexec/java_home -v 21 2>/dev/null)"; then
  export JAVA_HOME="$java_21_home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export GCLOUD_PROJECT=demo-mite-audit
export FIRESTORE_EMULATOR_HOST=127.0.0.1:18080
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:19099
export FUNCTIONS_EMULATOR_HOST=127.0.0.1:15001
npm --prefix functions run build
# No import/export: tests cannot replace the developer's saved emulator data.
exec firebase emulators:exec --config firebase.audit.json --project demo-mite-audit \
  --only auth,firestore,functions,storage "npm --prefix functions run quality:local"
