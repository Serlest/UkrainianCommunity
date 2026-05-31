import { Timestamp, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import {
  assertCanManageGuide,
  assertOwner,
  getUserPermissions,
} from "../permissions/userPermissions";
import { type GuideArticleStatus, type GuideModerationStatus } from "./types";

type GuideWorkflowAction = "submit" | "approve" | "publish" | "archive";
type ReviewInterval = "critical" | "normal" | "stable";

interface GuideWorkflowRequest {
  articleId: string;
}

interface GuideWorkflowResponse {
  articleId: string;
  moderationStatus: GuideModerationStatus;
  status: GuideArticleStatus;
  updatedAt: string;
}

interface GuideArticleWorkflowSnapshot {
  articleId: string;
  moderationStatus: GuideModerationStatus;
  status?: GuideArticleStatus;
  reviewInterval?: ReviewInterval;
  archivedAt?: unknown;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

function parseGuideWorkflowRequest(data: unknown): GuideWorkflowRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    articleId: normalizedRequiredString(data.articleId, "articleId"),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedRequiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return trimmedValue;
}

function articleSnapshotFromData(
  articleId: string,
  data: DocumentData | undefined
): GuideArticleWorkflowSnapshot {
  return {
    articleId,
    moderationStatus: guideModerationStatus(data?.moderationStatus),
    status: guideArticleStatus(data?.status),
    reviewInterval: reviewInterval(data?.reviewInterval),
    archivedAt: data?.archivedAt,
  };
}

function guideModerationStatus(value: unknown): GuideModerationStatus {
  switch (value) {
    case "draft":
    case "pendingReview":
    case "approved":
    case "archived":
      return value;
    default:
      return "draft";
  }
}

function guideArticleStatus(value: unknown): GuideArticleStatus | undefined {
  switch (value) {
    case "draft":
    case "review":
    case "approved":
    case "published":
    case "archived":
      return value;
    default:
      return undefined;
  }
}

function reviewInterval(value: unknown): ReviewInterval | undefined {
  switch (value) {
    case "critical":
    case "normal":
    case "stable":
      return value;
    default:
      return undefined;
  }
}

function assertNotArchived(article: GuideArticleWorkflowSnapshot): void {
  if (article.archivedAt !== undefined || article.status === "archived") {
    throw new HttpsError("failed-precondition", "Guide article is already archived.");
  }
}

function assertDraftArticle(article: GuideArticleWorkflowSnapshot): void {
  assertNotArchived(article);

  if (
    article.moderationStatus !== "draft"
    || (article.status !== undefined && article.status !== "draft")
  ) {
    throw new HttpsError("failed-precondition", "Guide article must be a draft.");
  }
}

function assertReviewArticle(article: GuideArticleWorkflowSnapshot): void {
  assertNotArchived(article);

  if (article.moderationStatus !== "pendingReview" || article.status !== "review") {
    throw new HttpsError("failed-precondition", "Guide article must be in review.");
  }
}

function assertApprovedArticle(article: GuideArticleWorkflowSnapshot): void {
  assertNotArchived(article);

  if (article.moderationStatus !== "approved" || article.status !== "approved") {
    throw new HttpsError("failed-precondition", "Guide article must be approved.");
  }
}

function nextReviewDate(publishedAt: Date, interval: ReviewInterval | undefined): Date {
  const nextReviewAt = new Date(publishedAt);

  switch (interval ?? "normal") {
    case "critical":
      nextReviewAt.setMonth(nextReviewAt.getMonth() + 3);
      break;
    case "normal":
      nextReviewAt.setMonth(nextReviewAt.getMonth() + 6);
      break;
    case "stable":
      nextReviewAt.setMonth(nextReviewAt.getMonth() + 12);
      break;
  }

  return nextReviewAt;
}

function createGuideWorkflowCallable(action: GuideWorkflowAction) {
  return onCall(callableOptions, async (request): Promise<GuideWorkflowResponse> => {
    const auth = requireAuth(request);
    const workflowRequest = parseGuideWorkflowRequest(request.data);
    const actorPermissions = await getUserPermissions(auth.uid);
    const articleReference = db.collection("guideArticles").doc(workflowRequest.articleId);
    const committedAt = new Date();
    let nextModerationStatus: GuideModerationStatus = "draft";
    let nextStatus: GuideArticleStatus = "draft";

    await db.runTransaction(async (transaction) => {
      const articleDocument = await transaction.get(articleReference);
      if (!articleDocument.exists) {
        throw new HttpsError("not-found", "Guide article does not exist.");
      }

      const article = articleSnapshotFromData(workflowRequest.articleId, articleDocument.data());
      const update = guideWorkflowUpdate(action, article, auth.uid, committedAt);
      nextModerationStatus = update.moderationStatus;
      nextStatus = update.status;

      if (action === "submit") {
        assertCanManageGuide(actorPermissions);
      } else if (action === "archive" && article.moderationStatus === "draft") {
        assertCanManageGuide(actorPermissions);
      } else {
        assertOwner(actorPermissions);
      }

      transaction.update(articleReference, update.data);
    });

    return {
      articleId: workflowRequest.articleId,
      moderationStatus: nextModerationStatus,
      status: nextStatus,
      updatedAt: committedAt.toISOString(),
    };
  });
}

function guideWorkflowUpdate(
  action: GuideWorkflowAction,
  article: GuideArticleWorkflowSnapshot,
  actorUid: string,
  committedAt: Date
) {
  const timestamp = Timestamp.fromDate(committedAt);

  switch (action) {
    case "submit":
      assertDraftArticle(article);
      return {
        moderationStatus: "pendingReview" as GuideModerationStatus,
        status: "review" as GuideArticleStatus,
        data: {
          moderationStatus: "pendingReview",
          status: "review",
          updatedAt: timestamp,
          updatedBy: actorUid,
        },
      };
    case "approve":
      assertReviewArticle(article);
      return {
        moderationStatus: "approved" as GuideModerationStatus,
        status: "approved" as GuideArticleStatus,
        data: {
          moderationStatus: "approved",
          status: "approved",
          reviewedBy: actorUid,
          lastReviewedAt: timestamp,
          updatedAt: timestamp,
          updatedBy: actorUid,
        },
      };
    case "publish": {
      assertApprovedArticle(article);
      const nextReviewAt = Timestamp.fromDate(nextReviewDate(committedAt, article.reviewInterval));

      return {
        moderationStatus: "approved" as GuideModerationStatus,
        status: "published" as GuideArticleStatus,
        data: {
          status: "published",
          publishedAt: timestamp,
          lastReviewedAt: timestamp,
          nextReviewAt,
          updatedAt: timestamp,
          updatedBy: actorUid,
        },
      };
    }
    case "archive":
      assertArchivableArticle(article);
      return {
        moderationStatus: "archived" as GuideModerationStatus,
        status: "archived" as GuideArticleStatus,
        data: {
          moderationStatus: "archived",
          status: "archived",
          archivedAt: timestamp,
          updatedAt: timestamp,
          updatedBy: actorUid,
        },
      };
  }
}

function assertArchivableArticle(article: GuideArticleWorkflowSnapshot): void {
  assertNotArchived(article);

  const isDraft = article.moderationStatus === "draft"
    && (article.status === undefined || article.status === "draft");
  const isApproved = article.moderationStatus === "approved" && article.status === "approved";
  const isPublished = article.moderationStatus === "approved" && article.status === "published";

  if (!isDraft && !isApproved && !isPublished) {
    throw new HttpsError("failed-precondition", "Guide article is not archivable.");
  }
}

export const submitGuideArticleForReview = createGuideWorkflowCallable("submit");
export const approveGuideArticle = createGuideWorkflowCallable("approve");
export const publishGuideArticle = createGuideWorkflowCallable("publish");
export const archiveGuideArticle = createGuideWorkflowCallable("archive");
