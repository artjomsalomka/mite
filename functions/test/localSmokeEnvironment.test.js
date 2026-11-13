const test = require("node:test");
const assert = require("node:assert/strict");
const { configureLocalSmokeEnvironment } = require("../scripts/localSmokeEnvironment");

test("smoke tests use explicitly isolated local ports", () => {
  const env = { GCLOUD_PROJECT: "demo-mite-audit", FUNCTIONS_EMULATOR_HOST: "127.0.0.1:15001" };
  assert.equal(configureLocalSmokeEnvironment(env).functionBase, "http://127.0.0.1:15001/demo-mite-audit/us-central1");
  assert.equal(env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8080");
});
test("smoke tests reject remote hosts and malformed endpoints before admin initialization", () => {
  for (const host of ["firestore.googleapis.com:443", "example.org:8080", "127.0.0.1:8080/path", "user@localhost:9099", "localhost"]) {
    assert.throws(() => configureLocalSmokeEnvironment({ FIRESTORE_EMULATOR_HOST: host }));
  }
  assert.throws(() => configureLocalSmokeEnvironment({ GCLOUD_PROJECT: "../../remote" }));
});
