// Test scripts must never send admin writes to a cloud project or a remote emulator.
function configureLocalSmokeEnvironment(env = process.env) {
  env.GCLOUD_PROJECT ||= "demo-mite-submission";
  for (const [name, fallback] of Object.entries({
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099",
    FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5001",
  })) {
    env[name] ||= fallback;
    const endpoint = new URL(`http://${env[name]}`);
    if (!["127.0.0.1", "localhost", "[::1]"].includes(endpoint.hostname) ||
        !endpoint.port || endpoint.pathname !== "/" || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
      throw new Error(`${name} must point to a loopback host and explicit port.`);
    }
  }
  if (!/^[a-z0-9-]+$/.test(env.GCLOUD_PROJECT)) throw new Error("Invalid local test project ID.");
  return { functionBase: `http://${env.FUNCTIONS_EMULATOR_HOST}/${env.GCLOUD_PROJECT}/us-central1` };
}

module.exports = { configureLocalSmokeEnvironment };
