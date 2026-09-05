import {type CallableRequest} from "firebase-functions/v2/https";

import {assertActiveUser, requireVerifiedAuth, type VerifiedActiveUserContext} from "./context";
import {getUserPermissions} from "../permissions/userPermissions";

/**
 * Preserve the verified/active gate of the deployed v1 endpoints being repaired.
 * MFA rollout is a separate change: importing today's stricter shared helper
 * must not silently change the authentication contract of an existing endpoint.
 * New commands that replace direct Rules-protected writes use the normal helper.
 */
export async function requireLegacyCallableUser(request: CallableRequest): Promise<VerifiedActiveUserContext> {
  const auth = requireVerifiedAuth(request);
  const permissions = await getUserPermissions(auth.uid);
  assertActiveUser(permissions);
  return {...auth, permissions};
}
