export interface DateGenerationRateLimitState {
  windowStartedAtMilliseconds: number;
  requestsInWindow: number;
  lastRequestedAtMilliseconds: number;
}

export type DateGenerationRateLimitResult =
  | { allowed: true; nextState: DateGenerationRateLimitState }
  | { allowed: false; reason: "too_fast" | "window_exhausted" };

// A generation can invoke a paid model call. This allows normal comparison of several ideas,
// while making accidental repeated taps and runaway automated use uneconomical.
const minimumIntervalMilliseconds = 7_000;
const windowMilliseconds = 10 * 60_000;
const maximumRequestsPerWindow = 6;

export function nextDateGenerationRateLimit(
  current: DateGenerationRateLimitState | undefined,
  nowMilliseconds: number,
): DateGenerationRateLimitResult {
  if (current && nowMilliseconds - current.lastRequestedAtMilliseconds < minimumIntervalMilliseconds) {
    return { allowed: false, reason: "too_fast" };
  }

  const isInCurrentWindow = current && nowMilliseconds - current.windowStartedAtMilliseconds < windowMilliseconds;
  if (isInCurrentWindow && current.requestsInWindow >= maximumRequestsPerWindow) {
    return { allowed: false, reason: "window_exhausted" };
  }

  return {
    allowed: true,
    nextState: isInCurrentWindow
      ? {
          windowStartedAtMilliseconds: current.windowStartedAtMilliseconds,
          requestsInWindow: current.requestsInWindow + 1,
          lastRequestedAtMilliseconds: nowMilliseconds,
        }
      : {
          windowStartedAtMilliseconds: nowMilliseconds,
          requestsInWindow: 1,
          lastRequestedAtMilliseconds: nowMilliseconds,
        },
  };
}
