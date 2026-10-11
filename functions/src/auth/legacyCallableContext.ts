import {type CallableRequest} from "firebase-functions/v2/https";

import {assertActiveUser, assertCurrentLegalAcknowledgements, requireVerifiedAuth, type VerifiedActiveUserContext} from "./context";
import {getUserPermissions} from "../permissions/userPermissions";

/**
 * Preserve the v1 MFA contract while enforcing current legal versions on
 * account operations. MFA rollout remains a separate change.
 */
export async function requireLegacyCallableUser(request: CallableRequest): Promise<VerifiedActiveUserContext> {
  const auth = requireVerifiedAuth(request);
  const permissions = await getUserPermissions(auth.uid);
  assertActiveUser(permissions);
  await assertCurrentLegalAcknowledgements(permissions);
  return {...auth, permissions};
}
