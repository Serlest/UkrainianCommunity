export type OrganizationModerationStatus =
  | "pendingReview"
  | "needsRevision"
  | "rejected"
  | "approved"
  | "archived";

export interface OrganizationRequestReviewInput {
  organizationId: string;
  moderationStatus: OrganizationModerationStatus;
  reviewMessage?: string | null;
  rejectionReason?: string | null;
}
