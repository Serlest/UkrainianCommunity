import {strict as assert} from "node:assert";
import {createRequire} from "node:module";
import {test} from "node:test";
const require = createRequire(import.meta.url);

for (const consumer of ["gaxios", "teeny-request"]) {
  test(`${consumer} resolves patched CommonJS uuid and its v4() string API`, () => {
    const consumerRequire = createRequire(require.resolve(consumer));
    const uuid = consumerRequire("uuid");
    assert.equal(consumerRequire("uuid/package.json").version, "11.1.1");
    const value = uuid.v4();
    assert.equal(uuid.validate(value), true);
    assert.equal(uuid.version(value), 4);
    // Regression for the advisory, independent of the consumers' v4-only usage.
    assert.throws(() => uuid.v5("fixture", uuid.v5.DNS, new Uint8Array(8), 4), RangeError);
    assert.doesNotThrow(() => require(consumer));
  });
}
