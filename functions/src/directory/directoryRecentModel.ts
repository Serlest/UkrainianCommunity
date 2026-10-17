import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {directoryRecentBaseline} from "./directoryRecentBaseline";

export interface DirectoryText {ukrainian: string; german: string;}
export interface RecentMaterial {
  id: string; kind: "topic" | "section"; categoryID: string; topicID: string;
  sectionID: string | null; federalState: string | null;
  title: DirectoryText; topicTitle: DirectoryText; categoryTitle: DirectoryText;
  visible: boolean;
}
interface Section {id: string; isHidden: boolean; title: DirectoryText;}
interface Topic extends Section {
  groupID: string; sections: Section[]; regionalSections: Record<string, Section[]>;
}
interface Category extends Section {groups: Section[]; topics: Topic[];}

export function materialID(kind: string, category: string, topic: string, section = "", region = ""): string {
  return createHash("sha256").update(JSON.stringify([kind, category, topic, section, region])).digest("hex");
}

/** Input is validated by the category publisher before this projection is built. */
export function directoryMaterials(payload: string): RecentMaterial[] {
  const category = JSON.parse(payload) as Category;
  const groups = new Set(category.groups.filter((g) => !g.isHidden).map((g) => g.id));
  const result: RecentMaterial[] = [];
  for (const topic of category.topics) {
    const visible = !category.isHidden && !topic.isHidden && groups.has(topic.groupID);
    const base = {categoryID: category.id, topicID: topic.id, topicTitle: topic.title, categoryTitle: category.title};
    result.push({...base, id: materialID("topic", category.id, topic.id), kind: "topic",
      sectionID: null, federalState: null, title: topic.title, visible});
    const add = (sections: Section[], region: string | null) => {
      for (const section of sections) result.push({...base,
        id: materialID("section", category.id, topic.id, section.id, region ?? ""), kind: "section",
        sectionID: section.id, federalState: region, title: section.title, visible: visible && !section.isHidden});
    };
    add(topic.sections, null);
    for (const [region, sections] of Object.entries(topic.regionalSections)) add(sections, region);
  }
  return result;
}

export function planDirectoryAdditions(categoryID: string, previousPayload: string | undefined,
  nextPayload: string, previousKnown: readonly string[] | undefined): {knownIDs: string[]; additions: RecentMaterial[]} {
  // Bootstrap the previously published snapshot and bundle as history, never as "new today".
  const known = new Set(previousKnown ?? [
    ...(directoryRecentBaseline[categoryID] ?? []),
    ...(previousPayload ? directoryMaterials(previousPayload).map((m) => m.id) : []),
  ]);
  const next = directoryMaterials(nextPayload);
  const candidates = next.filter((m) => m.visible && !known.has(m.id));
  const newTopics = new Set(candidates.filter((m) => m.kind === "topic").map((m) => m.topicID));
  const additions = candidates.filter((m) => m.kind === "topic" || !newTopics.has(m.topicID));
  for (const material of next) if (material.visible) known.add(material.id);
  if (additions.length > 400 || known.size > 10_000) {
    throw new HttpsError("resource-exhausted", "Directory publication exceeds the recent-material journal limit.");
  }
  return {knownIDs: [...known].sort(), additions};
}
