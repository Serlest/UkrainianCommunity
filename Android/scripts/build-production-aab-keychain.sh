#!/bin/bash
set -euo pipefail

uac_account="${UAC_KEYCHAIN_ACCOUNT:-serlest}"
uac_signing_dir="${UAC_ANDROID_SIGNING_DIR:-/Users/serlest/Library/Application Support/UAC/AndroidSigning}"

export UAC_PRODUCTION_KEYSTORE="$uac_signing_dir/uac-upload.jks"
export UAC_PRODUCTION_KEY_ALIAS="uac-upload"
export UAC_PRODUCTION_KEYSTORE_PASSWORD="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Keystore Password' -w)"
export UAC_PRODUCTION_KEY_PASSWORD="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Key Password' -w)"
export UAC_PRODUCTION_FIREBASE_PROJECT_ID="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Firebase Project ID' -w)"
export UAC_PRODUCTION_FIREBASE_APPLICATION_ID="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Firebase Application ID' -w)"
export UAC_PRODUCTION_FIREBASE_API_KEY="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Firebase API Key' -w)"
export UAC_PRODUCTION_FIREBASE_BUCKET="$(security find-generic-password -a "$uac_account" -s 'UAC Android Production Firebase Bucket' -w)"

uac_clear_secrets() {
  unset UAC_PRODUCTION_KEYSTORE_PASSWORD UAC_PRODUCTION_KEY_PASSWORD
  unset UAC_PRODUCTION_FIREBASE_PROJECT_ID UAC_PRODUCTION_FIREBASE_APPLICATION_ID
  unset UAC_PRODUCTION_FIREBASE_API_KEY UAC_PRODUCTION_FIREBASE_BUCKET
}
trap uac_clear_secrets EXIT

node scripts/build-production-aab.mjs
