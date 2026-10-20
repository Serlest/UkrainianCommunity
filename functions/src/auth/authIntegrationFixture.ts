import {adminAuth} from "../firebase/admin";

function requireLocalAuth(): void {
  if (!process.env.GCLOUD_PROJECT?.startsWith("demo-") ||
      !/^(127\.0\.0\.1|localhost):/.test(process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "")) {
    throw new Error("Auth fixtures require a local demo emulator.");
  }
}

export async function seedVerifiedAuthForIntegration(...userIds: string[]): Promise<void> {
  requireLocalAuth();
  for (const uid of userIds) {
    await adminAuth.createUser({uid, email: `${uid}@example.test`, emailVerified: true});
  }
}

export async function deleteAuthForIntegration(...userIds: string[]): Promise<void> {
  requireLocalAuth();
  await adminAuth.deleteUsers(userIds);
}
