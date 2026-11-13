const assert = require("node:assert/strict");
const test = require("node:test");

const { isMutuallyCompatible } = require("../lib/singles/matchingCompatibility");

function profile(overrides = {}) {
  return {
    uid: "demo",
    displayName: "Demo",
    city: "Marburg",
    cityNormalized: "marburg",
    bio: "",
    age: 28,
    preferredAgeMinimum: 24,
    preferredAgeMaximum: 34,
    interests: ["Kultur"],
    budgetPreference: "mittel",
    moods: ["kulturell"],
    isMatchingActive: true,
    createdAt: {},
    updatedAt: {},
    ...overrides,
  };
}

test("matching compatibility requires shared city and mutual age ranges", () => {
  assert.equal(isMutuallyCompatible(profile(), profile({ uid: "other", age: 30 })), true);
  assert.equal(isMutuallyCompatible(profile(), profile({ uid: "other", cityNormalized: "giessen" })), false);
  assert.equal(isMutuallyCompatible(profile(), profile({ uid: "other", age: 38 })), false);
  assert.equal(isMutuallyCompatible(profile({ age: 38 }), profile({ uid: "other", age: 30 })), false);
});
