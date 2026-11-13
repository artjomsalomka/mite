const assert = require("node:assert/strict");
const test = require("node:test");

const { nextChatRateLimit } = require("../lib/singles/chatRateLimit");

test("chat throttle permits normal messages but rejects rapid repeats", () => {
  const first = nextChatRateLimit(undefined, 10_000);
  assert.equal(first.allowed, true);
  assert.deepEqual(first.nextState, {
    windowStartedAtMilliseconds: 10_000,
    sentInWindow: 1,
    lastSentAtMilliseconds: 10_000,
  });

  const rapidRepeat = nextChatRateLimit(first.nextState, 10_800);
  assert.deepEqual(rapidRepeat, { allowed: false, reason: "too_fast" });

  const normalFollowUp = nextChatRateLimit(first.nextState, 11_300);
  assert.equal(normalFollowUp.allowed, true);
  assert.equal(normalFollowUp.nextState.sentInWindow, 2);
});

test("chat throttle caps a burst and resets after its one-minute window", () => {
  let state;
  for (let index = 0; index < 8; index += 1) {
    const result = nextChatRateLimit(state, 10_000 + (index * 1_300));
    assert.equal(result.allowed, true);
    state = result.nextState;
  }

  assert.deepEqual(nextChatRateLimit(state, 21_000), { allowed: false, reason: "window_exhausted" });
  const afterWindow = nextChatRateLimit(state, 70_000);
  assert.equal(afterWindow.allowed, true);
  assert.equal(afterWindow.nextState.sentInWindow, 1);
});
