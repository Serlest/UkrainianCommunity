import {FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  isPrivilegedSessionAuthenticated,
  isTOTPAuthenticated,
  requireVerifiedActiveUser,
} from "./context";
import {db} from "../firebase/admin";
import {
  isAppAdmin,
  isAppOwner,
  userPermissionSnapshotFromData,
} from "../permissions/userPermissions";

export interface PrivilegedMFAActivationResponse {
  required: true;
  activatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 5,
  // Keep aligned with the staged App Check rollout. The request is still
  // protected by verified Auth, TOTP or passkey session proof, and a live role read.
  enforceAppCheck: false,
};

export const activatePrivilegedMFAProtection = onCall(
  callableOptions,
  async (request): Promise<PrivilegedMFAActivationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    if (!isPrivilegedSessionAuthenticated(auth.token, auth.permissions)) {
      throw new HttpsError(
        "failed-precondition",
        "Sign in with a passkey or authenticator before activating privileged protection."
      );
    }
    if (!isAppOwner(auth.permissions) && !isAppAdmin(auth.permissions)) {
      throw new HttpsError(
        "permission-denied",
        "Privileged MFA activation is available only to platform owners and admins."
      );
    }

    const userReference = db.collection("users").doc(auth.uid);
    const activatedAt = Timestamp.now();
    const method = isTOTPAuthenticated(auth.token) ? "totp" : "passkey";

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(userReference);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "User profile does not exist.");
      }

      const permissions = userPermissionSnapshotFromData(auth.uid, snapshot.data());
      if (!isAppOwner(permissions) && !isAppAdmin(permissions)) {
        throw new HttpsError(
          "permission-denied",
          "The account no longer has a privileged platform role."
        );
      }

      if (permissions.requiresMultiFactorAuth === true) {
        return;
      }

      transaction.update(userReference, {
        requiresMultiFactorAuth: true,
        multiFactorAuthRequiredAt: activatedAt,
        multiFactorAuthRequiredMethod: method,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    logger.info("Privileged sign-in protection activated", {
      actorUserId: auth.uid,
      method,
    });

    return {
      required: true,
      activatedAt: activatedAt.toDate().toISOString(),
    };
  }
);
