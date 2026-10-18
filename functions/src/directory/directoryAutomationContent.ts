import {createHash} from "node:crypto";
import {isDeepStrictEqual} from "node:util";
import {type DirectoryAutomationCandidate} from "./directoryAutomationPolicy";

type Value = Record<string, any>;

/** The service checks boundaries; the signed-in Codex publisher performs the semantic review. */
export function validateReviewedDirectoryContent(candidate: DirectoryAutomationCandidate,
  before: Value, next: Value, now: Date): void {
  const review = candidate.review;
  if (!review || review.payloadSHA256 !== createHash("sha256").update(candidate.nextPayload).digest("hex") ||
      review.bilingualChecked !== true || review.applicabilityChecked !== true ||
      review.noSourceConflict !== true || typeof review.scope !== "string" || !review.scope.trim()) {
    throw new Error("Content requires review of the exact payload, both languages, applicability and conflicts.");
  }
  const checked = Date.parse(review.reviewedAt);
  if (!Number.isFinite(checked) || checked > now.getTime() + 60_000 ||
      checked < now.getTime() - 86_400_000) throw new Error("Content review is stale.");
  const fragments = [candidate.evidence.excerpt, ...(candidate.evidence.excerpts ?? [])];
  if (!Array.isArray(review.statements) || review.statements.length < 1 || review.statements.length > 20 ||
      review.statements.some((statement) => typeof statement.ukrainian !== "string" ||
        !statement.ukrainian.trim() || typeof statement.german !== "string" || !statement.german.trim() ||
        typeof statement.excerpt !== "string" || !fragments.includes(statement.excerpt))) {
    throw new Error("Each reviewed bilingual statement requires a checked source fragment.");
  }
  if (before.id !== candidate.categoryId || next.id !== candidate.categoryId ||
      before.isHidden === true || next.isHidden === true) throw new Error("Category changed or is hidden.");
  const sourceURL = candidate.evidence.url;
  const checkSection = (section: Value) => {
    if (!section || section.isHidden !== false || section.source?.url !== sourceURL ||
        typeof section.body?.ukrainian !== "string" || !section.body.ukrainian.trim() ||
        typeof section.body?.german !== "string" || !section.body.german.trim()) {
      throw new Error("Visible bilingual content must cite the directly checked source.");
    }
  };
  if (candidate.operation === "add-topic" && candidate.field === "topic") {
    if (candidate.newValue !== candidate.topicId || candidate.federalState !== undefined ||
        before.topics.some((t: Value) => t.id === candidate.topicId)) {
      throw new Error("New topic ID already exists or has invalid region scope.");
    }
    const index = next.topics.findIndex((t: Value) => t.id === candidate.topicId);
    const topic = next.topics[index];
    if (!topic || topic.isHidden !== false || !before.groups.some((g: Value) =>
      g.id === topic.groupID && g.isHidden === false) || !topic.sections.length ||
      Object.keys(topic.regionalSections ?? {}).length ||
      topic.sources.some((source: Value) => source.url !== sourceURL)) {
      throw new Error("New topic must use an existing visible group and one checked source.");
    }
    topic.sections.forEach(checkSection);
    next.topics.splice(index, 1);
  } else if (["add-section", "replace-section"].includes(candidate.operation ?? "") && candidate.field === "section") {
    const oldTopic = before.topics.find((t: Value) => t.id === candidate.topicId);
    const newTopic = next.topics.find((t: Value) => t.id === candidate.topicId);
    if (!oldTopic || !newTopic || oldTopic.isHidden !== false ||
        !before.groups.some((g: Value) => g.id === oldTopic.groupID && g.isHidden === false)) {
      throw new Error("Target topic or group is unavailable.");
    }
    const region = candidate.federalState;
    const oldSections: Value[] = region === undefined ? oldTopic.sections : oldTopic.regionalSections?.[region];
    const newSections: Value[] = region === undefined ? newTopic.sections : newTopic.regionalSections?.[region];
    if (!Array.isArray(oldSections) || !Array.isArray(newSections)) throw new Error("Target section list is missing.");
    const oldIndex = oldSections.findIndex((s) => s.id === candidate.sectionId);
    const newIndex = newSections.findIndex((s) => s.id === candidate.sectionId);
    const section = newSections[newIndex];
    checkSection(section);
    if (candidate.newValue !== candidate.sectionId) throw new Error("Declared section does not match target.");
    if (candidate.operation === "add-section") {
      if (oldIndex !== -1) throw new Error("New section ID already exists.");
      newSections.splice(newIndex, 1);
    } else {
      if (oldIndex === -1 || oldSections[oldIndex].isHidden !== false ||
          newIndex !== oldIndex || section.order !== oldSections[oldIndex].order ||
          isDeepStrictEqual(section, oldSections[oldIndex])) throw new Error("Correction target changed or makes no change.");
      newSections[newIndex] = oldSections[oldIndex];
    }
    // Only one source addition alongside the reviewed block is permitted.
    if (!oldTopic.sources.some((source: Value) => source.url === sourceURL)) {
      const additions = newTopic.sources.filter((source: Value) => source.url === sourceURL);
      if (additions.length !== 1) throw new Error("Reviewed source is missing or duplicated.");
      newTopic.sources = newTopic.sources.filter((source: Value) => source.url !== sourceURL);
    }
  } else {
    throw new Error("Unsupported reviewed content operation.");
  }
  if (!isDeepStrictEqual(before, next)) throw new Error("Content candidate changes unrelated category fields.");
}
