const assert = require("node:assert/strict");
const test = require("node:test");

const { resumableInviteCode } = require("../lib/couples/pendingCoupleRecovery");

test("only the creator can resume an unfinished couple connection", () => {
  const pendingCouple = {
    status: "pending",
    createdByUid: "artem",
    memberUids: ["artem"],
    inviteCode: "042817",
  };

  assert.equal(resumableInviteCode(pendingCouple, "artem"), "042817");
  assert.equal(resumableInviteCode(pendingCouple, "alex"), null);
  assert.equal(resumableInviteCode({ ...pendingCouple, status: "active" }, "artem"), null);
  assert.equal(resumableInviteCode({ ...pendingCouple, memberUids: ["artem", "alex"] }, "artem"), null);
  assert.equal(resumableInviteCode({ ...pendingCouple, inviteCode: "not-a-code" }, "artem"), null);
});
