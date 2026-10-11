import {HttpsError} from "firebase-functions/v2/https";

type RecordValue = Record<string, unknown>;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function record(value: unknown, fields: string[], label: string): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalid(`${label} must be an object.`);
  }
  const data = value as RecordValue;
  if (Object.keys(data).some((key) => !fields.includes(key))) {
    return invalid(`${label} contains unsupported fields.`);
  }
  return data;
}

function text(value: unknown, max: number, label: string, required = true): string {
  if (typeof value !== "string" || value.length > max ||
      (required && !value.trim())) {
    return invalid(`${label} is invalid.`);
  }
  return value;
}

function id(value: unknown, label: string): string {
  const result = text(value, 64, label);
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(result)) {
    return invalid(`${label} is invalid.`);
  }
  return result;
}

function bilingual(value: unknown, max: number, label: string, required = true): void {
  const fields = record(value, ["ukrainian", "german"], label);
  text(fields.ukrainian, max, `${label}.ukrainian`, required);
  text(fields.german, max, `${label}.german`, required);
}

function integer(value: unknown, label: string): void {
  if (!Number.isInteger(value) || (value as number) < 0 || (value as number) > 1000) {
    invalid(`${label} is invalid.`);
  }
}

function bool(value: unknown, label: string): void {
  if (typeof value !== "boolean") invalid(`${label} is invalid.`);
}

function array(value: unknown, max: number, label: string): unknown[] {
  if (!Array.isArray(value) || value.length > max) {
    return invalid(`${label} is invalid.`);
  }
  return value;
}

function source(value: unknown): void {
  const item = record(value, ["name", "url"], "source");
  text(item.name, 160, "source.name");
  const raw = text(item.url, 1024, "source.url");
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    return invalid("Source URL is invalid.");
  }
  if (parsed.protocol !== "https:" || !parsed.hostname ||
      parsed.username || parsed.password) {
    invalid("Source must use a public HTTPS URL.");
  }
}

function unique(values: string[], label: string): void {
  if (new Set(values).size !== values.length) invalid(`${label} contains duplicate IDs.`);
}

function validateRegionalSections(value: unknown): void {
  const states = record(value, [
    "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg",
    "steiermark", "tirol", "vorarlberg", "wien",
  ], "regionalSections");
  for (const [state, entries] of Object.entries(states)) {
    const sections = array(entries, 40, `regionalSections.${state}`).map((value) => {
      const section = record(value, [
        "id", "order", "isHidden", "title", "body", "symbol",
        "phoneNumber", "source", "contacts",
      ], "regional section");
      const sectionId = id(section.id, "regional section.id");
      integer(section.order, "regional section.order");
      bool(section.isHidden, "regional section.isHidden");
      bilingual(section.title, 160, "regional section.title");
      bilingual(section.body, 6000, "regional section.body", section.isHidden !== true);
      text(section.symbol, 80, "regional section.symbol");
      if (section.phoneNumber !== undefined && section.phoneNumber !== null) {
        text(section.phoneNumber, 40, "regional section.phoneNumber", false);
      }
      if (section.source !== undefined && section.source !== null) source(section.source);
      array(section.contacts, 12, "regional section.contacts").forEach((value) => {
        const contact = record(value, ["number", "title", "detail"], "regional contact");
        const number = text(contact.number, 40, "regional contact.number");
        if (!/^[0-9 +()/-]+$/.test(number)) invalid("Regional contact number is invalid.");
        bilingual(contact.title, 100, "regional contact.title");
        bilingual(contact.detail, 200, "regional contact.detail");
      });
      if (section.isHidden !== true && section.source == null) {
        invalid("Visible regional section requires a source.");
      }
      return sectionId;
    });
    unique(sections, `regionalSections.${state}`);
  }
}

export function validateDirectoryCategoryPayload(payload: string, categoryId: string): void {
  if (Buffer.byteLength(payload, "utf8") > 800_000) invalid("Category is too large.");
  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return invalid("Category payload is not JSON.");
  }
  const category = record(parsed, [
    "id", "placement", "order", "isHidden", "title", "summary", "symbol", "groups", "topics",
  ], "category");
  if (id(category.id, "category.id") !== categoryId) invalid("Category ID mismatch.");
  if (!["start", "life", "support"].includes(String(category.placement))) {
    invalid("Category placement is invalid.");
  }
  integer(category.order, "category.order");
  bool(category.isHidden, "category.isHidden");
  bilingual(category.title, 100, "category.title");
  bilingual(category.summary, 500, "category.summary");
  text(category.symbol, 80, "category.symbol");

  const groups = array(category.groups, 30, "groups").map((value) => {
    const group = record(value, ["id", "title", "order", "isHidden"], "group");
    const groupId = id(group.id, "group.id");
    bilingual(group.title, 100, "group.title");
    integer(group.order, "group.order");
    bool(group.isHidden, "group.isHidden");
    return {id: groupId, hidden: group.isHidden === true};
  });
  unique(groups.map((item) => item.id), "groups");
  const groupIDs = new Set(groups.map((item) => item.id));
  const activeGroups = new Set(groups.filter((item) => !item.hidden).map((item) => item.id));
  const topics = array(category.topics, 100, "topics").map((value) => {
    const topic = record(value, [
      "id", "groupID", "order", "isHidden", "title", "summary", "sections", "sources", "regionalSections",
    ], "topic");
    const topicId = id(topic.id, "topic.id");
    const groupID = id(topic.groupID, "topic.groupID");
    if (!groupIDs.has(groupID)) invalid("Topic group does not exist.");
    integer(topic.order, "topic.order");
    bool(topic.isHidden, "topic.isHidden");
    bilingual(topic.title, 140, "topic.title");
    bilingual(topic.summary, 800, "topic.summary", topic.isHidden !== true);
    const sources = array(topic.sources, 80, "topic.sources");
    sources.forEach(source);
    validateRegionalSections(topic.regionalSections);
    const sections = array(topic.sections, 80, "topic.sections").map((value) => {
      const section = record(value, [
        "id", "order", "isHidden", "title", "body", "symbol",
        "phoneNumber", "source", "contacts",
      ], "section");
      const sectionId = id(section.id, "section.id");
      integer(section.order, "section.order");
      bool(section.isHidden, "section.isHidden");
      bilingual(section.title, 160, "section.title");
      bilingual(section.body, 6000, "section.body", section.isHidden !== true);
      text(section.symbol, 80, "section.symbol");
      if (section.phoneNumber !== undefined && section.phoneNumber !== null) {
        text(section.phoneNumber, 40, "section.phoneNumber", false);
      }
      if (section.source !== undefined && section.source !== null) source(section.source);
      array(section.contacts, 12, "section.contacts").forEach((value) => {
        const contact = record(value, ["number", "title", "detail"], "contact");
        const number = text(contact.number, 40, "contact.number");
        if (!/^[0-9 +()/-]+$/.test(number)) invalid("Contact number is invalid.");
        bilingual(contact.title, 100, "contact.title");
        bilingual(contact.detail, 200, "contact.detail");
      });
      if (section.isHidden !== true && section.source == null && sources.length === 0) {
        invalid("Visible section requires a source.");
      }
      return {id: sectionId, hidden: section.isHidden === true};
    });
    unique(sections.map((item) => item.id), "sections");
    if (topic.isHidden !== true && activeGroups.has(groupID) &&
        sections.every((item) => item.hidden)) {
      invalid("Visible topic requires a visible section.");
    }
    return {id: topicId, hidden: topic.isHidden === true};
  });
  unique(topics.map((item) => item.id), "topics");
  if (category.isHidden !== true && topics.length === 0) {
    invalid("New visible category requires a topic.");
  }
}
