import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

import ts from "typescript";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultSourceRoot = path.resolve(scriptDirectory, "../src");

function typescriptFiles(root) {
  return fs.readdirSync(root, {withFileTypes: true})
    .flatMap((entry) => {
      const absolutePath = path.join(root, entry.name);
      if (entry.isDirectory()) return typescriptFiles(absolutePath);
      return entry.isFile() && entry.name.endsWith(".ts") ? [absolutePath] : [];
    })
    .sort();
}

function propertyNameText(name) {
  if (ts.isIdentifier(name) || ts.isStringLiteral(name)) return name.text;
  return undefined;
}

function unwrapExpression(expression) {
  let current = expression;
  while (
    ts.isAsExpression(current)
    || ts.isSatisfiesExpression(current)
    || ts.isParenthesizedExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function localObjectLiteral(identifier, sourceFile) {
  let result;
  const visit = (node) => {
    if (result) return;
    if (
      ts.isVariableDeclaration(node)
      && ts.isIdentifier(node.name)
      && node.name.text === identifier.text
      && node.initializer
    ) {
      const initializer = unwrapExpression(node.initializer);
      if (ts.isObjectLiteralExpression(initializer)) result = initializer;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return result;
}

function policyValue(objectLiteral) {
  const property = objectLiteral.properties.find((candidate) => (
    ts.isPropertyAssignment(candidate)
    && propertyNameText(candidate.name) === "enforceAppCheck"
  ));
  if (!property) return undefined;

  const initializer = unwrapExpression(property.initializer);
  if (initializer.kind === ts.SyntaxKind.TrueKeyword) return "enforced";
  if (initializer.kind === ts.SyntaxKind.FalseKeyword) return "monitoring";
  return "dynamic";
}

function lineNumber(sourceFile, node) {
  return sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
}

export function inspectAppCheckPolicy(sourceRoot = defaultSourceRoot) {
  const results = [];
  const violations = [];

  for (const filename of typescriptFiles(sourceRoot)) {
    const sourceText = fs.readFileSync(filename, "utf8");
    const sourceFile = ts.createSourceFile(
      filename,
      sourceText,
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.TS
    );

    const visit = (node) => {
      if (
        ts.isCallExpression(node)
        && ts.isIdentifier(node.expression)
        && node.expression.text === "onCall"
      ) {
        const relativePath = path.relative(sourceRoot, filename);
        const line = lineNumber(sourceFile, node);
        const optionsArgument = node.arguments.length >= 2 ? node.arguments[0] : undefined;
        let objectLiteral;

        if (optionsArgument) {
          const unwrappedOptions = unwrapExpression(optionsArgument);
          if (ts.isObjectLiteralExpression(unwrappedOptions)) {
            objectLiteral = unwrappedOptions;
          } else if (ts.isIdentifier(unwrappedOptions)) {
            objectLiteral = localObjectLiteral(unwrappedOptions, sourceFile);
          }
        }

        const policy = objectLiteral ? policyValue(objectLiteral) : undefined;
        if (!policy) {
          violations.push(
            `${relativePath}:${line} must declare enforceAppCheck explicitly in its onCall options`
          );
        } else {
          results.push({file: relativePath, line, policy});
        }
      }
      ts.forEachChild(node, visit);
    };

    visit(sourceFile);
  }

  return {results, violations};
}

export function policySummary(results) {
  return results.reduce(
    (summary, result) => ({...summary, [result.policy]: summary[result.policy] + 1}),
    {enforced: 0, monitoring: 0, dynamic: 0}
  );
}

function run() {
  const sourceRoot = process.argv[2] ? path.resolve(process.argv[2]) : defaultSourceRoot;
  const {results, violations} = inspectAppCheckPolicy(sourceRoot);
  if (violations.length > 0) {
    console.error(["App Check policy validation failed:", ...violations.map((item) => `- ${item}`)].join("\n"));
    process.exitCode = 1;
    return;
  }

  const summary = policySummary(results);
  console.log(
    `Validated ${results.length} onCall construction sites: `
    + `${summary.enforced} enforced, ${summary.monitoring} monitoring, ${summary.dynamic} dynamic.`
  );
}

if (path.resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) run();
