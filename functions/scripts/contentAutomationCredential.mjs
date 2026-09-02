import {firebaseCliCredential} from "./firebaseCliCredential.mjs";

export const DEFAULT_CONTENT_AUTOMATION_ACCOUNT_EMAIL = "timofyeyev.ph@gmail.com";

export function contentAutomationAccountEmail(environment = process.env) {
  const configured = environment.UAC_FIREBASE_ACCOUNT_EMAIL?.trim();
  return configured || DEFAULT_CONTENT_AUTOMATION_ACCOUNT_EMAIL;
}

export async function contentAutomationCredential(dependencies = {}) {
  const createCredential = dependencies.createCredential ?? firebaseCliCredential;
  const accountEmail = contentAutomationAccountEmail(
    dependencies.environment ?? process.env
  );
  return createCredential({accountEmail});
}

export async function contentAutomationAccessToken(dependencies = {}) {
  const credential = await contentAutomationCredential(dependencies);
  const token = await credential.getAccessToken();
  return token.access_token;
}

export async function decodeSuccessfulJSON(response, operation) {
  if (!response.ok) {
    const details = await safeResponseDetails(response);
    const suffix = details ? `: ${details}` : "";
    throw new Error(`${operation} failed (${response.status})${suffix}`);
  }
  return response.json();
}

async function safeResponseDetails(response) {
  try {
    const text = (await response.text()).trim();
    if (!text) return "";
    try {
      const payload = JSON.parse(text);
      const message = payload?.error?.message;
      return typeof message === "string" ? message : "request rejected";
    } catch {
      return "request rejected";
    }
  } catch {
    return "";
  }
}
