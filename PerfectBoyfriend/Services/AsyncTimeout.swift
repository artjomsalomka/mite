import Foundation

enum TimeoutError: LocalizedError, Sendable {
    case timedOut

    var errorDescription: String? {
        "Die Anfrage hat zu lange gedauert. Bitte erneut versuchen."
    }
}

/// Protects a continuation against being resumed by both the request and its timeout. `NSLock`
/// is intentional: Firebase's async wrappers do not consistently cooperate with Swift task
/// cancellation, so an actor/task-group race can still wait forever for a cancelled request.
private final class TimeoutGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

/// Races `operation` against a hard deadline so a stalled network/connection (e.g. a long-lived
/// Firestore connection that stopped acking writes) can never leave a caller — and the UI state
/// it drives — hanging indefinitely. This deliberately does not use a task group: leaving a task
/// group waits for every child, while Firebase writes can ignore cancellation after the timeout.
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let gate = TimeoutGate(continuation)

        Task {
            do {
                gate.resume(with: .success(try await operation()))
            } catch {
                gate.resume(with: .failure(error))
            }
        }

        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                return
            }
            gate.resume(with: .failure(TimeoutError.timedOut))
        }
    }
}
