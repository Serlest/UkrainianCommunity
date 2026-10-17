import {createHash} from "node:crypto";
import {isDeepStrictEqual} from "node:util";

type RecordValue = Record<string, unknown>;

export interface DirectoryAutomationCandidate {
  categoryId: string;
  topicId: string;
  sectionId: string;
  federalState?: string;
  expectedRevision: number;
  previousPayloadSHA256: string;
  nextPayload: string;
  changeClass: "official-contact";
  field: "source.url" | "phoneNumber";
  newValue: string;
  evidence: {
    url: string;
    authority: string;
    observedAt: string;
    excerpt: string;
  };
}

const states = new Set([
  "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg",
  "steiermark", "tirol", "vorarlberg", "wien",
]);
const officialHosts = new Set([
  "ris.bka.gv.at", "www.ris.bka.gv.at", "oesterreich.gv.at", "www.oesterreich.gv.at",
  "bfa.gv.at", "www.bfa.gv.at", "bmi.gv.at", "www.bmi.gv.at",
  "ams.at", "www.ams.at",
]);

function object(value: unknown, label: string): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object.`);
  }
  return value as RecordValue;
}

export function officialDirectoryURL(value: string, label: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${label} must be a valid URL.`);
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port ||
      !officialHosts.has(url.hostname.toLowerCase())) {
    throw new Error(`${label} must be an approved official HTTPS URL.`);
  }
  return url;
}

function findById(items: unknown, id: string, label: string): RecordValue {
  if (!Array.isArray(items)) throw new Error(`${label} list is missing.`);
  const item = items.find((entry) => object(entry, label).id === id);
  if (!item) throw new Error(`${label} ${id} does not exist.`);
  return object(item, label);
}

function targetSection(category: RecordValue, candidate: DirectoryAutomationCandidate): RecordValue {
  if (category.id !== candidate.categoryId || category.isHidden === true) {
    throw new Error("Category ID or visibility changed.");
  }
  const topic = findById(category.topics, candidate.topicId, "topic");
  if (topic.isHidden === true) throw new Error("Hidden topic cannot be autopublished.");
  const group = findById(category.groups, String(topic.groupID), "group");
  if (group.isHidden === true) throw new Error("Hidden group cannot be autopublished.");
  let sections = topic.sections;
  if (candidate.federalState !== undefined) {
    if (!states.has(candidate.federalState)) throw new Error("Unknown federal state.");
    sections = object(topic.regionalSections, "regionalSections")[candidate.federalState];
  }
  const section = findById(sections, candidate.sectionId, "section");
  if (section.isHidden === true) throw new Error("Hidden section cannot be autopublished.");
  return section;
}

export function payloadSHA256(payload: string): string {
  return createHash("sha256").update(payload, "utf8").digest("hex");
}

/** Only a single, directly evidenced contact/link field can pass unattended. */
export function validateAutomaticDirectoryChange(
  candidate: DirectoryAutomationCandidate,
  previousPayload: string,
  currentRevision: number,
  now = new Date()
): {nextPayload: string; oldValue: string; newValue: string} {
  if (!candidate || candidate.changeClass !== "official-contact" ||
      !["source.url", "phoneNumber"].includes(candidate.field) ||
      !Number.isSafeInteger(candidate.expectedRevision) || candidate.expectedRevision < 1 ||
      candidate.expectedRevision !== currentRevision) {
    throw new Error("Unsupported class, field, or stale revision.");
  }
  if (payloadSHA256(previousPayload) !== candidate.previousPayloadSHA256) {
    throw new Error("Published payload changed since candidate preparation.");
  }
  const evidence = object(candidate.evidence, "evidence");
  officialDirectoryURL(String(evidence.url), "Evidence URL");
  if (typeof evidence.authority !== "string" || evidence.authority.trim().length < 3 ||
      typeof evidence.excerpt !== "string" || evidence.excerpt.trim().length < 20 ||
      evidence.excerpt.length > 1500) {
    throw new Error("Authority or direct evidence excerpt is insufficient.");
  }
  const observed = Date.parse(String(evidence.observedAt));
  if (!Number.isFinite(observed) || observed > now.getTime() + 60_000 ||
      observed < now.getTime() - 7 * 86_400_000) {
    throw new Error("Official evidence is outside the seven-day window.");
  }
  if (typeof candidate.newValue !== "string" || !candidate.newValue.trim()) {
    throw new Error("New value is missing.");
  }
  const before = object(JSON.parse(previousPayload), "previous category");
  const next = object(JSON.parse(candidate.nextPayload), "next category");
  const beforeSection = targetSection(before, candidate);
  const nextSection = targetSection(next, candidate);
  let oldValue: unknown;
  if (candidate.field === "source.url") {
    const oldSource = object(beforeSection.source, "existing section source");
    const nextSource = object(nextSection.source, "next section source");
    oldValue = oldSource.url;
    officialDirectoryURL(candidate.newValue, "New source URL");
    if (candidate.newValue !== evidence.url) {
      throw new Error("New source URL must be the directly checked evidence URL.");
    }
    if (nextSource.url !== candidate.newValue) {
      throw new Error("Declared value does not match the next section source.");
    }
    nextSource.url = oldValue;
  } else {
    oldValue = beforeSection.phoneNumber;
    if (!/^[0-9 +()/-]{5,40}$/.test(candidate.newValue)) {
      throw new Error("Phone number has an invalid format.");
    }
    if (!evidence.excerpt.includes(candidate.newValue)) {
      throw new Error("Phone number is absent from the evidence excerpt.");
    }
    if (nextSection.phoneNumber !== candidate.newValue) {
      throw new Error("Declared value does not match the next section phone.");
    }
    if (oldValue === undefined) delete nextSection.phoneNumber;
    else nextSection.phoneNumber = oldValue;
  }
  if (typeof oldValue !== "string" && oldValue !== undefined) {
    throw new Error("Existing value has an invalid type.");
  }
  if (oldValue === candidate.newValue || !isDeepStrictEqual(before, next)) {
    throw new Error("Candidate changes more than one permitted field or makes no change.");
  }
  return {nextPayload: candidate.nextPayload, oldValue: String(oldValue ?? ""), newValue: candidate.newValue};
}
