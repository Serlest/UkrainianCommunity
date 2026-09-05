import {createHash} from "node:crypto";
import type {DocumentData} from "firebase-admin/firestore";

export const organizationActionNames = ["editInfo", "manageContent", "manageTeam", "viewSubscribers", "createNews", "editNews", "createEvent", "editEvent", "deleteContent", "managePhotos", "cancelEvent", "resubmitRequest", "deleteOrganization"] as const;
export type OrganizationAction = typeof organizationActionNames[number];
export type OrganizationCommand = "updateOrganizationInfo" | "saveOrganizationPhoto";

/** Configuration selects routes, never grants a role or bypasses a command guard. */
export function organizationRollout(config: DocumentData | undefined, uid: string) {
  const percent = config?.rolloutPercent ?? 100;
  const audience = config?.enabledUserIds;
  const validAudience = audience === undefined || (Array.isArray(audience) && audience.length <= 100 && audience.every(x => typeof x === "string"));
  const bucket = parseInt(createHash("sha256").update(uid).digest("hex").slice(0, 8), 16) % 100;
  const selected = validAudience && Number.isInteger(percent) && percent >= 0 && percent <= 100
    && (audience === undefined || audience.includes(uid)) && bucket < percent;
  const enabled = config?.mode === "enforced" && selected;
  const overrides = config?.actionModes;
  const modes = Object.fromEntries(organizationActionNames.map(action => [action,
    enabled && (overrides === undefined || overrides?.[action] === "enforced") ? "enforced" : "shadow"
  ])) as Record<OrganizationAction, "enforced" | "shadow">;
  const commands = {
    updateOrganizationInfo: enabled && config?.commandsEnabled === true
      && (config?.commandModes === undefined || config.commandModes.updateOrganizationInfo === "enforced"),
    // Media v2 is always opt-in, including on servers already using the old global switch.
    saveOrganizationPhoto: enabled && config?.commandsEnabled === true
      && config?.commandModes?.saveOrganizationPhoto === "enforced" && modes.managePhotos === "enforced",
  };
  return {mode: enabled ? "enforced" : "shadow", actionModes: modes, commands};
}

export function commandEnabled(config: DocumentData | undefined, uid: string, command: OrganizationCommand, action: OrganizationAction): boolean {
  const policy = organizationRollout(config, uid);
  return policy.commands[command] && policy.actionModes[action] === "enforced";
}

export function compareOrganizationDecisions(reported: unknown, allowed: string[]): {action: OrganizationAction; client: boolean; server: boolean}[] {
  if (!reported || typeof reported !== "object" || Array.isArray(reported)) return [];
  const object = reported as Record<string, unknown>;
  return organizationActionNames.flatMap(action => typeof object[action] === "boolean" && object[action] !== allowed.includes(action)
    ? [{action, client: object[action] as boolean, server: allowed.includes(action)}] : []);
}
