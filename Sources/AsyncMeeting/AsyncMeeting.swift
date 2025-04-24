import Foundation
import os

/// A type that sychronises two async callers via the rendezvous pattern. Optionally allows work to
/// be performed during the suspension of both tasks.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class AsyncMeeting: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?> = OSAllocatedUnfairLock(initialState: nil)

    /// Suspends a Task by waiting for a another task to rendezvous. After the two tasks
    /// complete the rendezvous, both tasks resume.
    ///
    /// Closureless version of `rendezvous`. See: ``rendezvous(_:)`` for more information
    func rendezvous() async {
        await rendezvous {}
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
    func rendezvous<T: Sendable>(_ perform: @Sendable () async throws -> T) async throws -> T {
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
    func rendezvous<T: Sendable>(_ perform: @Sendable () async -> T) async -> T {
        await resumeWithPeer()
        let result = await perform()
        await resumeWithPeer()
        return result
    }

    /// Suspends the caller until a second (peer) caller also suspends, after
    /// which both will resume.
    private func resumeWithPeer() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { newContinuation in
                continuation.withLock { peerContinuation in
                    if Task.isCancelled || peerContinuation != nil {
                        peerContinuation?.resume()
                        peerContinuation = nil
                        newContinuation.resume()
                    } else {
                        peerContinuation = newContinuation
                    }
                }
            }
        } onCancel: {
            continuation.withLock { $0?.resume() }
        }
    }
}
