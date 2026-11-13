export interface ChatRateLimitState {
  windowStartedAtMilliseconds: number;
  sentInWindow: number;
  lastSentAtMilliseconds: number;
}

export type ChatRateLimitResult =
  | { allowed: true; nextState: ChatRateLimitState }
  | { allowed: false; reason: "too_fast" | "window_exhausted" };

// This is deliberately modest: it stops copy/paste floods and accidental double taps without
// making an ordinary first conversation feel mechanically limited.
const minimumIntervalMilliseconds = 1_200;
const windowMilliseconds = 60_000;
const maximumMessagesPerWindow = 8;

export function nextChatRateLimit(
  current: ChatRateLimitState | undefined,
  nowMilliseconds: number,
): ChatRateLimitResult {
  if (current && nowMilliseconds - current.lastSentAtMilliseconds < minimumIntervalMilliseconds) {
    return { allowed: false, reason: "too_fast" };
  }

  const isInCurrentWindow = current && nowMilliseconds - current.windowStartedAtMilliseconds < windowMilliseconds;
  if (isInCurrentWindow && current.sentInWindow >= maximumMessagesPerWindow) {
    return { allowed: false, reason: "window_exhausted" };
  }

  return {
    allowed: true,
    nextState: isInCurrentWindow
      ? {
          windowStartedAtMilliseconds: current.windowStartedAtMilliseconds,
          sentInWindow: current.sentInWindow + 1,
          lastSentAtMilliseconds: nowMilliseconds,
        }
      : {
          windowStartedAtMilliseconds: nowMilliseconds,
          sentInWindow: 1,
          lastSentAtMilliseconds: nowMilliseconds,
        },
  };
}
