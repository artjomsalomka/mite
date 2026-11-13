/** 6-digit numeric invite code, e.g. "042817". Leading zeros allowed — always compared as a string. */
export function generateInviteCode(): string {
  const n = Math.floor(Math.random() * 1_000_000);
  return n.toString().padStart(6, "0");
}
