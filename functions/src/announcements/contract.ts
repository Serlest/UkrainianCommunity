import {HttpsError} from "firebase-functions/v2/https";

export const groups = ["registered", "guests", "organizationOwners", "appAdmins", "organizationAdmins", "organizationModerators"] as const;
export const regions = ["burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien"] as const;
export type Group = typeof groups[number];
export interface Announcement {
  id: string; schemaVersion: 1; revision: number;
  title: {uk: string; de: string}; body: {uk: string; de: string};
  groups: Group[]; userIds: string[]; regions: string[]; targetPlatforms: string[];
  mode: "once" | "acknowledge"; feedback: boolean; push: boolean;
  startsAt: number; expiresAt: number; status: "draft" | "published" | "cancelled";
  createdAt: number; updatedAt: number; authorId: string;
}
export interface AudienceUser {
  uid: string; region?: string; globalRole?: string; organizationRoles: string[];
}
export const fail = (message: string): never => { throw new HttpsError("invalid-argument", message); };
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return fail("Expected an object.");
  return value as Record<string, unknown>;
}
export function text(value: unknown, max: number, empty = false): string {
  if (typeof value !== "string" || value.length > max || (!empty && !value.trim())) return fail("Invalid text length.");
  return value.trim();
}
export function identifier(value: unknown): string {
  const result = text(value, 128);
  if (!/^[A-Za-z0-9_-]+$/.test(result)) return fail("Invalid identifier.");
  return result;
}
function strings(value: unknown, max: number): string[] {
  if (!Array.isArray(value) || value.length > max) return fail("Invalid selection.");
  return [...new Set(value.map((item) => text(item, 128)))];
}
export function parseDraft(value: unknown, uid: string, now: number): Announcement {
  const v = record(value), title = record(v.title), body = record(v.body);
  const selectedGroups = strings(v.groups, groups.length);
  const selectedRegions = strings(v.regions, regions.length);
  const platforms = strings(v.targetPlatforms, 2);
  const userIds = strings(v.userIds, 100).map(identifier);
  if (selectedGroups.some((g) => !(groups as readonly string[]).includes(g)) ||
      selectedRegions.some((r) => !(regions as readonly string[]).includes(r)) ||
      platforms.length === 0 || platforms.some((p) => !["ios", "android"].includes(p))) return fail("Invalid audience.");
  if (!selectedGroups.length && !userIds.length) return fail("Select recipients.");
  if (v.mode !== "once" && v.mode !== "acknowledge") return fail("Invalid display mode.");
  if (typeof v.feedback !== "boolean" || typeof v.push !== "boolean") return fail("Invalid options.");
  if (typeof v.startsAt !== "number" || typeof v.expiresAt !== "number" ||
      !Number.isSafeInteger(v.startsAt) || !Number.isSafeInteger(v.expiresAt) ||
      v.expiresAt <= Math.max(v.startsAt, now) || v.expiresAt - v.startsAt > 90 * 86400000) return fail("Choose a validity period of up to 90 days.");
  return {id: identifier(v.id), schemaVersion: 1, revision: 1,
    title: {uk: text(title.uk, 160, true), de: text(title.de, 160, true)},
    body: {uk: text(body.uk, 6000, true), de: text(body.de, 6000, true)},
    groups: selectedGroups as Group[], regions: selectedRegions, userIds, targetPlatforms: platforms,
    mode: v.mode, feedback: v.feedback, push: v.push, startsAt: v.startsAt, expiresAt: v.expiresAt,
    status: "draft", authorId: uid, createdAt: now, updatedAt: now};
}
export function assertPublishable(a: Announcement, now: number): void {
  if (a.expiresAt <= now || !a.title.uk || !a.title.de || !a.body.uk || !a.body.de) fail("Complete both languages and the validity period.");
  if (a.targetPlatforms.some((p) => p !== "ios")) fail("Android announcements are not enabled yet.");
}
export function matchesAudience(a: Announcement, user?: AudienceUser): boolean {
  if (!user) return a.groups.includes("guests");
  if (a.regions.length && (!user.region || !a.regions.includes(user.region))) return false;
  return a.userIds.includes(user.uid) || a.groups.includes("registered") ||
    (a.groups.includes("appAdmins") && user.globalRole === "admin") ||
    (a.groups.includes("organizationOwners") && user.organizationRoles.includes("communityOwner")) ||
    (a.groups.includes("organizationAdmins") && user.organizationRoles.includes("communityAdmin")) ||
    (a.groups.includes("organizationModerators") && user.organizationRoles.includes("communityModerator"));
}
export function supports(a: Announcement, platform: unknown, capability: unknown): boolean {
  return platform === "ios" && capability === 1 && a.targetPlatforms.includes(platform);
}
export function isActive(a: Announcement, now: number): boolean {
  return a.status === "published" && a.startsAt <= now && a.expiresAt > now;
}
export function publicAnnouncement(a: Announcement) {
  return {id: a.id, schemaVersion: a.schemaVersion, revision: a.revision, title: a.title, body: a.body,
    mode: a.mode, feedback: a.feedback, status: a.status, startsAt: a.startsAt, expiresAt: a.expiresAt};
}
