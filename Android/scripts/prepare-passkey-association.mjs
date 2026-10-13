#!/usr/bin/env node
// Prints a reviewable Digital Asset Links entry and the matching server origin.
// It never writes to Firebase Hosting or modifies an account.
import { Buffer } from 'node:buffer';

const [packageName, fingerprint] = process.argv.slice(2);
const allowedPackages = new Set([
  'at.serlest.ukrainiancommunity',
  'at.serlest.ukrainiancommunity.staging',
]);
if (!allowedPackages.has(packageName) ||
    !/^(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$/.test(fingerprint ?? '')) {
  console.error('Usage: node prepare-passkey-association.mjs <UAC package> <SHA-256 certificate fingerprint as 32 colon-separated bytes>');
  process.exit(2);
}
const bytes = Buffer.from(fingerprint.replaceAll(':', ''), 'hex');
const origin = `android:apk-key-hash:${bytes.toString('base64url')}`;
console.log(JSON.stringify({
  assetlinksEntry: {
    relation: ['delegate_permission/common.get_login_creds'],
    target: {
      namespace: 'android_app',
      package_name: packageName,
      sha256_cert_fingerprints: [fingerprint.toUpperCase()],
    },
  },
  serverOrigin: origin,
}, null, 2));
