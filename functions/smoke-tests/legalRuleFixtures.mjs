import {collection, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc, writeBatch} from 'firebase/firestore';

const defaultVersion = '2026.13';
const testHash = 'a'.repeat(64);

// Existing rules suites test unrelated permissions with server-seeded users.
// Give those fixtures the current legal versions, while keeping the dedicated
// legal suite responsible for negative and stale-version cases.
export async function seedCurrentLegalVersions(environment) {
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    const versions = {};
    for (const type of ['terms', 'privacy']) {
      const pointer = doc(database, 'legalDocuments', type);
      const snapshot = await getDoc(pointer);
      const version = snapshot.get('activeVersion') ?? defaultVersion;
      const fields = {
        documentType: type,
        version,
        versionNumber: Number(version.replace('.', '')),
        status: 'published',
        requiresAcceptance: type === 'terms',
        contentHash: testHash,
      };
      await setDoc(pointer, {...fields, activeVersion: version}, {merge: true});
      await setDoc(doc(pointer, 'versions', version), fields, {merge: true});
      versions[type] = version;
    }
    const users = await getDocs(collection(database, 'users'));
    await Promise.all(users.docs.map(user => updateDoc(user.ref, {
      acceptedTermsVersion: versions.terms,
      acceptedPrivacyVersion: versions.privacy,
    })));
  });
}

export function registerWithCurrentLegalEvidence(database, uid, profile) {
  const batch = writeBatch(database);
  batch.set(doc(database, 'users', uid), {
    ...profile,
    acceptedTermsVersion: defaultVersion,
    acceptedPrivacyVersion: defaultVersion,
    termsVersion: defaultVersion,
    privacyVersion: defaultVersion,
  });
  for (const type of ['terms', 'privacy']) {
    batch.set(doc(database, 'legalAcceptanceLogs', `${uid}_${type}_${defaultVersion}`), {
      userId: uid,
      documentType: type,
      version: defaultVersion,
      acceptedAt: serverTimestamp(),
      appVersion: 'test',
      locale: 'uk',
      contentHash: testHash,
      acceptedFromPlatform: 'ios',
    });
  }
  return batch.commit();
}
