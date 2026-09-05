# uuid transitive patch — prepared for central verification

The baseline lock resolved uuid 9.0.1 through gaxios 6.7.1 and teeny-request 9.0.0.
Both installed callers use the named CommonJS `v4()` function without arguments
for multipart boundaries (gaxios build/src/gaxios.js, teeny-request build/src/index.js).
No application call to the advisory's v3/v5/v6 buffer path was established.

Scoped npm overrides pin only those two parent versions to uuid **11.1.1**.
The lock changes only the uuid node; firebase-admin 14.3.0 and firebase-functions
7.3.2 and their declared ranges remain unchanged. No Firebase downgrade or broad
major update is involved. Exact parent scoping intentionally requires re-review
when those parents change.

The maintainer advisory identifies 11.1.1 as patched. The tagged README and package
exports support CommonJS and the named v4() no-argument string API. Changes to
binary/timestamp UUID APIs do not affect the observed calls. This is a documented
compatibility assessment, not a runtime success claim.

Only `npm install --package-lock-only --ignore-scripts --no-audit --no-fund` ran.
No dependencies were executed, no audit/tests/builds ran, and zero remaining
warnings has NOT yet been verified. During the shared verification phase use
Node 22, `npm ci`, build/full unit, new `scripts/uuidDependencyCompatibility.test.mjs`,
`npm ls uuid`, `npm audit --omit=dev`, and multipart smoke tests for both parents.
The new test resolves uuid from each parent's actual module location, checks CJS
loading/v4 output and the patched v5 invalid-buffer behavior without a network call.

Official sources consulted 2026-09-05:

- [GHSA-w5hq-g745-h8pq](https://github.com/advisories/GHSA-w5hq-g745-h8pq)
- [uuid 11.1.1 README](https://github.com/uuidjs/uuid/blob/v11.1.1/README.md)
- [uuid 11.1.1 package exports](https://github.com/uuidjs/uuid/blob/v11.1.1/package.json)
- [npm scoped overrides](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#overrides)
