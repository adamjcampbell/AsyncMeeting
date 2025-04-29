import Foundation
import os

/// A type that sychronises two async callers via the rendezvous pattern. Optionally allows work to
/// be performed during the suspension of both tasks. Supports a timeout.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public final class AsyncMeeting: Sendable {
    let state: OSAllocatedUnfairLock<State> = .init(initialState: .init())
    let timeoutDuration: Duration?

    struct State {
        var peerCount: UInt = 0
        var continuation: CheckedContinuation<Void, any Error>?
    }

    public enum MeetingError: Error {
        case timeout
        case peerCountExceeded
    }

    /// Initialises an async meeting of two async callers.
    /// - Parameter timeoutDuration: How long to wait before throwing
    /// a timeout error. If `nil` is passed the wait is indefinite.
    public init(timeout timeoutDuration: Duration? = nil) {
        self.timeoutDuration = timeoutDuration
    }

    /// Suspends a Task by waiting for a another task to rendezvous. After the two tasks
    /// complete the rendezvous, both tasks resume.
    ///
    /// Closureless version of `rendezvous`. See: ``rendezvous(_:)`` for more information
    public func rendezvous() async throws {
        try await rendezvous {}
    }

    /// Suspends a Task by waiting for a another task to rendezvous. Runs the provided
    /// work while both task are suspended. After the two tasks complete the
    /// rendezvous, both tasks resume.
    ///
    /// The rendezvous works in four steps for both 'peers':
    ///
    /// 1. Wait for the other peer to begin the rendezvous.
    /// 2. Perform the work (passed perform closure).
    /// 3. Wait for the other peer to complete (2).
    /// 4. Return the result of the work.
    ///
    /// - Parameters:
    ///   - perform: A closure to perform during the rendezvous (while both
    ///   tasks are suspended).
    public func rendezvous<T: Sendable>(_ perform: @escaping @Sendable () async throws -> T) async throws -> T {
        try await rendezvous { () -> Result<T, any Error> in
            do {
                return .success(try await perform())
            } catch {
                return .failure(error)
            }
        }.get()
    }

    /// Suspends a Task by waiting for a another task to rendezvous. Runs the provided
    /// work while both task are suspended. After the two tasks complete the
    /// rendezvous, both tasks resume.
    ///
    /// The rendezvous works in four steps for both 'peers':
    /// 1. Wait for the other peer to begin the rendezvous.
    /// 2. Perform the work (passed perform closure).
    /// 3. Wait for the other peer to complete (2).
    /// 4. Return the result of the work.
    ///
    /// - Parameters:
    ///   - perform: A closure to perform during the rendezvous (while both
    ///   tasks are suspended).
    public func rendezvous<T: Sendable>(_ perform: @escaping @Sendable () async -> T) async throws -> T {
        // Ensure we only have at most one other peer already active
        // before incrementing the peer count
        try state.withLock { state in
            guard state.peerCount <= 1 else {
                throw MeetingError.peerCountExceeded
            }

            state.peerCount += 1
        }

        // Given the peer count has been incremented,
        // decrement the peer count on exit
        defer { state.withLock { $0.peerCount -= 1 } }

        // Use a task group in order to race our main task against
        // a timeout task
        let result = try await withThrowingTaskGroup { group in
            // Main rendezvous task
            group.addTask {
                // Wait for both peers to synchronise
                try await self.resumeWithPeer()
                // Both peers perform work
                let result = await perform()
                // Wait for both peers to synchronise
                // after the performed work
                try await self.resumeWithPeer()
                // Return any work back to the caller
                return result
            }

            // If we have a timeout add the racing timeout task
            if let timeoutDuration {
                // Sleep for the timeout duration or
                // complete the task group with an error
                group.addTask {
                    try await Task.sleep(for: timeoutDuration)
                    throw MeetingError.timeout
                }
            }

            // We only care about the next result from the main
            // task. Nil is not an issue here as it is only returned
            // if no tasks are added. Hence the !
            return try await group.next()!
        }

        return result
    }

    /// Suspends the caller until a second (peer) caller also suspends, after
    /// which both will resume.
    private func resumeWithPeer() async throws {
        // Take the continuation by removing from state and returning it
        // if present while under lock. Otherwise returns nil.
        @Sendable func takeContinuation() -> CheckedContinuation<Void, any Error>? {
            state.withLock { state in
                if let continuation = state.continuation {
                    state.continuation = nil
                    return continuation
                } else {
                    return nil
                }
            }
        }

        // Respond to cancellation
        try await withTaskCancellationHandler {
            // Create a continuation
            try await withCheckedThrowingContinuation { continuation in
                do {
                    // Check that we haven't already been cancelled
                    try Task.checkCancellation()

                    // If we have a stored continuation, resume both tasks.
                    // Else store the continuation in state.
                    if let storedContinuation = takeContinuation() {
                        storedContinuation.resume()
                        continuation.resume()
                    } else {
                        state.withLock { $0.continuation = continuation }
                    }
                } catch {
                    // Report any errors (cancellation) to the caller
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // On cancellation aquire a lock on the state, if we have a
            // stored cancellation: clear it and propagate the cancellation
            // as an error
            takeContinuation()?.resume(throwing: CancellationError())
        }
    }
}
