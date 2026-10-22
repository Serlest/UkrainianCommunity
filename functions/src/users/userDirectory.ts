import {createHash} from "node:crypto";
import {type Readable} from "node:stream";
import {Timestamp, FieldPath, type DocumentData, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertCanManageUsers} from "../permissions/userPermissions";
import {canManageOrganizationRoles} from "../permissions/organizationPermissions";
import {adminSearchDocuments, adminSearchFields, collectAdminSearch, normalizeAdminSearch} from "./adminUserSearch";
import {managedUserMatchesRegion, userDocumentMatchesSearch} from "./userManagementQueries";

const filters = ["all", "active", "warned", "suspended", "banned", "deactivated", "organizationOwners", "organizationAdmins", "organizationModerators"];
const sorts = ["newest", "oldest", "nameAscending", "nameDescending"];
const regions = ["burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien", "unknown"];
const roleField: Record<string, string> = {organizationOwners: "ownerId", organizationAdmins: "adminIds", organizationModerators: "moderatorIds"};
function text(value: unknown, max = 120): string {
  if (value == null) return "";
  if (typeof value !== "string" || value.length > max) throw new HttpsError("invalid-argument", "Invalid text.");
  return value.trim();
}
function id(value: unknown): string { const result = text(value,128); if (!result || result.includes("/")) throw new HttpsError("invalid-argument", "Invalid ID."); return result; }
export function directoryStatus(data: DocumentData): string {
  const rank: Record<string, number> = {active:0,warned:1,suspendedUntil:2,temporarilyBanned:2,blocked:2,bannedPermanent:3,permanentlyBanned:3,deactivated:4};
  const value = Math.max(rank[data.accountStatus] ?? 0,rank[data.blockState] ?? (data.isBlocked === true ? 2 : 0));
  return ["active","warned","suspended","banned","deactivated"][value];
}
function organization(document: QueryDocumentSnapshot) {
  const data = document.data(), time = data.updatedAt;
  return {id:document.id,name:data.name || document.id,city:data.city || "",logoURL:data.logoURL ?? data.imageURL ?? null,
    ownerId:data.ownerId ?? null,adminIds:data.adminIds ?? [],moderatorIds:data.moderatorIds ?? [],
    accessRevision:time?.seconds !== undefined ? `${time.seconds}:${time.nanoseconds}` : null,
    moderationStatus:data.moderationStatus ?? "draft"};
}
type Cursor = {signature:string; key:number|string; id:string};
function decodeCursor(raw: unknown, signature: string): Cursor | undefined {
  if (raw == null) return;
  try {
    const cursor = JSON.parse(Buffer.from(text(raw,2000),"base64url").toString()) as Cursor;
    if (cursor.signature !== signature || !cursor.id || cursor.id.includes("/") || cursor.id.length > 128 || !["string","number"].includes(typeof cursor.key)) throw Error();
    return cursor;
  } catch { throw new HttpsError("invalid-argument", "The filter changed. Restart the list."); }
}
export const manageUserDirectory = onCall({region:"europe-west3",maxInstances:10,enforceAppCheck:false},async request => {
  const auth = await requireVerifiedActiveUser(request); assertCanManageUsers(auth.permissions);
  const data = request.data ?? {};
  if (data.principalId !== auth.uid) throw new HttpsError("permission-denied","Account changed.");
  if (data.action === "memberships") {
    const uid = id(data.userId);
    const snapshots = await Promise.all([db.collection("organizations").where("ownerId","==",uid).get(),db.collection("organizations").where("adminIds","array-contains",uid).get(),db.collection("organizations").where("moderatorIds","array-contains",uid).get()]);
    const unique = new Map(snapshots.flatMap(s=>s.docs).map(d=>[d.id,d]));
    return {organizations:[...unique.values()].map(organization).sort((a,b)=>a.name.localeCompare(b.name)||a.id.localeCompare(b.id))};
  }
  if (data.action === "organizations") {
    const search = normalizeAdminSearch(text(data.query)), cursor = data.cursor ? id(data.cursor) : undefined;
    const items: ReturnType<typeof organization>[] = []; let next: string | null = null;
    // Stream only compact organization metadata; retain at most one page.
    const base = db.collection("organizations").orderBy(FieldPath.documentId());
    const stream = (cursor ? base.startAfter(cursor) : base).select("name","city","logoURL","ownerId","adminIds","moderatorIds","updatedAt","moderationStatus").stream();
    for await (const value of stream as Readable) {
      const document = value as QueryDocumentSnapshot;
      const d = document.data();
      if (!["approved","pendingReview","needsRevision","rejected"].includes(d.moderationStatus) || !canManageOrganizationRoles(auth.permissions,{organizationId:document.id,ownerId:d.ownerId,adminIds:d.adminIds??[],moderatorIds:d.moderatorIds??[]})) continue;
      if (search && !search.split(" ").every(token=>normalizeAdminSearch(`${d.name??""} ${d.city??""} ${document.id}`).includes(token))) continue;
      if (items.length === 30) { next = items.at(-1)!.id; (stream as Readable).destroy(); break; }
      items.push(organization(document));
    }
    return {organizations:items,cursor:next};
  }
  if (data.action !== "list") throw new HttpsError("invalid-argument","Invalid action.");
  const query = normalizeAdminSearch(text(data.query)), region = text(data.region), filter = data.filter ?? "all", sort = data.sort ?? "newest";
  if (!filters.includes(filter) || !sorts.includes(sort) || region && !regions.includes(region)) throw new HttpsError("invalid-argument","Invalid filter.");
  const signature = createHash("sha256").update(JSON.stringify([auth.uid,query,region,filter,sort])).digest("hex");
  const cursor = decodeCursor(data.cursor,signature);
  if (cursor && (!sort.startsWith("name") && !/^\d{12}:\d{9}$/.test(String(cursor.key)) || sort.startsWith("name") && typeof cursor.key !== "string")) throw new HttpsError("invalid-argument","Invalid cursor value.");
  const ascending = sort === "oldest" || sort === "nameAscending";
  const key = (document: QueryDocumentSnapshot): number|string => sort.startsWith("name")
    ? normalizeAdminSearch(document.get("displayName") || document.get("fullName") || document.id)
    : document.get("createdAt")?.seconds !== undefined ? `${String(document.get("createdAt").seconds).padStart(12,"0")}:${String(document.get("createdAt").nanoseconds).padStart(9,"0")}` : "000000000000:000000000";
  const compare = (left: {key:number|string;id:string},right:{key:number|string;id:string}) => {
    const order = left.key < right.key ? -1 : left.key > right.key ? 1 : 0;
    return (ascending ? order : -order) || (left.id < right.id ? -1 : left.id > right.id ? 1 : 0);
  };
  let items: QueryDocumentSnapshot[] = [], total = 0, hasMore = false, indexedPage = false;
  // The common unfiltered chronological list uses an indexed page + aggregate,
  // rather than streaming every account on every next-page request.
  if (!query && filter === "all" && !sort.startsWith("name") && region !== "unknown") {
    let base = db.collection("users").orderBy("createdAt",ascending?"asc":"desc").orderBy(FieldPath.documentId());
    if (region) base = base.where("selectedFederalState","==",region);
    const pageQuery = cursor ? base.startAfter(new Timestamp(...String(cursor.key).split(":").map(Number) as [number,number]),cursor.id) : base;
    try {
      const [page,count] = await Promise.all([pageQuery.limit(41).get(),base.count().get()]);
      items = page.docs.slice(0,40); total = count.data().count; hasMore = page.size > 40; indexedPage = true;
    } catch (error) {
      if ((error as {code?:number}).code !== 9) throw error;
      // An index building in production must not prevent an authorized read.
    }
  }
  if (!indexedPage) {
    let members: Set<string> | undefined;
    if (roleField[filter]) {
      members = new Set(); const field = roleField[filter];
      const stream = db.collection("organizations").select("ownerId","adminIds","moderatorIds").stream();
      for await (const value of stream as Readable) {
        const doc = value as QueryDocumentSnapshot;
        const fieldValue = doc.get(field);
        for (const uid of Array.isArray(fieldValue)?fieldValue:typeof fieldValue === "string"?[fieldValue]:[]) {
          if (field !== "ownerId" && doc.get("ownerId") === uid || field === "moderatorIds" && (doc.get("adminIds")??[]).includes(uid)) continue;
          members.add(uid);
        }
      }
    }
    total = 0;
    const result = await collectAdminSearch(adminSearchDocuments(db,query,[...adminSearchFields,"createdAt","accountStatus","blockState","isBlocked"],"automatic",region || undefined),document => {
      if (!managedUserMatchesRegion(document.data(),region || undefined) || query && !userDocumentMatchesSearch(document.id,document.data(),query)) return false;
      if (members ? !members.has(document.id) : filter !== "all" && directoryStatus(document.data()) !== filter) return false;
      total++; return !cursor || compare({id:document.id,key:key(document)},cursor) > 0;
    },41,(a,b)=>compare({id:a.id,key:key(a)},{id:b.id,key:key(b)}));
    items = result.items.slice(0,40); hasMore = result.items.length > 40;
  }
  const organizations = new Map<string,ReturnType<typeof organization>>();
  for (let offset=0;offset<items.length;offset+=30) {
    const ids = items.slice(offset,offset+30).map(d=>d.id);
    const pages = await Promise.all([db.collection("organizations").where("ownerId","in",ids).get(),db.collection("organizations").where("adminIds","array-contains-any",ids).get(),db.collection("organizations").where("moderatorIds","array-contains-any",ids).get()]);
    for (const doc of pages.flatMap(p=>p.docs)) organizations.set(doc.id,organization(doc));
  }
  const last = items.at(-1);
  return {organizations:[...organizations.values()],userIds:items.map(d=>d.id),totalMatches:total,cursor:hasMore && last ? Buffer.from(JSON.stringify({signature,key:key(last),id:last.id})).toString("base64url"):null};
});
