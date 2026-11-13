/** Pure validation for the private-profile callable. Keeping this separate from Firebase makes
 * the most important input/security boundary inexpensive to test on every local change. */
export class PersonalProfileValidationError extends Error {}

export function cleanPersonalDisplayName(value: unknown): string {
  if (typeof value !== "string") {
    throw new PersonalProfileValidationError("Bitte gib einen Namen ein.");
  }
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length < 1 || name.length > 40) {
    throw new PersonalProfileValidationError("Der Name muss zwischen 1 und 40 Zeichen lang sein.");
  }
  return name;
}

export function validatePersonalAvatarPath(value: unknown, uid: string): string | null {
  if (value === undefined || value === null || value === "") return null;
  const expectedPath = `userImages/${uid}/avatar.jpg`;
  if (typeof value !== "string" || value !== expectedPath) {
    throw new PersonalProfileValidationError("Ungültiger Avatarpfad.");
  }
  return value;
}
