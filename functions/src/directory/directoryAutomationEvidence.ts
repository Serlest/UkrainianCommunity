import {officialDirectoryURL, type DirectoryAutomationCandidate} from "./directoryAutomationPolicy";

const maximumSourceBytes = 600_000;

function readableText(html: string): string {
  return html.replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;|&#xA0;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ").trim();
}

function normalized(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

/** An official URL is read again by the server before any automatic write. */
export async function verifyOfficialDirectoryEvidence(
  candidate: DirectoryAutomationCandidate,
  fetchImpl: typeof fetch = fetch
): Promise<{url: string; checkedAt: string}> {
  let url = officialDirectoryURL(candidate.evidence.url, "Evidence URL");
  for (let redirect = 0; redirect <= 3; redirect++) {
    const response = await fetchImpl(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
      headers: {Accept: "text/html, text/plain;q=0.9"},
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirect === 3) throw new Error("Official source redirect failed.");
      url = officialDirectoryURL(new URL(location, url).toString(), "Redirect URL");
      continue;
    }
    if (!response.ok) throw new Error(`Official source returned HTTP ${response.status}.`);
    const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
    if (!contentType.includes("text/html") && !contentType.includes("text/plain")) {
      throw new Error("Official source is not readable HTML or text.");
    }
    const statedSize = Number(response.headers.get("content-length"));
    if (Number.isFinite(statedSize) && statedSize > maximumSourceBytes) {
      throw new Error("Official source exceeds read limit.");
    }
    if (!response.body) throw new Error("Official source body is unavailable.");
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let received = 0;
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      received += value.length;
      if (received > maximumSourceBytes) {
        await reader.cancel();
        throw new Error("Official source exceeds read limit.");
      }
      chunks.push(value);
    }
    if (!received) {
      throw new Error("Official source is empty or exceeds read limit.");
    }
    const bytes = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    const body = new TextDecoder("utf-8", {fatal: false}).decode(bytes);
    const visible = normalized(contentType.includes("text/html") ? readableText(body) : body);
    const excerpt = normalized(candidate.evidence.excerpt);
    if (!visible.includes(excerpt)) {
      throw new Error("Claimed evidence excerpt is absent from the official page.");
    }
    if (candidate.field === "phoneNumber" && !visible.includes(normalized(candidate.newValue))) {
      throw new Error("New phone number is absent from the official page.");
    }
    if (candidate.field === "source.url" && url.toString() !== candidate.newValue) {
      throw new Error("Checked source URL differs from the proposed published URL.");
    }
    return {url: url.toString(), checkedAt: new Date().toISOString()};
  }
  throw new Error("Official source redirect limit exceeded.");
}
