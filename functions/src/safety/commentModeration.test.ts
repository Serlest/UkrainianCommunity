import {strict as assert} from "node:assert";
import {test} from "node:test";

import {classifyCommentText} from "./commentModeration";

test("allows ordinary Ukrainian, German, and English community comments", () => {
  for (const text of [
    "Дякую за корисну подію!",
    "Kann ich auch mit Kindern teilnehmen?",
    "Great organization, thank you for sharing.",
    "Посилання на програму: https://example.org/event",
  ]) {
    assert.equal(classifyCommentText(text), null, text);
  }
});

test("rejects direct threats after normalization", () => {
  assert.equal(classifyCommentText("I’ll kill you"), "threat");
  assert.equal(classifyCommentText("Я тебе убью"), "threat");
  assert.equal(classifyCommentText("Ich töte dich"), "threat");
});

test("rejects child sexual exploitation terms", () => {
  assert.equal(classifyCommentText("child porn"), "sexual-exploitation");
  assert.equal(classifyCommentText("детское порно"), "sexual-exploitation");
});

test("rejects link flooding but allows a normal source link", () => {
  assert.equal(classifyCommentText("https://a.test https://b.test https://c.test"), "spam");
  assert.equal(classifyCommentText("Details: https://example.org"), null);
});
