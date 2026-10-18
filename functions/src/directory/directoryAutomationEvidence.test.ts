import {strict as assert} from "node:assert";
import {test} from "node:test";
import {verifyOfficialDirectoryEvidence} from "./directoryAutomationEvidence";
import {type DirectoryAutomationCandidate} from "./directoryAutomationPolicy";

const candidate = {
  categoryId: "residence", topicId: "temporary-protection", sectionId: "contact",
  expectedRevision: 2, previousPayloadSHA256: "0".repeat(64), nextPayload: "{}",
  changeClass: "official-contact" as const, field: "phoneNumber" as const,
  newValue: "+43 1 99999",
  evidence: {url: "https://www.bfa.gv.at/kontakt/", authority: "BFA",
    observedAt: "2026-10-17T11:00:00.000Z",
    excerpt: "Bundesamt für Fremdenwesen und Asyl: +43 1 99999"},
} satisfies DirectoryAutomationCandidate;

test("checks direct official HTML content before accepting an evidence receipt", async () => {
  const fakeFetch = async () => new Response(
    "<html><script>ignore</script><p>Bundesamt für Fremdenwesen und Asyl: +43 1 99999</p></html>",
    {status: 200, headers: {"content-type": "text/html"}}
  );
  const receipt = await verifyOfficialDirectoryEvidence(candidate, fakeFetch as typeof fetch);
  assert.equal(receipt.url, candidate.evidence.url);
  assert.ok(Date.parse(receipt.checkedAt));
});

test("rejects external redirects, absent evidence, and blocked pages", async () => {
  await assert.rejects(verifyOfficialDirectoryEvidence(candidate, (async () => new Response("", {
    status: 302, headers: {location: "https://evil.example/"},
  })) as typeof fetch), /official HTTPS/);
  await assert.rejects(verifyOfficialDirectoryEvidence(candidate, (async () => new Response(
    "<html>Unrelated content</html>", {status: 200, headers: {"content-type": "text/html"}}
  )) as typeof fetch), /excerpt is absent/);
  await assert.rejects(verifyOfficialDirectoryEvidence(candidate, (async () => new Response(
    "Unavailable", {status: 403, headers: {"content-type": "text/html"}}
  )) as typeof fetch), /HTTP 403/);
});

test("rejects a content candidate if any additional claim fragment is absent", async () => {
  const content = {...candidate, evidence: {...candidate.evidence,
    excerpts: ["A different supporting statement absent from this page"]}};
  await assert.rejects(verifyOfficialDirectoryEvidence(content, (async () => new Response(
    `<p>${candidate.evidence.excerpt}</p>`, {headers: {"content-type": "text/html"}}
  )) as typeof fetch), /excerpt is absent/);
});
