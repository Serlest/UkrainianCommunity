import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";

const MAXIMUM_COMMENT_LENGTH = 1_000;
const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: false,
};

const parentCollections = {
  news: "news",
  event: "events",
  organization: "organizations",
} as const;

type CommentParentType = keyof typeof parentCollections;

interface SaveCommentRequest {
  parentType?: unknown;
  parentId?: unknown;
  text?: unknown;
}

export type CommentRejectionReason =
  | "threat"
  | "hate"
  | "sexual-exploitation"
  | "spam";

const disallowedPatterns: ReadonlyArray<{
  reason: CommentRejectionReason;
  pattern: RegExp;
}> = [
  {
    reason: "threat",
    pattern: /(?:kill\s+(?:you|yourself)|i(?:'|’)ll\s+kill|t[oö]te\s+dich|ich\s+bringe\s+dich\s+um|убью|убити|вб(?:'|’)ю|сдохни|помри)/iu,
  },
  {
    reason: "hate",
    pattern: /(?:n[i1]gg(?:er|a)|k[i1]ke|f[a4]gg?[o0]t|хохол|жид|чурка|москаль)/iu,
  },
  {
    reason: "sexual-exploitation",
    pattern: /(?:child\s*porn|child\s*sex|kinderporno|kindersex|дитяче\s+порно|детское\s+порно|секс\s+з\s+дитиною|секс\s+с\s+ребенком)/iu,
  },
];

function normalizedForModeration(text: string): string {
  return text
    .normalize("NFKC")
    .replace(/[\u200B-\u200D\u2060\uFEFF]/gu, "")
    .toLocaleLowerCase("und")
    .replace(/[._*~`|\\\-]+/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

export function classifyCommentText(text: string): CommentRejectionReason | null {
  const normalized = normalizedForModeration(text);
  for (const candidate of disallowedPatterns) {
    if (candidate.pattern.test(normalized)) return candidate.reason;
  }

  const links = normalized.match(/(?:https?:\/\/|www\.)\S+/gu) ?? [];
  const contactSolicitations = normalized.match(/\b(?:telegram|whatsapp|signal|viber)\b/gu) ?? [];
  if (links.length >= 3 || (links.length >= 2 && contactSolicitations.length >= 1)) {
    return "spam";
  }
  return null;
}

function requiredString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return trimmed;
}

function parseRequest(data: SaveCommentRequest): {
  parentType: CommentParentType;
  parentId: string;
  text: string;
} {
  if (typeof data.parentType !== "string" || !(data.parentType in parentCollections)) {
    throw new HttpsError("invalid-argument", "parentType is invalid.");
  }
  const parentType = data.parentType as CommentParentType;
  const parentId = requiredString(data.parentId, "parentId", 256);
  const text = requiredString(data.text, "text", MAXIMUM_COMMENT_LENGTH);
  const rejectionReason = classifyCommentText(text);
  if (rejectionReason) {
    throw new HttpsError(
      "invalid-argument",
      "The comment contains content that cannot be published.",
      {reason: "objectionable-content", category: rejectionReason}
    );
  }
  return {parentType, parentId, text};
}

function profileDisplayName(data: FirebaseFirestore.DocumentData | undefined): string {
  for (const candidate of [data?.displayName, data?.fullName]) {
    if (typeof candidate === "string" && candidate.trim()) return candidate.trim().slice(0, 160);
  }
  return "User";
}

function optionalAvatarURL(data: FirebaseFirestore.DocumentData | undefined): string | null {
  const value = data?.avatarURL;
  return typeof value === "string" && value.length <= 2_048 ? value : null;
}

function isoDate(timestamp: Timestamp | null): string | null {
  return timestamp?.toDate().toISOString() ?? null;
}

export const saveComment = onCall(callableOptions, async (request) => {
  const actor = await requireVerifiedActiveUser(request);
  const input = parseRequest((request.data ?? {}) as SaveCommentRequest);
  const parentReference = db.collection(parentCollections[input.parentType]).doc(input.parentId);
  const profileReference = db.collection("users").doc(actor.uid);
  const commentReference = parentReference.collection("comments").doc();

  const result = await db.runTransaction(async (transaction) => {
    const [parentSnapshot, profileSnapshot] = await Promise.all([
      transaction.get(parentReference),
      transaction.get(profileReference),
    ]);

    if (!parentSnapshot.exists || parentSnapshot.get("moderationStatus") !== "approved") {
      throw new HttpsError("not-found", "The content is not available for comments.");
    }

    const now = Timestamp.now();
    const profile = profileSnapshot.data();
    const comment = {
      id: commentReference.id,
      parentType: input.parentType,
      parentId: input.parentId,
      authorId: actor.uid,
      authorName: profileDisplayName(profile),
      authorPhotoURL: optionalAvatarURL(profile),
      text: input.text,
      body: input.text,
      createdAt: now,
      updatedAt: null,
      moderationStatus: "approved",
      isDeleted: false,
    };
    transaction.create(commentReference, comment);
    return comment;
  });

  return {
    id: result.id,
    parentType: result.parentType,
    parentId: result.parentId,
    authorId: result.authorId,
    authorName: result.authorName,
    authorPhotoURL: result.authorPhotoURL,
    text: result.text,
    createdAt: isoDate(result.createdAt),
    updatedAt: isoDate(result.updatedAt),
    moderationStatus: result.moderationStatus,
    isDeleted: result.isDeleted,
  };
});
