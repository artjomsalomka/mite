const assert = require("node:assert/strict");
const test = require("node:test");

const { updatedStationProgress } = require("../lib/dates/journeyValidation.js");

test("station progress accepts only existing route stops and stays ordered", () => {
  assert.deepEqual(updatedStationProgress([0, 1, 2], [2, 0, 9], 1, true), [0, 1, 2]);
  assert.deepEqual(updatedStationProgress([0, 1, 2], [0, 1, 2], 1, false), [0, 2]);
});

test("station progress rejects malformed or foreign stop updates", () => {
  assert.throws(() => updatedStationProgress([0, 1], [], 2, true), /Ungültige Station/);
  assert.throws(() => updatedStationProgress([0, 1], [], "1", true), /Ungültige Station/);
  assert.throws(() => updatedStationProgress([0, 1], [], 1, "true"), /Ungültige Station/);
});
