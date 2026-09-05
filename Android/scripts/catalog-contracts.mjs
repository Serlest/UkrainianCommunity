import {createHash} from "node:crypto";
import {readFileSync, readdirSync, writeFileSync, mkdirSync} from "node:fs";
import {resolve, relative, dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {createRequire} from "node:module";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const require = createRequire(resolve(root, "functions/package.json"));
const ts = require("typescript");
const output = resolve(root, "Contracts/Android/source-catalog.json");
const walk = path => readdirSync(path, {withFileTypes: true}).flatMap(entry => {
  const file = resolve(path, entry.name);
  return entry.isDirectory() ? walk(file) : [file];
});
const paths = [
  ...walk(resolve(root, "UkrainianCommunity")).filter(p => p.endsWith(".swift")),
  ...walk(resolve(root, "functions/src")).filter(p => p.endsWith(".ts") && !p.endsWith(".test.ts")),
  resolve(root, "Firebase/firestore.rules"), resolve(root, "Firebase/storage.rules"),
  resolve(root, "Firebase/firestore.indexes.json")
].sort();
const sources = paths.map(path => {
  const content = readFileSync(path, "utf8");
  return {path: relative(root, path), sha256: createHash("sha256").update(content).digest("hex"), content};
});
if (process.argv.includes("--check")) {
  const old = JSON.parse(readFileSync(output, "utf8"));
  const current = sources.map(({path, sha256}) => ({path, sha256}));
  if (JSON.stringify(old.sources) !== JSON.stringify(current)) throw new Error("Contract sources changed; review affected entries before refreshing.");
  console.log(`PASS: ${current.length} source fingerprints unchanged.`);
  process.exit(0);
}
const swiftDeclarations = [];
const repositoryOperations = [];
const wireMappings = [];
const endpoints = [];
const serverTypes = [];
const rules = [];
for (const source of sources) {
  const lines = source.content.split("\n");
  if (source.path.endsWith(".swift")) {
    lines.forEach((text, index) => {
      const item = {path: source.path, line: index + 1, text: text.trim()};
      if (/\b(struct|enum|protocol)\s+\w+|^\s*(?:nonisolated\s+)?(?:let|var)\s+\w+\s*:|^\s*case\s+\w+/.test(text)
          && /\/Models\/|CloudFunctionsClient|ContentPublishingCoding|OwnerContentPublicationResponse/.test(source.path)) swiftDeclarations.push(item);
      if (/\bfunc\s+\w+/.test(text) && /\/Repositories\/|\/Services\//.test(source.path)) repositoryOperations.push(item);
      if (/data\[|\.collection\(|\.document\(|whereField\(|\.order\(by|\.limit\(to|\.start\(after|httpsCallable|"[^"]+"\s*:/.test(text)
          && /\/Repositories\/|\/Services\/Firebase\//.test(source.path)) wireMappings.push(item);
    });
  } else if (source.path.endsWith(".ts")) {
    const ast = ts.createSourceFile(source.path, source.content, ts.ScriptTarget.Latest, true);
    for (const statement of ast.statements) {
      const line = ast.getLineAndCharacterOfPosition(statement.getStart(ast)).line + 1;
      if (ts.isInterfaceDeclaration(statement) || ts.isTypeAliasDeclaration(statement)) {
        serverTypes.push({path: source.path, line, name: statement.name.text, declaration: statement.getText(ast)});
      }
      if (ts.isVariableStatement(statement) && statement.modifiers?.some(m => m.kind === ts.SyntaxKind.ExportKeyword)) {
        for (const d of statement.declarationList.declarations) {
          if (!d.initializer || !ts.isCallExpression(d.initializer)) continue;
          const factory = d.initializer.expression.getText(ast);
          if (!/onCall|onRequest|onSchedule|onDocument|create.*(Mutation|Function|Handler|Callable)/.test(factory)) continue;
          endpoints.push({path: source.path, line, name: d.name.getText(ast), factory, declaration: d.getText(ast)});
        }
      }
    }
  } else if (source.path.endsWith(".rules")) {
    lines.forEach((text, index) => {
      if (/function\s|match\s\/|allow\s/.test(text)) rules.push({path: source.path, line: index + 1, text: text.trim()});
    });
  }
}
const catalog = {
  schemaVersion: 1, baseline: "c9c2a692cacc190318dbf6b38b93a276d497da19", date: "2026-09-02",
  note: "Read-only source inventory, not a generated authorization SDK. Swift declarations include computed/legacy members; wireMappings and server validators are authoritative. Endpoint factories include triggers, not only callable APIs.",
  sources: sources.map(({path, sha256}) => ({path, sha256})),
  swiftDeclarations, repositoryOperations, wireMappings, serverTypes, endpoints, rules,
  indexes: JSON.parse(sources.find(s => s.path.endsWith("firestore.indexes.json")).content)
};
mkdirSync(dirname(output), {recursive: true});
writeFileSync(output, JSON.stringify(catalog, null, 2) + "\n");
console.log(Object.fromEntries(Object.entries(catalog).filter(([,v]) => Array.isArray(v)).map(([k,v]) => [k,v.length])));
