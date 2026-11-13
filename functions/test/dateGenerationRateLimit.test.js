const assert = require("node:assert/strict");
const test = require("node:test");

const { nextDateGenerationRateLimit } = require("../lib/dateSuggestions/dateGenerationRateLimit.js");

test("date generation throttle rejects accidental repeated taps", () => {
  const first = nextDateGenerationRateLimit(undefined, 10_000);
  assert.equal(first.allowed, true);
  const second = nextDateGenerationRateLimit(first.nextState, 12_000);
  assert.deepEqual(second, { allowed: false, reason: "too_fast" });
});

test("date generation throttle allows six requests per ten-minute window then resets", () => {
  let state;
  for (let index = 0; index < 6; index += 1) {
    const decision = nextDateGenerationRateLimit(state, index * 8_000);
    assert.equal(decision.allowed, true);
    state = decision.nextState;
  }
  assert.deepEqual(nextDateGenerationRateLimit(state, 50_000), { allowed: false, reason: "window_exhausted" });
  assert.equal(nextDateGenerationRateLimit(state, 10 * 60_000 + 1).allowed, true);
});
