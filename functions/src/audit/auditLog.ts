import { FieldValue } from "firebase-admin/firestore";

import { db } from "../firebase/admin";

export type AuditActionType =
  | "warningIssued"
  | "suspended"
  | "banned"
  | "unblocked"
  | "deactivated"
  | "organizationRoleAssigned"
  | "organizationRoleRemoved"
  | "organizationOwnerChanged"
  | "organizationRequestApproved"
  | "organizationRequestNeedsRevision"
  | "organizationRequestRejected";

export interface AuditLogInput {
  actionType: AuditActionType;
  targetUserId: string;
  performedBy: string;
  reason: string;
  note?: string | null;
  previousValue: Record<string, unknown>;
  newValue: Record<string, unknown>;
}

export function auditLogRef() {
  return db.collection("auditLogs").doc();
}

export function buildAuditLog(input: AuditLogInput) {
  return {
    ...input,
    note: input.note ?? null,
    createdAt: FieldValue.serverTimestamp(),
  };
}
