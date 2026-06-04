/* global console, process */

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { cert, initializeApp, getApps } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const VERSION = "2026.1";
const VERSION_NUMBER = 202601;
const STATUS = "published";
const REQUIRES_ACCEPTANCE = true;
const DEFAULT_LOCALE = "de";
const CANONICAL_LOCALE = "de";
const SEED_ACTOR = "legal-seed-script";
const CHANGE_SUMMARY = "Initial Firestore legal document seed from current app text.";

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isDryRun = args.has("--dry-run");
const isVerify = args.has("--verify");
const isForce = args.has("--force");
const projectIdArg = valueForFlag("--project-id");
const serviceAccountPath = valueForFlag("--service-account");

const documents = [
  {
    type: "terms",
    title: {
      de: "Nutzungsbedingungen",
      uk: "Умови використання",
    },
    sections: {
      de: [
        {
          title: "Nutzung der App",
          body:
            "Ukrainian Community Tirol hilft Menschen dabei, öffentliche Updates, " +
            "Veranstaltungen, Organisationen und praktische Orientierung zu finden. " +
            "Wenn Sie die App mit einem Konto verwenden, stimmen Sie zu, sie " +
            "rechtmäßig, respektvoll und nur für ihren vorgesehenen Community-Zweck " +
            "zu nutzen.",
        },
        {
          title: "Verantwortung für Ihr Konto",
          body:
            "Sie sind dafür verantwortlich, dass die von Ihnen angegebenen " +
            "Profildaten korrekt sind, dass Ihre Zugangsdaten vertraulich bleiben " +
            "und dass Handlungen über Ihr Konto von Ihnen verantwortet werden. " +
            "Sie dürfen sich nicht als andere Person ausgeben oder Konten anlegen, " +
            "um Moderation zu umgehen.",
        },
        {
          title: "Community-Inhalte und Moderation",
          body:
            "Von Nutzerinnen und Nutzern eingereichte Inhalte können überprüft, " +
            "eingeschränkt oder entfernt werden, wenn sie irreführend, unsicher, " +
            "rechtswidrig, beleidigend, diskriminierend, spamartig oder thematisch " +
            "unpassend sind. Rollen mit Moderationsaufgaben dürfen Inhalte gemäß " +
            "dem Moderationsmodell des Projekts verwalten.",
        },
        {
          title: "Verfügbarkeit und Änderungen",
          body:
            "Wir dürfen Teile des Dienstes verbessern, ändern oder vorübergehend " +
            "einschränken, einschließlich Community-Funktionen und Kontozugriff, " +
            "um Zuverlässigkeit, Sicherheit und Compliance zu wahren. Eine " +
            "unterbrechungsfreie Verfügbarkeit wird nicht zugesichert.",
        },
        {
          title: "Informationen und Verantwortung",
          body:
            "Die App soll Orientierung und Community-Koordination unterstützen. " +
            "Sie ersetzt keine rechtliche, medizinische, finanzielle oder " +
            "behördliche Beratung. Nutzerinnen und Nutzer bleiben für Entscheidungen " +
            "verantwortlich, die sie auf Grundlage geteilter Informationen treffen.",
        },
      ],
      uk: [
        {
          title: "Використання застосунку",
          body:
            "Ukrainian Community Tirol допомагає знаходити публічні оновлення, " +
            "події, організації та практичну корисну інформацію. Використовуючи " +
            "застосунок з обліковим записом, ви погоджуєтеся користуватися ним " +
            "законно, з повагою та лише для його спільнотної мети.",
        },
        {
          title: "Відповідальність за обліковий запис",
          body:
            "Ви відповідаєте за точність даних профілю, які надаєте, за " +
            "конфіденційність своїх даних для входу та за дії, виконані через ваш " +
            "обліковий запис. Заборонено видавати себе за іншу особу або створювати " +
            "облікові записи для обходу модерації.",
        },
        {
          title: "Вміст спільноти та модерація",
          body:
            "Користувацький вміст може бути перевірений, обмежений або видалений, " +
            "якщо він є оманливим, небезпечним, незаконним, образливим, " +
            "дискримінаційним, схожим на спам або не відповідає призначенню " +
            "застосунку. Ролі з модераторськими обов’язками можуть керувати " +
            "вмістом відповідно до моделі модерації проєкту.",
        },
        {
          title: "Доступність і зміни",
          body:
            "Ми можемо покращувати, змінювати або тимчасово обмежувати частини " +
            "сервісу, зокрема функції спільноти та доступ до облікового запису, " +
            "щоб підтримувати надійність, безпеку та відповідність вимогам. " +
            "Безперервна доступність сервісу не гарантується.",
        },
        {
          title: "Інформація та відповідальність",
          body:
            "Застосунок призначений для орієнтації та координації в межах " +
            "спільноти. Він не замінює юридичну, медичну, фінансову чи офіційну " +
            "державну консультацію. Користувачі самі відповідають за рішення, які " +
            "ухвалюють на основі поширеної інформації.",
        },
      ],
    },
  },
  {
    type: "privacy",
    title: {
      de: "Datenschutzerklärung",
      uk: "Політика конфіденційності",
    },
    sections: {
      de: [
        {
          title: "Welche Daten wir speichern",
          body:
            "Wenn Sie ein Konto erstellen, speichern wir die Profildaten, die für " +
            "die App notwendig sind: E-Mail-Adresse, Anzeigename, optionalen " +
            "Telegram-Benutzernamen, ausgewähltes Bundesland sowie Rollen-, " +
            "Status- und Zeitstempelfelder rund um Konto und Einwilligungen.",
        },
        {
          title: "Wofür wir Daten verwenden",
          body:
            "Wir verwenden Kontodaten, um Sie anzumelden, Ihr Profil anzuzeigen, " +
            "Berechtigungen anzuwenden, Feedback und Veranstaltungsanmeldungen zu " +
            "unterstützen und den Community-Bereich durch Moderation und " +
            "Missbrauchsschutz sicher zu halten.",
        },
        {
          title: "Speicherung und Dienstleister",
          body:
            "Diese App verwendet Firebase-Dienste für Authentifizierung, Datenbank " +
            "und Medienspeicher. Daten werden nur verarbeitet, um die Funktionen " +
            "der App bereitzustellen, die Sicherheit zu erhalten und interne " +
            "Abläufe zu unterstützen.",
        },
        {
          title: "Weitergabe und Sichtbarkeit",
          body:
            "Wir verkaufen keine personenbezogenen Daten. Bestimmte Profildaten " +
            "und nutzergenerierte Inhalte können innerhalb der App sichtbar sein, " +
            "soweit das für Community-Funktionen nötig ist. Administrative und " +
            "moderierende Rollen dürfen relevante Einträge einsehen, um Regeln " +
            "durchzusetzen und den Dienst zu verwalten.",
        },
        {
          title: "Ihre Möglichkeiten",
          body:
            "Sie können unterstützte Profilfelder direkt in der App aktualisieren. " +
            "Wenn Sie Hilfe zu Kontodaten, Moderationsfragen oder Löschanfragen " +
            "brauchen, wenden Sie sich bitte über den vorgesehenen Support-Kanal " +
            "an das Projektteam.",
        },
      ],
      uk: [
        {
          title: "Які дані ми зберігаємо",
          body:
            "Коли ви створюєте обліковий запис, ми зберігаємо дані профілю, " +
            "потрібні для роботи застосунку: адресу електронної пошти, ім’я для " +
            "показу, необов’язкове ім’я користувача Telegram, вибрану федеральну " +
            "землю, а також поля ролі, статусу й часові позначки, пов’язані з " +
            "обліковим записом і згодами.",
        },
        {
          title: "Для чого ми використовуємо дані",
          body:
            "Ми використовуємо дані облікового запису, щоб автентифікувати вас, " +
            "показувати ваш профіль, застосовувати дозволи, підтримувати відгуки " +
            "та реєстрації на події, а також підтримувати безпеку простору " +
            "спільноти через модерацію та захист від зловживань.",
        },
        {
          title: "Зберігання та постачальники сервісів",
          body:
            "Цей застосунок використовує сервіси Firebase для автентифікації, " +
            "бази даних і зберігання медіафайлів. Дані обробляються лише для " +
            "надання функцій застосунку, підтримки безпеки та внутрішніх операцій.",
        },
        {
          title: "Передача та видимість",
          body:
            "Ми не продаємо персональні дані. Частина даних профілю та " +
            "користувацького вмісту може бути видимою в застосунку там, де це " +
            "потрібно для функцій спільноти. Адміністративні та модераторські " +
            "ролі можуть переглядати відповідні записи для застосування правил " +
            "і керування сервісом.",
        },
        {
          title: "Ваші можливості",
          body:
            "Ви можете оновлювати підтримувані поля профілю безпосередньо в " +
            "застосунку. Якщо вам потрібна допомога щодо даних облікового запису, " +
            "питань модерації або запитів на видалення, зверніться до команди " +
            "проєкту через доступний канал підтримки.",
        },
      ],
    },
  },
];

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function markdownFor(title, sections) {
  const sectionMarkdown = sections
    .map((section) => `## ${section.title}\n\n${section.body}`)
    .join("\n\n");

  return `# ${title}\n\n${sectionMarkdown}`;
}

function textFor(title, sections) {
  const sectionText = sections
    .map((section) => `${section.title}\n${section.body}`)
    .join("\n\n");

  return `${title}\n\n${sectionText}`;
}

function buildPayload(document) {
  const locales = Object.fromEntries(
    Object.entries(document.sections).map(([locale, sections]) => {
      const title = document.title[locale];
      const contentMarkdown = markdownFor(title, sections);
      const contentText = textFor(title, sections);

      return [
        locale,
        {
          title,
          contentMarkdown,
          contentText,
          contentHash: sha256(contentMarkdown),
        },
      ];
    }),
  );

  const contentHash = sha256(
    Object.keys(locales)
      .sort()
      .map((locale) => {
        const content = locales[locale];
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
    requiresAcceptance: REQUIRES_ACCEPTANCE,
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
    requiresAcceptance: REQUIRES_ACCEPTANCE,
    defaultLocale: DEFAULT_LOCALE,
    canonicalLocale: CANONICAL_LOCALE,
    locales,
    contentHash,
    changeSummary: CHANGE_SUMMARY,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: SEED_ACTOR,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: SEED_ACTOR,
    publishedAt: FieldValue.serverTimestamp(),
    publishedBy: SEED_ACTOR,
    supersedesVersion: null,
  };

  return { pointer, version };
}

function valueForFlag(flagName) {
  const index = rawArgs.indexOf(flagName);

  if (index === -1) {
    return undefined;
  }

  return rawArgs[index + 1];
}

function readFirebaseProjectId() {
  try {
    const firebasercUrl = new URL("../../.firebaserc", import.meta.url);
    const firebaserc = JSON.parse(readFileSync(firebasercUrl, "utf8"));
    const projects = firebaserc.projects ?? {};

    return projects.default ?? projects.production;
  } catch {
    return undefined;
  }
}

function loadServiceAccount(path) {
  const json = readFileSync(path, "utf8");
  return JSON.parse(json);
}

function resolveProjectId(serviceAccount) {
  return (
    projectIdArg ??
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GCLOUD_PROJECT ??
    serviceAccount?.project_id ??
    readFirebaseProjectId()
  );
}

function initializeFirestore() {
  if (getApps().length === 0) {
    const serviceAccount = serviceAccountPath
      ? loadServiceAccount(serviceAccountPath)
      : undefined;
    const projectId = resolveProjectId(serviceAccount);
    const appOptions = {};

    if (projectId) {
      appOptions.projectId = projectId;
    }

    if (serviceAccount) {
      appOptions.credential = cert(serviceAccount);
    }

    initializeApp(appOptions);
  }

  return getFirestore();
}

function printCredentialHelp(error) {
  console.error(error?.message ?? error);
  console.error("");
  console.error("Firestore access requires one of:");
  console.error("  --service-account /secure/path/service-account.json");
  console.error("  GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json");
  console.error("  FIRESTORE_EMULATOR_HOST for emulator seeding");
  console.error("");
  console.error("Firebase CLI login is not used as an Admin SDK credential.");
}

function pathsFor(documentType) {
  return {
    pointer: `legalDocuments/${documentType}`,
    version: `legalDocuments/${documentType}/versions/${VERSION}`,
  };
}

function printPlan() {
  for (const document of documents) {
    const { pointer, version } = buildPayload(document);
    const paths = pathsFor(document.type);
    console.log(`${document.type}:`);
    console.log(`  pointer: ${paths.pointer}`);
    console.log(`  version: ${paths.version}`);
    console.log(`  activeVersion: ${pointer.activeVersion}`);
    console.log(`  versionNumber: ${pointer.versionNumber}`);
    console.log(`  defaultLocale: ${pointer.defaultLocale}`);
    console.log(`  locales: ${Object.keys(version.locales).join(", ")}`);
    console.log(`  contentHash: ${version.contentHash}`);
  }
}

async function verifySeed(db) {
  let hasError = false;

  for (const document of documents) {
    const { version } = buildPayload(document);
    const paths = pathsFor(document.type);
    const pointerSnapshot = await db.doc(paths.pointer).get();
    const versionSnapshot = await db.doc(paths.version).get();

    if (!pointerSnapshot.exists || !versionSnapshot.exists) {
      console.error(`Missing seeded document for ${document.type}.`);
      hasError = true;
      continue;
    }

    const pointerData = pointerSnapshot.data();
    const versionData = versionSnapshot.data();
    const matches =
      pointerData.activeVersion === VERSION &&
      pointerData.versionNumber === VERSION_NUMBER &&
      pointerData.status === STATUS &&
      pointerData.requiresAcceptance === REQUIRES_ACCEPTANCE &&
      pointerData.defaultLocale === DEFAULT_LOCALE &&
      versionData.version === VERSION &&
      versionData.versionNumber === VERSION_NUMBER &&
      versionData.status === STATUS &&
      versionData.contentHash === version.contentHash;

    if (!matches) {
      console.error(`Seeded document does not match expected values: ${document.type}.`);
      hasError = true;
      continue;
    }

    console.log(`Verified ${document.type} ${VERSION} (${version.contentHash}).`);
  }

  if (hasError) {
    process.exitCode = 1;
  }
}

async function assertSafeToSeed(db) {
  if (isForce) {
    return;
  }

  const existingPaths = [];

  for (const document of documents) {
    const paths = pathsFor(document.type);
    const [pointerSnapshot, versionSnapshot] = await Promise.all([
      db.doc(paths.pointer).get(),
      db.doc(paths.version).get(),
    ]);

    if (pointerSnapshot.exists) {
      existingPaths.push(paths.pointer);
    }

    if (versionSnapshot.exists) {
      existingPaths.push(paths.version);
    }
  }

  if (existingPaths.length > 0) {
    console.error("Refusing to overwrite existing legal documents:");
    for (const path of existingPaths) {
      console.error(`  ${path}`);
    }
    console.error("Pass --force only when intentionally reseeding these documents.");
    process.exit(1);
  }
}

async function seedDocuments(db) {
  await assertSafeToSeed(db);

  const batch = db.batch();

  for (const document of documents) {
    const { pointer, version } = buildPayload(document);
    const paths = pathsFor(document.type);

    batch.set(db.doc(paths.pointer), pointer);
    batch.set(db.doc(paths.version), version);
  }

  await batch.commit();

  for (const document of documents) {
    const { version } = buildPayload(document);
    const paths = pathsFor(document.type);
    console.log(`Seeded ${paths.pointer}.`);
    console.log(`Seeded ${paths.version} (${version.contentHash}).`);
  }
}

try {
  if (isDryRun) {
    printPlan();
  } else {
    const db = initializeFirestore();

    if (isVerify) {
      await verifySeed(db);
    } else {
      await seedDocuments(db);
    }
  }
} catch (error) {
  printCredentialHelp(error);
  process.exit(1);
}
