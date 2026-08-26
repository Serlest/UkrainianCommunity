import {strict as assert} from "node:assert";
import {test} from "node:test";

import {db} from "../firebase/admin";
import {saveComment} from "./commentModeration";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

function request(uid: string, data: unknown, verified = true) {
  return {auth: {uid, token: {email_verified: verified}}, data} as never;
}

test("comment callable filters and creates approved content", {skip: !enabled}, async () => {
  const prefix = `comment-filter-${Date.now()}`;
  const uid = `${prefix}-user`;
  const newsId = `${prefix}-news`;
  try {
    await db.collection("users").doc(uid).set({
      displayName: "Verified Author",
      avatarURL: "https://example.org/avatar.jpg",
      globalRole: "user",
      accountStatus: "active",
      blockState: "active",
    });
    await db.collection("news").doc(newsId).set({moderationStatus: "approved"});

    await assert.rejects(
      saveComment.run(request(uid, {parentType: "news", parentId: newsId, text: "I will kill you"})),
      {code: "invalid-argument"}
    );
    const created = await saveComment.run(request(uid, {
      parentType: "news",
      parentId: newsId,
      text: "  Дякую за інформацію!  ",
    }));
    assert.equal(created.text, "Дякую за інформацію!");
    assert.equal(created.authorName, "Verified Author");
    const stored = await db.collection("news").doc(newsId).collection("comments").doc(created.id).get();
    assert.equal(stored.get("body"), "Дякую за інформацію!");
    assert.equal(stored.get("moderationStatus"), "approved");

  } finally {
    await db.recursiveDelete(db.collection("news").doc(newsId));
    await db.recursiveDelete(db.collection("users").doc(uid));
  }
});
