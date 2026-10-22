import {execFileSync} from "node:child_process";
import {OAuth2Client} from "google-auth-library";
import {Firestore} from "firebase-admin/firestore";
const project = process.argv.find(v => v.startsWith("--project="))?.slice(10);
if (!project) throw new Error("Use --project=<id> (read only).");
const authClient = new OAuth2Client();
authClient.setCredentials({access_token: execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}).trim(), expiry_date: Date.now() + 3000000});
const db = new Firestore({projectId: project, authClient});
const owners = await db.collection("users").where("globalRole", "==", "owner").get();
const result = [];
for (const owner of owners.docs) {
  const [settings, tokens] = await Promise.all([owner.ref.collection("notificationPreferences").doc("settings").get(), owner.ref.collection("notificationPushTokens").get()]);
  result.push({active: (owner.get("accountStatus") ?? "active") === "active", notificationsEnabled: settings.get("notificationsEnabled") === true,
    registeredDevices: tokens.size, appleDevices: tokens.docs.filter(d => ["ios", "iOS", "apple"].includes(d.get("platform"))).length});
}
console.log(JSON.stringify({project, owners: result}));
