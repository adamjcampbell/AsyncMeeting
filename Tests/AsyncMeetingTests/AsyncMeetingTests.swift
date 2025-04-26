@testable import AsyncMeeting
import ConcurrencyExtras
import Testing

struct AsyncMeetingTests {
    actor TestActor {
        var testInt = 0

        func increment() {
            testInt += 1
        }
    }

    @Test("Test a rendezvous with no work performed")
    func rendezvousWithNoPerform() async throws {
        try await withMainSerialExecutor {
            let actor = TestActor()
            let meeting = AsyncMeeting()

            let task = Task {
                try await meeting.rendezvous()
                await actor.increment()
            }

            await Task.megaYield()

            meeting.state.withLock { state in
                #expect(state.continuation != nil)
            }

            await #expect(actor.testInt == 0)

            try await meeting.rendezvous()
            try await task.value

            await #expect(actor.testInt == 1)
        }
    }

    @Test("Test rendezvous with work performed")
    func rendezvousWithPerform() async throws {
        try await withMainSerialExecutor {
            let actor = TestActor()
            let meeting = AsyncMeeting()

            let task = Task {
                try await meeting.rendezvous {
                    await actor.increment()
                }
            }

            await Task.megaYield()

            meeting.state.withLock { state in
                #expect(state.continuation != nil)
            }

            await #expect(actor.testInt == 0)

            try await meeting.rendezvous()
            await #expect(actor.testInt == 1)

            try await task.value
        }
    }

    @Test("Test timeout error is thrown")
    func timeout() async {
        let meeting = AsyncMeeting(timeout: .nanoseconds(1))

        await #expect(throws: AsyncMeeting.MeetingError.timeout) {
            try await meeting.rendezvous()
        }
    }

    @Test("Test cancellation is thrown without a continuation")
    func cancellationWithNoContinuationSet() async {
        await withMainSerialExecutor {
            let meeting = AsyncMeeting()

            let task = Task { try await meeting.rendezvous() }

            meeting.state.withLock { state in
                #expect(state.continuation == nil)
            }

            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }

    @Test("Test cancellation is thrown with a continuation")
    func cancellationWithContinuationSet() async {
        await withMainSerialExecutor {
            let meeting = AsyncMeeting()

            let task = Task { try await meeting.rendezvous() }

            await Task.megaYield()

            meeting.state.withLock { state in
                #expect(state.continuation != nil)
            }

            task.cancel()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }

            meeting.state.withLock { state in
                #expect(state.continuation == nil)
            }
        }
    }

    @Test("Peer count exceeded error")
    func peerCountExceeded() async throws {
        try await withMainSerialExecutor {
            let meeting = AsyncMeeting()

            let task1 = Task {
                try await meeting.rendezvous { await Task.yield() }
            }
            let task2 = Task {
                try await meeting.rendezvous { await Task.yield() }
            }

            await #expect(throws: AsyncMeeting.MeetingError.peerCountExceeded) {
                try await meeting.rendezvous()
            }

            await Task.megaYield()
            try await task1.value
            try await task2.value
        }
    }
}
