import {HttpsError} from "firebase-functions/v2/https";

type Translator = (texts: string[], source?: string, target?: string) => Promise<string[]>;
interface Piece { field: number; text: string; prefix: string; suffix: string; tokens: {marker: string; value: string}[]; }

/** Keep line breaks, Markdown markers, URLs and code verbatim. Fail closed if
 * a provider changes a protected token; the editor never applies partial output. */
function legalPieces(texts: string[]): Piece[] {
  const pieces: Piece[] = [];
  texts.forEach((text, field) => {
    const lines = text.match(/[^\n]*\n|[^\n]+$/g) ?? [];
    let fenced = false;
    for (const line of lines) {
      if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; pieces.push({field, text: "", prefix: line, suffix: "", tokens: []}); continue; }
      if (fenced || !line.trim()) { pieces.push({field, text: "", prefix: line, suffix: "", tokens: []}); continue; }
      const prefix = line.match(/^\s*(?:(?:#{1,6}|>|[-+*]|\d+[.)])\s+)?/)?.[0] ?? "";
      const suffix = line.slice(prefix.length).match(/\s*$/)?.[0] ?? "";
      const body = line.slice(prefix.length, line.length - suffix.length);
      const tokens: {marker: string; value: string}[] = [];
      const protectedText = body.replace(/(?<=\]\()[^)]+(?=\))|`[^`]*`|[\w.+%-]+@[\w.-]+\.[A-Za-z]{2,}|[()[\]|]|-{3,}|https?:\/\/[^\s<>)]+|\*\*|__|~~|\]\(|\)\s*$|(?<!\w)[*_](?!\s)|(?<!\s)[*_](?!\w)/g, value => {
        const marker = `⟪UAC${tokens.length}⟫`; tokens.push({marker, value}); return marker;
      });
      // Protected syntax tokens are atomic, even for a URL crossing a chunk boundary.
      if (!protectedText) { pieces.push({field, text: "", prefix, suffix, tokens: []}); continue; }
      const units = protectedText.match(/⟪UAC\d+⟫|[\s\S]/gu) ?? [];
      let offset = 0;
      while (offset < units.length) {
        let end = offset, size = 0, boundary = offset;
        while (end < units.length && size + units[end].length <= 6000) {
          size += units[end].length;
          if (/^\s$/.test(units[end])) boundary = end + 1;
          end++;
        }
        if (end < units.length && boundary > offset + 1000) end = boundary;
        const chunk = units.slice(offset, end).join("");
        const leading = chunk.match(/^\s*/)?.[0] ?? "";
        const trailing = chunk.slice(leading.length).match(/\s*$/)?.[0] ?? "";
        pieces.push({field, text: chunk.slice(leading.length, chunk.length - trailing.length),
          prefix: (offset === 0 ? prefix : "") + leading,
          suffix: trailing + (end === units.length ? suffix : ""), tokens: tokens.filter(t => chunk.includes(t.marker))});
        offset = end;
      }

    }
  });
  if (pieces.length > 1024) throw new HttpsError("invalid-argument", "Too many legal text lines.");
  return pieces;
}
export function legalTranslationSize(texts: string[]): number {
  return legalPieces(texts).reduce((n, p) => n + p.text.length, 0);
}
export async function translateLegalTexts(texts: string[], source: string, target: string,
  translate: Translator): Promise<string[]> {
  const output = texts.map(() => "");
  const pieces = legalPieces(texts);
  const translated = new Map<Piece, string>();
  let batch: Piece[] = [], size = 0;
  const flush = async () => {
    if (!batch.length) return;
    const result = await translate(batch.map(p => p.text), source, target);
    if (result.length !== batch.length) throw new HttpsError("unavailable", "Incomplete legal translation.");
    batch.forEach((piece, i) => {
      let value = result[i];
      for (const {marker, value: token} of piece.tokens) {
        if (value.split(marker).length !== 2) throw new HttpsError("unavailable", "Legal markup was not preserved.");
        value = value.replace(marker, token);
      }
      if (/⟪UAC\d+⟫/.test(value)) throw new HttpsError("unavailable", "Invalid legal translation.");
      translated.set(piece, value);
    });
    batch = []; size = 0;
  };
  for (const piece of pieces) {
    if (!piece.text) continue;
    if (size + piece.text.length > 18000 || batch.length >= 512) await flush();
    batch.push(piece); size += piece.text.length;
  }
  await flush();
  for (const piece of pieces) output[piece.field] += piece.prefix + (translated.get(piece) ?? "") + piece.suffix;
  if (output.some(t => t.length > 100000)) throw new HttpsError("resource-exhausted", "Legal translation is too long.");
  return output;
}
