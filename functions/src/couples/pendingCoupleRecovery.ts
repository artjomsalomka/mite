/**
 * Returns the original invite code only for the person who created an unfinished connection.
 * This makes a retried create request safe after a client-side timeout without ever exposing an
 * invite code to the person who merely joined it.
 */
export function resumableInviteCode(couple: Record<string, unknown> | undefined, creatorUid: string): string | null {
  if (!couple || couple.status !== "pending" || couple.createdByUid !== creatorUid) return null;

  const memberUids = couple.memberUids;
  const inviteCode = couple.inviteCode;
  if (!Array.isArray(memberUids) || memberUids.length !== 1 || memberUids[0] !== creatorUid) return null;
  return typeof inviteCode === "string" && /^\d{6}$/.test(inviteCode) ? inviteCode : null;
}
