import {type DocumentData, type DocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {isActiveUser} from "../permissions/userPermissions";
import {adminSearchDocuments, adminSearchFields, normalizeAdminSearch} from "../users/adminUserSearch";
import {userDocumentMatchesSearch} from "../users/userManagementQueries";
import {type AudienceUser, identifier, text} from "./contract";

export function recipient(document: DocumentSnapshot) {
  const data = document.data();
  if (!data) return {id: document.id, name: document.id, email: null, region: null, available: false};
  return {id: document.id, name: data.displayName || data.fullName || data.email || document.id,
    email: data.email ?? null, region: data.selectedFederalState ?? null,
    available: isActiveUser({uid: document.id, ...data})};
}

/** Page through the existing server-owned index. Close the stream after one page.
 * Cursor belongs to this query; no loaded-client-only search or offset scans. */
export async function searchRecipients(queryValue: unknown, cursorValue: unknown) {
  const query = normalizeAdminSearch(queryValue == null ? "" : text(queryValue, 120, true));
  let after = "";
  if (cursorValue) {
    try {
      const parsed = JSON.parse(Buffer.from(text(cursorValue, 2000), "base64url").toString());
      if (parsed.query !== query) throw Error();
      after = identifier(parsed.after);
    } catch { throw new HttpsError("invalid-argument", "Restart the recipient search."); }
  }
  const items: ReturnType<typeof recipient>[] = [];
  let more = false, scanned = 0, last = after;
  const fields = [...adminSearchFields, "accountStatus", "blockState", "isBlocked", "uid"];
  for await (const document of adminSearchDocuments(db, query, fields, "automatic", undefined, after || undefined)) {
    const item = recipient(document);
    if (item.available && (!query || userDocumentMatchesSearch(document.id, document.data(), query))) {
      if (items.length === 50) { more = true; break; }
      items.push(item);
    }
    last = document.id;
    // A pathological broad query must not consume the entire user collection in
    // one callable. The cursor advances over inspected candidates, including an
    // empty result page, so no matching account is silently lost.
    if (++scanned >= 250) { more = true; break; }
  }
  return {items, cursor: more ? Buffer.from(JSON.stringify({query, after: last})).toString("base64url") : null};
}

/** Reuse the page's profile snapshots. Only selected organization-role groups
 * require organization queries, in batches of 30 IDs instead of 3 reads per user. */
export async function audiencePage(documents: DocumentSnapshot[], groups: readonly string[]): Promise<AudienceUser[]> {
  const users = documents.filter(d => d.exists && isActiveUser({uid: d.id, ...d.data()}));
  const roles = new Map(users.map(d => [d.id, new Set<string>()]));
  const specifications = [
    ["organizationOwners", "ownerId", "in", "communityOwner"],
    ["organizationAdmins", "adminIds", "array-contains-any", "communityAdmin"],
    ["organizationModerators", "moderatorIds", "array-contains-any", "communityModerator"],
  ] as const;
  for (let offset = 0; offset < users.length; offset += 30) {
    const ids = users.slice(offset, offset + 30).map(d => d.id);
    await Promise.all(specifications.filter(([group]) => !groups.includes("registered") && groups.includes(group)).map(async ([, field, operator, role]) => {
      const snapshot = await db.collection("organizations").where(field, operator, ids).select(field).get();
      for (const doc of snapshot.docs) {
        const value: DocumentData[string] = doc.get(field);
        for (const id of typeof value === "string" ? [value] : Array.isArray(value) ? value : []) roles.get(id)?.add(role);
      }
    }));
  }
  return users.map(d => ({uid: d.id, region: d.get("selectedFederalState"), globalRole: d.get("globalRole"), organizationRoles: [...roles.get(d.id)!]}));
}
