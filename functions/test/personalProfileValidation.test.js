const assert = require("node:assert/strict");
const test = require("node:test");

const {
  PersonalProfileValidationError,
  cleanPersonalDisplayName,
  validatePersonalAvatarPath,
} = require("../lib/users/personalProfileValidation.js");

test("personal profile name is trimmed and normalized", () => {
  assert.equal(cleanPersonalDisplayName("  Artem   Zalomka  "), "Artem Zalomka");
});

test("personal profile rejects missing or overlong names", () => {
  assert.throws(() => cleanPersonalDisplayName("   "), PersonalProfileValidationError);
  assert.throws(() => cleanPersonalDisplayName("x".repeat(41)), PersonalProfileValidationError);
  assert.throws(() => cleanPersonalDisplayName(null), PersonalProfileValidationError);
});

test("personal avatar path accepts only the authenticated person's exact private path", () => {
  const uid = "viewer-123";
  const path = "userImages/viewer-123/avatar.jpg";
  assert.equal(validatePersonalAvatarPath(path, uid), path);
  assert.equal(validatePersonalAvatarPath(null, uid), null);
  assert.equal(validatePersonalAvatarPath(undefined, uid), null);
  assert.throws(
    () => validatePersonalAvatarPath("userImages/other-person/avatar.jpg", uid),
    PersonalProfileValidationError
  );
  assert.throws(
    () => validatePersonalAvatarPath("profileImages/viewer-123/avatar.jpg", uid),
    PersonalProfileValidationError
  );
});
