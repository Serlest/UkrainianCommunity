import {strict as assert} from "node:assert";
import {test} from "node:test";
import {translateLegalTexts} from "./legalTranslation";
import {translationInput} from "./service";

test("long legal translation preserves Markdown, URLs, whitespace and code in bounded batches", async () => {
  const source = "# Hallo\n\n**Hallo** [Link](https://example.com/a?q=1)\n- Hallo\n```swift\nlet value = 1\n```\n" + "Hallo paragraph with more content for translation.\n".repeat(900);
  let calls = 0;
  const result = await translateLegalTexts(["Title", source], "de", "uk", async texts => {
    calls++;
    assert.ok(texts.reduce((n, t) => n + t.length, 0) <= 18000);
    return texts.map(t => t.replaceAll("Hallo", "Вітаю"));
  });
  assert.ok(calls > 1);
  assert.equal(result[1], source.replaceAll("Hallo", "Вітаю"));
  assert.equal(translationInput({kind: "legal", source: "de", texts: [source]}).source, "de");
  assert.throws(() => translationInput({kind: "news", texts: [source]}));
});
test("broken protected markup never returns a partial legal translation", async () => {
  await assert.rejects(translateLegalTexts(["[Link](https://example.com)"], "uk", "de", async texts => texts.map(() => "corrupt")));
});

test("relative links, email destinations and a URL across a chunk boundary stay intact", async () => {
  const source = "Hallo ".repeat(1100) + "[Hallo](/privacy) [Mail](mailto:contact@example.com) https://example.com/" + "x".repeat(7000);
  const [result] = await translateLegalTexts([source], "de", "uk", async texts => texts.map(t => t.replaceAll("Hallo", "Вітаю")));
  assert.equal(result, source.replaceAll("Hallo", "Вітаю"));
});
