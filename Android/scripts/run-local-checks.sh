#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Explicit config + demo ID; Functions/Hosting/PubSub are deliberately not started.
exec firebase emulators:exec --config ../firebase.android-local.json --project demo-uac-android --only auth,firestore,storage "node scripts/local-fixtures.mjs"
