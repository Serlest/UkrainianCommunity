/* global console, process */

import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {fileURLToPath, URL} from "node:url";
import {cert, getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const repositoryRoot = fileURLToPath(new URL("../../", import.meta.url));
const manifest = JSON.parse(
  readFileSync(new URL("../../Legal/legal-manifest.json", import.meta.url), "utf8"),
);
const STATUS = "published";
const DEFAULT_LOCALE = manifest.canonicalLocale;
const CANONICAL_LOCALE = manifest.canonicalLocale;
const SEED_ACTOR = "legal-seed-script";
const documentVersion = (type) => manifest.documents[type].version ?? manifest.version;
const documentVersionNumber = (type) => Number(documentVersion(type).replace(".", ""));

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isDryRun = args.has("--dry-run");
const isVerify = args.has("--verify");
const isForce = args.has("--force");
const projectIdArg = valueForFlag("--project-id");
const serviceAccountPath = valueForFlag("--service-account");

function readCanonicalDocument(type, locale) {
  const relativePath = manifest.documents?.[type]?.files?.[locale];
  if (typeof relativePath !== "string") {
    throw new Error(`Missing legal source path for ${type}.${locale}.`);
  }
  const source = readFileSync(`${repositoryRoot}/${relativePath}`, "utf8");
  const lines = source.replaceAll("\r\n", "\n").split("\n");
  const titleLine = lines.find((line) => line.startsWith("# "));
  if (!titleLine) {
    throw new Error(`Missing document title in ${relativePath}.`);
  }
  const firstSection = lines.findIndex((line) => line.startsWith("## "));
  if (firstSection < 0) {
    throw new Error(`Missing sections in ${relativePath}.`);
  }
  const contentMarkdown = [titleLine, "", ...lines.slice(firstSection)]
    .join("\n")
    .trim();
  return {
    title: titleLine.slice(2).trim(),
    contentMarkdown,
    contentText: markdownToPlainText(contentMarkdown),
    contentHash: sha256(contentMarkdown),
  };
}

function markdownToPlainText(markdown) {
  return markdown
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/^[-*]\s+/gm, "• ")
    .replace(/\*\*(.*?)\*\*/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .trim();
}

const documents = Object.keys(manifest.documents).map((type) => ({
  type,
  requiresAcceptance: manifest.documents[type].requiresAcceptance === true,
  locales: Object.fromEntries(
    manifest.supportedLocales.map(
      (locale) => [locale, readCanonicalDocument(type, locale)],
    ),
  ),
}));

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function buildPayload(document) {
  const VERSION = documentVersion(document.type);
  const VERSION_NUMBER = documentVersionNumber(document.type);
  const CHANGE_SUMMARY = manifest.documents[document.type].changeSummary ?? `Publication of legal documents ${VERSION}.`;
  const contentHash = sha256(
    Object.keys(document.locales)
      .sort()
      .map((locale) => {
        const content = document.locales[locale];
        return [
          locale,
          content.title,
          content.contentMarkdown,
          content.contentText,
          content.contentHash,
        ].join("\n");
      })
      .join("\n---\n"),
  );
  const pointer = {
    documentType: document.type,
    activeVersion: VERSION,
    versionNumber: VERSION_NUMBER,
    status: STATUS,
    requiresAcceptance: document.requiresAcceptance,
    defaultLocale: DEFAULT_LOCALE,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: SEED_ACTOR,
    publishedAt: FieldValue.serverTimestamp(),
    publishedBy: SEED_ACTOR,
    changeSummary: CHANGE_SUMMARY,
  };
  const version = {
    documentType: document.type,
    version: VERSION,
    versionNumber: VERSION_NUMBER,
    status: STATUS,
    requiresAcceptance: document.requiresAcceptance,
    defaultLocale: DEFAULT_LOCALE,
    canonicalLocale: CANONICAL_LOCALE,
    locales: document.locales,
    contentHash,
    changeSummary: CHANGE_SUMMARY,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: SEED_ACTOR,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: SEED_ACTOR,
    publishedAt: FieldValue.serverTimestamp(),
    publishedBy: SEED_ACTOR,
    supersedesVersion: manifest.documents[document.type].supersedesVersion ?? null,
  };
  return {pointer, version};
}

function valueForFlag(flagName) {
  const index = rawArgs.indexOf(flagName);
  return index === -1 ? undefined : rawArgs[index + 1];
}

function readFirebaseProjectId() {
  try {
    const config = JSON.parse(
      readFileSync(new URL("../../.firebaserc", import.meta.url), "utf8"),
    );
    return config.projects?.default ?? config.projects?.production;
  } catch {
    return undefined;
  }
}

function loadServiceAccount(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function initializeFirestore() {
  if (getApps().length === 0) {
    const serviceAccount = serviceAccountPath ?
      loadServiceAccount(serviceAccountPath) :
      undefined;
    const projectId = projectIdArg ??
      process.env.FIREBASE_PROJECT_ID ??
      process.env.GCLOUD_PROJECT ??
      serviceAccount?.project_id ??
      readFirebaseProjectId();
    initializeApp({
      ...(projectId ? {projectId} : {}),
      ...(serviceAccount ? {credential: cert(serviceAccount)} : {}),
    });
  }
  return getFirestore();
}

function pathsFor(documentType) {
  return {
    pointer: `legalDocuments/${documentType}`,
    version: `legalDocuments/${documentType}/versions/${documentVersion(documentType)}`,
  };
}

function printPlan() {
  for (const document of documents) {
    const {pointer, version} = buildPayload(document);
    const paths = pathsFor(document.type);
    console.log(`${document.type}:`);
    console.log(`  pointer: ${paths.pointer}`);
    console.log(`  version: ${paths.version}`);
    console.log(`  activeVersion: ${pointer.activeVersion}`);
    console.log(`  requiresAcceptance: ${pointer.requiresAcceptance}`);
    console.log(`  locales: ${Object.keys(version.locales).join(", ")}`);
    console.log(`  contentHash: ${version.contentHash}`);
  }
}

async function verifySeed(db) {
  let hasError = false;
  for (const document of documents) {
    const {pointer, version} = buildPayload(document);
    const paths = pathsFor(document.type);
    const [pointerSnapshot, versionSnapshot] = await Promise.all([
      db.doc(paths.pointer).get(),
      db.doc(paths.version).get(),
    ]);
    const pointerData = pointerSnapshot.data();
    const versionData = versionSnapshot.data();
    const VERSION = documentVersion(document.type);
    const VERSION_NUMBER = documentVersionNumber(document.type);
    const matches = pointerSnapshot.exists &&
      versionSnapshot.exists &&
      pointerData.activeVersion === VERSION &&
      pointerData.versionNumber === VERSION_NUMBER &&
      pointerData.status === STATUS &&
      pointerData.requiresAcceptance === pointer.requiresAcceptance &&
      pointerData.defaultLocale === DEFAULT_LOCALE &&
      versionData.version === VERSION &&
      versionData.contentHash === version.contentHash;
    if (!matches) {
      console.error(
        `Seeded document does not match expected values: ${document.type}.`,
      );
      hasError = true;
    } else {
      console.log(
        `Verified ${document.type} ${VERSION} (${version.contentHash}).`,
      );
    }
  }
  if (hasError) process.exitCode = 1;
}

async function assertSafeToSeed(db) {
  if (isForce) return;
  const existingPaths = [];
  for (const document of documents) {
    const paths = pathsFor(document.type);
    const [pointer, version] = await Promise.all([
      db.doc(paths.pointer).get(),
      db.doc(paths.version).get(),
    ]);
    if (pointer.exists) existingPaths.push(paths.pointer);
    if (version.exists) existingPaths.push(paths.version);
  }
  if (existingPaths.length > 0) {
    throw new Error(
      `Refusing to overwrite existing legal documents:\n` +
      `${existingPaths.join("\n")}\n` +
      "Pass --force only when intentionally reseeding these documents.",
    );
  }
}

async function seedDocuments(db) {
  await assertSafeToSeed(db);
  const batch = db.batch();
  for (const document of documents) {
    const {pointer, version} = buildPayload(document);
    const paths = pathsFor(document.type);
    batch.set(db.doc(paths.pointer), pointer);
    batch.set(db.doc(paths.version), version);
  }
  await batch.commit();
  for (const document of documents) {
    const {version} = buildPayload(document);
    console.log(
      `Seeded ${pathsFor(document.type).version} (${version.contentHash}).`,
    );
  }
}

try {
  if (isDryRun) {
    printPlan();
  } else {
    const db = initializeFirestore();
    if (isVerify) await verifySeed(db);
    else await seedDocuments(db);
  }
} catch (error) {
  console.error(error?.message ?? error);
  process.exit(1);
}
