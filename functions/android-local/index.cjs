"use strict";

// This is a separate emulator entrypoint. Never add it to production firebase.json.
require("./preload.cjs");
const application = require("../lib/index.js");

for (const [name, handler] of Object.entries(application)) {
  if (typeof handler === "function" && handler.__endpoint?.callableTrigger) {
    exports[name] = handler;
  }
}
if (Object.keys(exports).length === 0) throw new Error("No compiled local callables found; build Functions first.");
