import Foundation
import os

/// A type that sychronises two async callers via the rendezvous pattern. Optionally allows work to
/// be performed during the suspension of both tasks.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public final class AsyncMeeting: Sendable {
    let state: OSAllocatedUnfairLock<State> = .init(initialState: .init())
    let timeoutDuration: Duration?

    struct State {
        var peerCount: UInt = 0
        var continuation: CheckedContinuation<Void, Never>?
    }

    public enum MeetingError: Error {
        case timeout
        case peerCountExceeded
    }

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
        defer { state.withLock { $0.peerCount -= 1 } }

        try state.withLock { state in
            guard state.peerCount <= 1 else {
                throw MeetingError.peerCountExceeded
            }

            state.peerCount += 1
        }

        let result = try await withThrowingTaskGroup { group in
            group.addTask {
                await self.resumeWithPeer()
                let result = await perform()
                await self.resumeWithPeer()
                return result
            }

            if let timeoutDuration {
                group.addTask {
                    try await Task.sleep(for: timeoutDuration)
                    throw MeetingError.timeout
                }
            }

            return try await group.next()!
        }

        return result
    }

    /// Suspends the caller until a second (peer) caller also suspends, after
    /// which both will resume.
    private func resumeWithPeer() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { newContinuation in
                state.withLock { state in
                    if Task.isCancelled || state.continuation != nil {
                        state.continuation?.resume()
                        state.continuation = nil
                        newContinuation.resume()
                    } else {
                        state.continuation = newContinuation
                    }
                }
            }
        } onCancel: {
            state.withLock { state in
                if let continuation = state.continuation {
                    state.continuation = nil
                    continuation.resume()
                }
            }
        }
    }
}
