import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

export interface AuthContext {
  uid: string;
  token: NonNullable<CallableRequest["auth"]>["token"];
}

export function requireAuth(request: CallableRequest): AuthContext {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  return {
    uid: request.auth.uid,
    token: request.auth.token,
  };
}
