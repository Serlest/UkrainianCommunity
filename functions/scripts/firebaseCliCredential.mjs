import {execFileSync} from "node:child_process";
import {createRequire} from "node:module";
import {dirname, join} from "node:path";
import {realpathSync} from "node:fs";

const defaultTokenLifetimeSeconds = 3600;
const refreshSafetyWindowMilliseconds = 60_000;

export async function firebaseCliCredential(dependencies = {}) {
  const runFirebaseLogin = dependencies.runFirebaseLogin ?? defaultFirebaseLogin;
  const loadFirebaseAuth = dependencies.loadFirebaseAuth ?? defaultFirebaseAuth;
  const now = dependencies.now ?? Date.now;
  const requestedAccountEmail = normalizedOptionalEmail(dependencies.accountEmail);
  const login = parseFirebaseLogin(runFirebaseLogin());
  const firebaseAuth = loadFirebaseAuth();
  if (!firebaseAuth || typeof firebaseAuth.getAccessToken !== "function") {
    throw new Error("Firebase CLI authentication helper is unavailable.");
  }
  const accounts = Array.isArray(login?.result) ? login.result : [];
  const activeAccount = typeof firebaseAuth.getGlobalDefaultAccount === "function"
    ? firebaseAuth.getGlobalDefaultAccount()
    : undefined;
  const activeEmail = activeAccount?.user?.email;
  const account = requestedAccountEmail
    ? accounts.find((candidate) => normalizedOptionalEmail(candidate?.user?.email) === requestedAccountEmail)
    : typeof activeEmail === "string"
      ? accounts.find((candidate) => candidate?.user?.email === activeEmail)
      : accounts.length === 1 ? accounts[0] : undefined;
  const refreshToken = account?.tokens?.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length < 20 ||
      typeof account?.user?.email !== "string") {
    throw new Error(requestedAccountEmail
      ? "Firebase CLI is not authenticated as the requested account."
      : "Firebase CLI is not authenticated or has no unambiguous active account.");
  }

  let cachedToken;
  let cachedUntil = 0;
  return {
    accountEmail: account.user.email,
    async getAccessToken() {
      if (cachedToken && cachedUntil - refreshSafetyWindowMilliseconds > now()) {
        return cachedToken;
      }
      const refreshed = await firebaseAuth.getAccessToken(refreshToken, []);
      const accessToken = refreshed?.access_token;
      if (typeof accessToken !== "string" || accessToken.length < 20) {
        throw new Error("Firebase CLI access token is unavailable.");
      }
      const expiresIn = positiveNumber(refreshed?.expires_in) ?? defaultTokenLifetimeSeconds;
      cachedToken = {access_token: accessToken, expires_in: expiresIn};
      cachedUntil = now() + expiresIn * 1000;
      return cachedToken;
    },
  };
}

function defaultFirebaseLogin() {
  try {
    return execFileSync("firebase", ["login:list", "--json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch {
    throw new Error("Firebase CLI is unavailable or not authenticated.");
  }
}

function defaultFirebaseAuth() {
  try {
    const require = createRequire(import.meta.url);
    const firebaseExecutable = execFileSync("which", ["firebase"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
    const firebaseEntrypoint = realpathSync(firebaseExecutable);
    const firebaseLib = dirname(dirname(firebaseEntrypoint));
    return require(join(firebaseLib, "auth.js"));
  } catch {
    throw new Error("Firebase CLI authentication helper is unavailable.");
  }
}

function parseFirebaseLogin(output) {
  try {
    return JSON.parse(output);
  } catch {
    throw new Error("Firebase CLI returned invalid authentication data.");
  }
}

function positiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : undefined;
}

function normalizedOptionalEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}
