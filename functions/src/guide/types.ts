export type GuideArticleStatus = "draft" | "review" | "approved" | "published" | "archived";
export type GuideModerationStatus = "draft" | "pendingReview" | "approved" | "archived";

export interface GuideWorkflowInput {
  articleId: string;
  actorUserId: string;
}
