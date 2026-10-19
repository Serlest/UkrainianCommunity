import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {bannerConfigurationAt} from "./bannerMeasurementHistory";

const t = (n: number) => Timestamp.fromMillis(n);
test("offline events use configuration at exposure, including after deletion", () => {
  const before = {validFrom: t(100), validUntil: t(200), isActive: true, visibleSections: ["home"]};
  const current = {updatedAt: t(200), isActive: false, visibleSections: ["events"]};
  assert.equal(bannerConfigurationAt(current, {versions: [before]}, 150)?.isActive, true);
  assert.equal(bannerConfigurationAt(current, {versions: [before]}, 200)?.isActive, false);
  assert.equal(bannerConfigurationAt(undefined, {versions: [before]}, 150)?.isActive, true);
  assert.equal(bannerConfigurationAt(undefined, {versions: [before]}, 200), undefined);
  assert.equal(bannerConfigurationAt(undefined, {versions: [before]}, 99), undefined);
});
